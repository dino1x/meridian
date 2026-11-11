// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMUSD, IERC20} from "./interfaces/IMezo.sol";

/// @title BatchRateAuction
/// @notice Uniform-clearing-price Treasury auction for Chronos PT-MUSD series.
///         Discovers fixed MUSD yields across 30D, 90D, and 180D maturities without a custom AMM.
contract BatchRateAuction {
    struct SellOrder {
        address seller;
        uint256 ptAmount;
        uint256 minPriceWad; // e.g., 0.985e18 MUSD per 1.00 PT-MUSD
        bool settled;
    }

    struct BuyBid {
        address buyer;
        uint256 musdCommitted;
        uint256 maxPriceWad; // e.g., 0.990e18 MUSD per 1.00 PT-MUSD
        bool settled;
    }

    struct EpochFixing {
        uint256 seriesId;
        uint256 maturity;
        address ptToken;
        uint256 clearingPriceWad;
        uint256 impliedFixedAPR_Bps;
        uint256 totalClearedPT;
        uint256 settledAt;
        bool settled;
    }

    IMUSD public immutable musd;
    address public feeTreasury;
    uint256 public constant SETTLEMENT_FEE_BPS = 5;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public nextAuctionId = 1;

    mapping(uint256 => EpochFixing) public fixings;
    mapping(uint256 => SellOrder[]) public sellOrders;
    mapping(uint256 => BuyBid[]) public buyBids;
    mapping(uint256 => uint256) public latestSeriesFixedRateBps;

    event AuctionOpened(uint256 indexed auctionId, uint256 indexed seriesId, address ptToken, uint256 maturity);
    event SellOrderPlaced(uint256 indexed auctionId, address indexed seller, uint256 ptAmount, uint256 minPriceWad);
    event BuyBidPlaced(uint256 indexed auctionId, address indexed buyer, uint256 musdAmount, uint256 maxPriceWad);
    event FixingSettled(
        uint256 indexed auctionId,
        uint256 indexed seriesId,
        uint256 clearingPriceWad,
        uint256 impliedFixedAPR_Bps,
        uint256 totalClearedPT
    );

    error AuctionAlreadySettled();
    error InvalidPriceBounds();

    constructor(address _musd) {
        require(_musd != address(0), "Zero address");
        musd = IMUSD(_musd);
        feeTreasury = msg.sender;
    }

    function setFeeTreasury(address _feeTreasury) external {
        require(_feeTreasury != address(0), "Zero address");
        feeTreasury = _feeTreasury;
    }

    function openAuction(uint256 seriesId, address ptToken, uint256 maturity) external returns (uint256 auctionId) {
        require(ptToken != address(0), "Zero address");
        auctionId = nextAuctionId++;
        fixings[auctionId] = EpochFixing({
            seriesId: seriesId,
            maturity: maturity,
            ptToken: ptToken,
            clearingPriceWad: 0,
            impliedFixedAPR_Bps: 0,
            totalClearedPT: 0,
            settledAt: 0,
            settled: false
        });
        emit AuctionOpened(auctionId, seriesId, ptToken, maturity);
    }

    function placeSellOrder(uint256 auctionId, uint256 ptAmount, uint256 minPriceWad) external {
        EpochFixing storage f = fixings[auctionId];
        if (f.settled) revert AuctionAlreadySettled();
        if (minPriceWad == 0 || minPriceWad > 1e18) revert InvalidPriceBounds();

        sellOrders[auctionId].push(
            SellOrder({seller: msg.sender, ptAmount: ptAmount, minPriceWad: minPriceWad, settled: false})
        );
        emit SellOrderPlaced(auctionId, msg.sender, ptAmount, minPriceWad);
        require(IERC20(f.ptToken).transferFrom(msg.sender, address(this), ptAmount), "ERC20 call failed");
    }

    function placeBuyBid(uint256 auctionId, uint256 musdAmount, uint256 maxPriceWad) external {
        EpochFixing storage f = fixings[auctionId];
        if (f.settled) revert AuctionAlreadySettled();
        if (maxPriceWad == 0 || maxPriceWad > 1e18) revert InvalidPriceBounds();

        buyBids[auctionId].push(
            BuyBid({buyer: msg.sender, musdCommitted: musdAmount, maxPriceWad: maxPriceWad, settled: false})
        );
        emit BuyBidPlaced(auctionId, msg.sender, musdAmount, maxPriceWad);
        require(musd.transferFrom(msg.sender, address(this), musdAmount), "ERC20 call failed");
    }

    /// @notice Permissionless uniform-price batch settlement: clears all qualifying orders at `clearingPriceWad`.
    function settleAuction(uint256 auctionId, uint256 clearingPriceWad) external returns (uint256 clearedPT) {
        EpochFixing storage f = fixings[auctionId];
        if (f.settled) revert AuctionAlreadySettled();
        if (clearingPriceWad == 0 || clearingPriceWad > 1e18) revert InvalidPriceBounds();

        SellOrder[] storage asks = sellOrders[auctionId];
        BuyBid[] storage bids = buyBids[auctionId];

        uint256 availablePT = 0;
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].minPriceWad <= clearingPriceWad) {
                availablePT += asks[i].ptAmount;
            }
        }

        uint256 demandedPT = 0;
        for (uint256 j = 0; j < bids.length; j++) {
            if (bids[j].maxPriceWad >= clearingPriceWad) {
                demandedPT += (bids[j].musdCommitted * 1e18) / clearingPriceWad;
            }
        }

        clearedPT = availablePT < demandedPT ? availablePT : demandedPT;

        uint256 dt = f.maturity > block.timestamp ? f.maturity - block.timestamp : 30 days;
        // Implied annualized simple rate in bps: ((1e18 - clearingPrice) / clearingPrice) * (365 days / dt) * 10000
        uint256 discountWad = 1e18 - clearingPriceWad;
        uint256 impliedBps = ((discountWad * 365 days * 10_000) / clearingPriceWad) / dt;

        // Effects before external interactions
        f.clearingPriceWad = clearingPriceWad;
        f.impliedFixedAPR_Bps = impliedBps;
        f.totalClearedPT = clearedPT;
        f.settledAt = block.timestamp;
        f.settled = true;

        latestSeriesFixedRateBps[f.seriesId] = impliedBps;

        emit FixingSettled(auctionId, f.seriesId, clearingPriceWad, impliedBps, clearedPT);

        // Fill qualifying sellers up to clearedPT and refund unmatched PT
        uint256 remPTToSell = clearedPT;
        for (uint256 i = 0; i < asks.length; i++) {
            asks[i].settled = true;
            if (asks[i].minPriceWad <= clearingPriceWad && remPTToSell > 0) {
                uint256 fillPT = asks[i].ptAmount <= remPTToSell ? asks[i].ptAmount : remPTToSell;
                remPTToSell -= fillPT;
                uint256 musdProceeds = (fillPT * clearingPriceWad) / 1e18;
                uint256 fee = feeTreasury != address(0)
                    ? (fillPT * clearingPriceWad * SETTLEMENT_FEE_BPS) / (1e18 * BPS_DENOMINATOR)
                    : 0;
                uint256 sellerNet = musdProceeds - fee;
                if (fee > 0) {
                    require(musd.transfer(feeTreasury, fee), "ERC20 call failed");
                }
                require(musd.transfer(asks[i].seller, sellerNet), "ERC20 call failed");
                if (asks[i].ptAmount > fillPT) {
                    require(IERC20(f.ptToken).transfer(asks[i].seller, asks[i].ptAmount - fillPT), "ERC20 call failed");
                }
            } else {
                require(IERC20(f.ptToken).transfer(asks[i].seller, asks[i].ptAmount), "ERC20 call failed");
            }
        }

        // Fill qualifying buyers up to clearedPT and refund unmatched MUSD
        uint256 remPTToBuy = clearedPT;
        for (uint256 j = 0; j < bids.length; j++) {
            bids[j].settled = true;
            if (bids[j].maxPriceWad >= clearingPriceWad && remPTToBuy > 0) {
                uint256 maxPTForBid = (bids[j].musdCommitted * 1e18) / clearingPriceWad;
                uint256 fillPT = maxPTForBid <= remPTToBuy ? maxPTForBid : remPTToBuy;
                remPTToBuy -= fillPT;
                uint256 musdSpent = (fillPT * clearingPriceWad) / 1e18;
                require(IERC20(f.ptToken).transfer(bids[j].buyer, fillPT), "ERC20 call failed");
                if (bids[j].musdCommitted > musdSpent) {
                    require(musd.transfer(bids[j].buyer, bids[j].musdCommitted - musdSpent), "ERC20 call failed");
                }
            } else {
                require(musd.transfer(bids[j].buyer, bids[j].musdCommitted), "ERC20 call failed");
            }
        }
    }

    function getYieldCurveBps() external view returns (uint256 rate30d, uint256 rate90d, uint256 rate180d) {
        return (latestSeriesFixedRateBps[1], latestSeriesFixedRateBps[2], latestSeriesFixedRateBps[3]);
    }
}

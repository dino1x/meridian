// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20,
    IStabilityPool,
    IMUSDSavingsRate,
    IPriceFeed,
    ITroveManager
} from "./interfaces/IMezo.sol";

/// @title BackstopVault
/// @notice B.Protocol-inspired ERC-4626 MUSD Stability Pool Vault with an On-Chain BTC Dutch Auction House.
/// @dev Deploys MUSD into Mezo StabilityPool (0x1CCA7E410eE41739792eA0A24e00349Dd247680e).
///      When liquidations yield BTC collateral gains, harvests the BTC into numbered Auction Lots
///      whose price decays linearly from 100% of PriceFeed oracle price down to 92% over 2 hours.
///      Buyers bid MUSD ("Gavel Strike"), automatically compounding MUSD back into StabilityPool!
contract BackstopVault {
    string public constant name = "Backstop Consignment Share";
    string public constant symbol = "bstMUSD";
    uint8 public constant decimals = 18;

    IERC20 public immutable musd;
    IStabilityPool public immutable stabilityPool;
    IMUSDSavingsRate public immutable smusd;
    IPriceFeed public immutable priceFeed;
    ITroveManager public immutable troveManager;

    address public feeTreasury;
    uint256 public totalSupply;

    /// @notice Dutch auction parameters: starts at 100% of oracle price, decays to 92% over 2 hours
    uint256 public constant AUCTION_DURATION = 2 hours;
    uint256 public constant MIN_PRICE_BPS = 9200; // 92.00% floor
    /// @notice 0.50% Auction Buyer's Premium on bidOnLot (explicit protocol revenue model)
    uint256 public constant BUYER_PREMIUM_BPS = 50;
    /// @notice 2.00% House Premium for legacy strikeGavel helper
    uint256 public constant HOUSE_PREMIUM_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    mapping(address => uint256) public balanceOf;

    struct AuctionLot {
        uint256 lotId;
        uint256 btcAmount;
        uint256 startPriceUSDPerBTC;
        uint256 startTime;
        address winningBidder;
        uint256 clearedMUSD;
        bool settled;
    }

    uint256 public nextLotId = 1;
    mapping(uint256 => AuctionLot) public lots;

    event ConsignmentDeposited(address indexed depositor, uint256 musdAmount, uint256 sharesMinted);
    event ConsignmentWithdrawn(address indexed depositor, uint256 sharesBurned, uint256 musdReturned);
    event LotCatalogued(uint256 indexed lotId, uint256 btcAmount, uint256 startPriceUSDPerBTC, uint256 startTime);
    event GavelStruck(
        uint256 indexed lotId,
        address indexed buyer,
        uint256 btcPurchased,
        uint256 musdPaid,
        uint256 houseFeeMUSD
    );

    error ZeroAmount();
    error InsufficientShares();
    error NoCollateralGainAvailable();
    error LotNotActive();
    error SlippageExceeded(uint256 requiredMUSD, uint256 maxMUSD);

    constructor(
        address _musd,
        address _stabilityPool,
        address _smusd,
        address _priceFeed,
        address _troveManager,
        address _feeTreasury
    ) {
        require(_musd != address(0), "Zero address");
        require(_stabilityPool != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        musd = IERC20(_musd);
        stabilityPool = IStabilityPool(_stabilityPool);
        smusd = IMUSDSavingsRate(_smusd);
        priceFeed = IPriceFeed(_priceFeed);
        troveManager = ITroveManager(_troveManager);
        feeTreasury = _feeTreasury;
    }

    /// @notice Total MUSD value backing vault shares (compounded SP deposit + liquid MUSD).
    function totalAssets() public view returns (uint256) {
        return stabilityPool.getCompoundedMUSDDeposit(address(this)) + musd.balanceOf(address(this));
    }

    function deposit(uint256 musdAmount) external returns (uint256 shares) {
        if (musdAmount == 0) revert ZeroAmount();
        uint256 assetsBefore = totalAssets();

        shares = (totalSupply == 0 || assetsBefore == 0)
            ? musdAmount
            : (musdAmount * totalSupply) / assetsBefore;

        // Effects before external interactions
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
        emit ConsignmentDeposited(msg.sender, musdAmount, shares);

        // Interactions
        require(musd.transferFrom(msg.sender, address(this), musdAmount), "ERC20 call failed");
        require(musd.approve(address(stabilityPool), musdAmount), "ERC20 call failed");
        stabilityPool.provideToSP(musdAmount);
    }

    function redeem(uint256 shares) public returns (uint256 musdOut) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < shares) revert InsufficientShares();

        musdOut = (shares * totalAssets()) / totalSupply;

        // Effects before external interactions
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        emit ConsignmentWithdrawn(msg.sender, shares, musdOut);

        // Interactions
        uint256 liquid = musd.balanceOf(address(this));
        if (liquid < musdOut) {
            stabilityPool.withdrawFromSP(musdOut - liquid);
        }
        require(musd.transfer(msg.sender, musdOut), "ERC20 call failed");
    }

    function withdraw(uint256 shares) external returns (uint256 musdOut) {
        return redeem(shares);
    }

    /// @notice Harvests pending BTC liquidation gains from StabilityPool and opens a numbered Dutch Auction Lot.
    function catalogueLiquidationLot() external returns (uint256 lotId) {
        uint256 pendingGain = stabilityPool.getDepositorCollateralGain(address(this));
        if (pendingGain == 0) revert NoCollateralGainAvailable();

        uint256 btcPrice = priceFeed.fetchPrice();

        // Effects before external interactions
        lotId = nextLotId++;
        lots[lotId] = AuctionLot({
            lotId: lotId,
            btcAmount: pendingGain,
            startPriceUSDPerBTC: btcPrice,
            startTime: block.timestamp,
            winningBidder: address(0),
            clearedMUSD: 0,
            settled: false
        });
        emit LotCatalogued(lotId, pendingGain, btcPrice, block.timestamp);

        // Interactions
        stabilityPool.withdrawFromSP(0);
    }

    /// @notice Returns the current Dutch auction ask price (in MUSD) to purchase the BTC lot.
    function currentLotAskMUSD(uint256 lotId) public view returns (uint256 askMUSD) {
        (askMUSD, ) = getCurrentLotCostMUSD(lotId);
    }

    /// @notice Returns the current Dutch auction price (in MUSD) and effective BTC price.
    function getCurrentLotCostMUSD(uint256 lotId) public view returns (uint256 musdCost, uint256 pricePerBTC) {
        AuctionLot memory lot = lots[lotId];
        if (lot.btcAmount == 0 || lot.settled) return (0, 0);

        uint256 elapsed = block.timestamp - lot.startTime;
        uint256 currentBps;
        if (elapsed >= AUCTION_DURATION) {
            currentBps = MIN_PRICE_BPS;
        } else {
            uint256 maxDropBps = BPS_DENOMINATOR - MIN_PRICE_BPS; // 800 bps (8% max discount)
            uint256 dropBps = (maxDropBps * elapsed) / AUCTION_DURATION;
            currentBps = BPS_DENOMINATOR - dropBps;
        }

        pricePerBTC = (lot.startPriceUSDPerBTC * currentBps) / BPS_DENOMINATOR;
        musdCost = (lot.btcAmount * lot.startPriceUSDPerBTC * currentBps) / (BPS_DENOMINATOR * 1e18);
    }

    /// @notice Bids on an active Dutch auction lot with slippage protection (`maxMUSD`).
    ///         Charges a 0.50% Buyer's Premium to `feeTreasury` and re-deposits 100% of `askMUSD` into `StabilityPool`.
    function bidOnLot(uint256 lotId, uint256 maxMUSD)
        external
        returns (uint256 btcPurchased, uint256 totalPayable)
    {
        AuctionLot storage lot = lots[lotId];
        if (lot.btcAmount == 0 || lot.settled) revert LotNotActive();

        uint256 askMUSD = currentLotAskMUSD(lotId);
        uint256 buyerPremium = (askMUSD * BUYER_PREMIUM_BPS) / BPS_DENOMINATOR;
        totalPayable = askMUSD + buyerPremium;
        if (totalPayable > maxMUSD) revert SlippageExceeded(totalPayable, maxMUSD);

        btcPurchased = lot.btcAmount;

        // Effects before external interactions
        lot.settled = true;
        lot.winningBidder = msg.sender;
        lot.clearedMUSD = askMUSD;
        emit GavelStruck(lotId, msg.sender, btcPurchased, askMUSD, buyerPremium);

        // Interactions
        require(musd.transferFrom(msg.sender, address(this), totalPayable), "ERC20 call failed");
        if (buyerPremium > 0) {
            require(musd.transfer(feeTreasury, buyerPremium), "ERC20 call failed");
        }
        if (askMUSD > 0) {
            require(musd.approve(address(stabilityPool), askMUSD), "ERC20 call failed");
            stabilityPool.provideToSP(askMUSD);
        }

        (bool ok, ) = msg.sender.call{value: btcPurchased}("");
        require(ok, "BTC delivery failed");
    }

    /// @notice Strikes the gavel on an active BTC lot: pulls MUSD from the buyer, sends BTC to the buyer,
    ///         takes the 2% House Premium, and re-deposits the net MUSD proceeds into StabilityPool!
    function strikeGavel(uint256 lotId) external returns (uint256 btcPurchased, uint256 musdPaid) {
        AuctionLot storage lot = lots[lotId];
        if (lot.btcAmount == 0 || lot.settled) revert LotNotActive();

        (musdPaid, ) = getCurrentLotCostMUSD(lotId);
        btcPurchased = lot.btcAmount;
        uint256 houseFee = (musdPaid * HOUSE_PREMIUM_BPS) / BPS_DENOMINATOR;
        uint256 netToSP = musdPaid - houseFee;

        // Effects before external interactions
        lot.settled = true;
        lot.winningBidder = msg.sender;
        lot.clearedMUSD = musdPaid;
        emit GavelStruck(lotId, msg.sender, btcPurchased, musdPaid, houseFee);

        // Interactions
        require(musd.transferFrom(msg.sender, address(this), musdPaid), "ERC20 call failed");
        if (houseFee > 0) {
            require(musd.transfer(feeTreasury, houseFee), "ERC20 call failed");
        }
        if (netToSP > 0) {
            require(musd.approve(address(stabilityPool), netToSP), "ERC20 call failed");
            stabilityPool.provideToSP(netToSP);
        }

        (bool ok, ) = msg.sender.call{value: btcPurchased}("");
        require(ok, "BTC delivery failed");
    }

    receive() external payable {}
}

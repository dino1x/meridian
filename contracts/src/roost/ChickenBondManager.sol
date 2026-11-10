// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IMUSD,
    IMUSDSavingsRate,
    IStabilityPool,
    IBorrowerOperations,
    ITroveManager,
    IPriceFeed
} from "./interfaces/IMezo.sol";
import {bMUSDToken} from "./bMUSDToken.sol";
import {BondNFT, IChickenBondManagerView} from "./BondNFT.sol";

/// @title ChickenBondManager
/// @notice Liquity Chicken Bonds ported natively to Mezo MUSD, sMUSD, StabilityPool & BorrowerOperations.
/// @dev Manages the three capital buckets (Pending, Reserve, Permanent) and a 1-tx BTC Trove-to-Bond Zap
///      that enforces Recovery Mode (TCR < 150%) and live Mezo protocol parameter reads.
contract ChickenBondManager is IChickenBondManagerView {
    IMUSD public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    IStabilityPool public immutable stabilityPool;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IPriceFeed public immutable priceFeed;

    bMUSDToken public immutable bMusd;
    BondNFT public immutable bondNft;

    address public feeTreasury;
    address public owner;

    /// @notice Accrual parameter alpha (in seconds): time to reach 50% of asymptotic cap. Default: 15 days.
    uint256 public immutable accrualParameterAlpha;
    /// @notice Protocol Chicken-In fee in basis points (100 bps = 1.00% explicit revenue model)
    uint256 public constant CHICKEN_IN_FEE_BPS = 100;
    /// @notice Portion of net Surplus routed to Permanent Bucket on Chicken-In (2500 bps = 25%)
    uint256 public constant PERMANENT_BUCKET_SPLIT_BPS = 2500;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_BOND_AMOUNT = 100e18; // 100 MUSD minimum bond

    /// @notice Capital Buckets (denominated in MUSD principal deployed in sMUSD / StabilityPool)
    uint256 public pendingBucketMUSD;
    uint256 public reserveBucketMUSD;
    uint256 public permanentBucketMUSD;

    uint256 public nextBondId = 1;

    struct Bond {
        address owner;
        uint256 musdPrincipal;
        uint256 startTime;
        uint256 endTime;
        uint256 claimedBMUSD;
        BondStatus status;
    }

    mapping(uint256 => Bond) public bonds;

    event BondCreated(uint256 indexed bondId, address indexed bonder, uint256 musdAmount, uint256 timestamp);
    event BondCreatedFromTrove(
        uint256 indexed bondId,
        address indexed bonder,
        uint256 btcCollateral,
        uint256 musdAmount,
        bool recoveryMode
    );
    event ChickenedIn(
        uint256 indexed bondId,
        address indexed bonder,
        uint256 musdPrincipal,
        uint256 mintedBMUSD,
        uint256 reserveAdded,
        uint256 permanentAdded,
        uint256 feeMUSD
    );
    event ChickenedOut(uint256 indexed bondId, address indexed bonder, uint256 musdReturned);
    event BMUSDRedeemed(address indexed redeemer, uint256 bMusdBurned, uint256 musdReturned, uint256 btcGainReturned);
    event YieldHarvestedToReserve(uint256 smusdYieldHarvested);

    error BondTooSmall();
    error NotBondOwner();
    error BondNotActive();
    error ZeroAmount();
    error InsufficientICRForMode(uint256 actualICR, uint256 requiredICR, bool recoveryMode);
    error BelowMinNetDebt(uint256 requested, uint256 minRequired);
    error ExceedsMaxBorrowingCapacity(uint256 totalDebt, uint256 maxCapacity);
    error Unauthorized();

    constructor(
        address _musd,
        address _smusd,
        address _stabilityPool,
        address _borrowerOperations,
        address _troveManager,
        address _priceFeed,
        address _feeTreasury,
        uint256 _alphaSeconds
    ) {
        require(_musd != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_stabilityPool != address(0), "Zero address");
        require(_borrowerOperations != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        musd = IMUSD(_musd);
        smusd = IMUSDSavingsRate(_smusd);
        stabilityPool = IStabilityPool(_stabilityPool);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        troveManager = ITroveManager(_troveManager);
        priceFeed = IPriceFeed(_priceFeed);
        feeTreasury = _feeTreasury;
        owner = msg.sender;
        accrualParameterAlpha = _alphaSeconds == 0 ? 15 days : _alphaSeconds;

        bMusd = new bMUSDToken(address(this));
        bondNft = new BondNFT(address(this));
    }

    /// @notice Updates the protocol fee treasury address (governance only).
    function setFeeTreasury(address _feeTreasury) external {
        if (msg.sender != owner) revert Unauthorized();
        require(_feeTreasury != address(0), "Zero address");
        feeTreasury = _feeTreasury;
    }

    /// @notice Creates a principal-protected MUSD Chicken Bond and deploys Pending MUSD into sMUSD.
    function createBond(uint256 musdAmount) external returns (uint256 bondId) {
        if (musdAmount == 0) revert ZeroAmount();
        if (musdAmount < MIN_BOND_AMOUNT) revert BondTooSmall();
        bondId = _recordBondState(msg.sender, musdAmount);
        emit BondCreated(bondId, msg.sender, musdAmount, block.timestamp);
        require(musd.transferFrom(msg.sender, address(this), musdAmount), "ERC20 call failed");
        _deployBondPrincipal(msg.sender, bondId, musdAmount);
    }

    /// @notice 1-tx Zap: Opens or adjusts the contract's proxy Trove on BorrowerOperations, enforces
    ///         Recovery Mode (TCR < 150%) and live minNetDebt/MCR/CCR checks, and bonds the minted MUSD.
    function createBondFromTrove(
        uint256,
        uint256 musdAmount,
        address upperHint,
        address lowerHint
    ) external payable returns (uint256 bondId) {
        if (musdAmount == 0) revert ZeroAmount();
        if (musdAmount < MIN_BOND_AMOUNT) revert BondTooSmall();

        // 1. Read live BTC price & check Recovery Mode (TCR < 150%)
        uint256 btcPrice = priceFeed.fetchPrice();
        bool isRecovery = troveManager.checkRecoveryMode(btcPrice);
        uint256 requiredICR = isRecovery ? troveManager.CCR() : troveManager.MCR();
        uint256 liveMinNetDebt = borrowerOperations.minNetDebt();

        // 2. Query existing Trove coll/debt without double-counting pendingInterest
        //    CRITICAL: `principal` ALREADY includes `pendingPrincipal` and `interest` ALREADY includes `pendingInterest`.
        (
            uint256 existingColl,
            uint256 existingPrincipal,
            uint256 existingInterest,
            uint256 pendingColl,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        ) = troveManager.getEntireDebtAndColl(address(this));
        pendingColl;
        pendingPrincipal;
        pendingInterest;
        uint256 existingDebt = existingPrincipal + existingInterest;

        uint256 borrowingRate = borrowerOperations.borrowingRate();
        uint256 upfrontFee = (musdAmount * borrowingRate) / 1e18;

        if (existingDebt == 0) {
            if (musdAmount < liveMinNetDebt) revert BelowMinNetDebt(musdAmount, liveMinNetDebt);
            uint256 gasComp = borrowerOperations.MUSD_GAS_COMPENSATION();
            uint256 newTotalDebt = musdAmount + upfrontFee + gasComp;
            uint256 projectedICR = (msg.value * btcPrice) / newTotalDebt;
            if (projectedICR < requiredICR) {
                revert InsufficientICRForMode(projectedICR, requiredICR, isRecovery);
            }
            bondId = _recordBondState(msg.sender, musdAmount);
            // forge-lint: disable-next-line(reentrancy-events)
            emit BondCreatedFromTrove(bondId, msg.sender, msg.value, musdAmount, isRecovery);
            borrowerOperations.openTrove{value: msg.value}(musdAmount, upperHint, lowerHint);
        } else {
            uint256 newTotalDebt = existingDebt + musdAmount + upfrontFee;
            uint256 newTotalColl = existingColl + msg.value;
            uint256 projectedICR = (newTotalColl * btcPrice) / newTotalDebt;
            if (projectedICR < requiredICR) {
                revert InsufficientICRForMode(projectedICR, requiredICR, isRecovery);
            }
            uint256 maxCap = borrowerOperations.maxBorrowingCapacity(address(this));
            if (maxCap > 0 && newTotalDebt > maxCap) {
                revert ExceedsMaxBorrowingCapacity(newTotalDebt, maxCap);
            }
            bondId = _recordBondState(msg.sender, musdAmount);
            // forge-lint: disable-next-line(reentrancy-events)
            emit BondCreatedFromTrove(bondId, msg.sender, msg.value, musdAmount, isRecovery);
            borrowerOperations.adjustTrove{value: msg.value}(
                0,
                musdAmount,
                true,
                upperHint,
                lowerHint
            );
        }

        _deployBondPrincipal(msg.sender, bondId, musdAmount);
    }

    function _recordBondState(address bonder, uint256 musdAmount) internal returns (uint256 bondId) {
        bondId = nextBondId++;
        bonds[bondId] = Bond({
            owner: bonder,
            musdPrincipal: musdAmount,
            startTime: block.timestamp,
            endTime: 0,
            claimedBMUSD: 0,
            status: BondStatus.ActiveEgg
        });

        pendingBucketMUSD += musdAmount;
    }

    function _deployBondPrincipal(address bonder, uint256 bondId, uint256 musdAmount) internal {
        // Deploy Pending MUSD into Mezo sMUSD (MUSDSavingsRate)
        require(musd.approve(address(smusd), musdAmount), "ERC20 call failed");
        smusd.deposit(musdAmount);

        bondNft.mint(bonder, bondId);
    }

    /// @notice Cancels an active bond and returns 100% of original MUSD principal to the NFT owner.
    ///         Any yield accrued in sMUSD during the bonding period stays in the Reserve Bucket!
    function chickenOut(uint256 bondId) external {
        Bond storage b = bonds[bondId];
        if (b.status != BondStatus.ActiveEgg) revert BondNotActive();
        address nftOwner = bondNft.ownerOf(bondId);
        if (msg.sender != nftOwner) revert NotBondOwner();

        uint256 claimable = smusd.claimableYield(address(this));
        uint256 principal = b.musdPrincipal;
        b.status = BondStatus.ChickenedOut;
        b.endTime = block.timestamp;
        b.owner = nftOwner;

        pendingBucketMUSD -= principal;
        if (claimable > 0) {
            reserveBucketMUSD += claimable;
            emit YieldHarvestedToReserve(claimable);
        }

        emit ChickenedOut(bondId, nftOwner, principal);

        // Harvest any pending sMUSD yield into the Reserve Bucket before withdrawing principal
        if (claimable > 0) {
            _claimAndDepositSMUSDYield();
        }

        smusd.withdraw(principal);
        require(musd.transfer(nftOwner, principal), "ERC20 call failed");
    }

    /// @notice Converts an active bond into yield-amplified bMUSD along the hyperbolic accrual curve.
    function chickenIn(uint256 bondId) external returns (uint256 mintedBMUSD) {
        Bond storage b = bonds[bondId];
        if (b.status != BondStatus.ActiveEgg) revert BondNotActive();
        address nftOwner = bondNft.ownerOf(bondId);
        if (msg.sender != nftOwner) revert NotBondOwner();

        mintedBMUSD = calcAccruedBMUSD(bondId);
        if (mintedBMUSD == 0) revert ZeroAmount();

        uint256 principal = b.musdPrincipal;
        uint256 backingPrice = getBMUSDBackingPrice();
        uint256 claimable = smusd.claimableYield(address(this));

        // 1% Protocol Fee on Chicken-In principal (explicit revenue model)
        uint256 feeMUSD = (principal * CHICKEN_IN_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netPrincipal = principal - feeMUSD;

        // Split net principal between Reserve Bucket (backing bMUSD) and Permanent Bucket (locked forever)
        uint256 requiredReserve = (mintedBMUSD * backingPrice) / 1e18;

        uint256 reserveAdded;
        uint256 permanentAdded;
        if (requiredReserve >= netPrincipal) {
            reserveAdded = netPrincipal;
            permanentAdded = 0;
        } else {
            uint256 surplus = netPrincipal - requiredReserve;
            permanentAdded = (surplus * PERMANENT_BUCKET_SPLIT_BPS) / BPS_DENOMINATOR;
            reserveAdded = netPrincipal - permanentAdded;
        }

        // Effects before external interactions (CEI)
        b.status = BondStatus.ChickenedIn;
        b.endTime = block.timestamp;
        b.claimedBMUSD = mintedBMUSD;
        b.owner = nftOwner;

        pendingBucketMUSD -= principal;
        reserveBucketMUSD += reserveAdded + claimable;
        permanentBucketMUSD += permanentAdded;

        if (claimable > 0) {
            emit YieldHarvestedToReserve(claimable);
        }
        emit ChickenedIn(bondId, nftOwner, principal, mintedBMUSD, reserveAdded, permanentAdded, feeMUSD);

        // Harvest any accrued sMUSD yield into the Reserve Bucket first
        if (claimable > 0) {
            _claimAndDepositSMUSDYield();
        }

        if (feeMUSD > 0) {
            smusd.withdraw(feeMUSD);
            require(musd.transfer(feeTreasury, feeMUSD), "ERC20 call failed");
        }

        // Route Permanent Bucket slice into StabilityPool for dual yield + peg defense
        if (permanentAdded > 0) {
            smusd.withdraw(permanentAdded);
            require(musd.approve(address(stabilityPool), permanentAdded), "ERC20 call failed");
            stabilityPool.provideToSP(permanentAdded);
        }

        bMusd.mint(nftOwner, mintedBMUSD);
    }

    /// @notice Redeems bMUSD for its pro-rata share of the Reserve Bucket MUSD + StabilityPool BTC gains.
    function redeemBMUSD(uint256 bMusdAmount) external returns (uint256 musdOut, uint256 btcGainOut) {
        if (bMusdAmount == 0) revert ZeroAmount();
        uint256 supply = bMusd.totalSupply();
        if (supply == 0) revert ZeroAmount();

        uint256 claimable = smusd.claimableYield(address(this));
        uint256 updatedReserve = reserveBucketMUSD + claimable;
        musdOut = (bMusdAmount * updatedReserve) / supply;
        reserveBucketMUSD = updatedReserve - musdOut;

        uint256 pendingBtcGain = stabilityPool.getDepositorCollateralGain(address(this));
        uint256 totalBtcAvailable = address(this).balance + pendingBtcGain;
        if (totalBtcAvailable > 0) {
            btcGainOut = (totalBtcAvailable * bMusdAmount) / supply;
        }

        if (claimable > 0) {
            emit YieldHarvestedToReserve(claimable);
        }
        emit BMUSDRedeemed(msg.sender, bMusdAmount, musdOut, btcGainOut);

        if (claimable > 0) {
            _claimAndDepositSMUSDYield();
        }

        bMusd.burn(msg.sender, bMusdAmount);

        smusd.withdraw(musdOut);
        require(musd.transfer(msg.sender, musdOut), "ERC20 call failed");

        if (pendingBtcGain > 0) {
            stabilityPool.withdrawFromSP(0);
        }
        if (btcGainOut > 0) {
            (bool ok, ) = msg.sender.call{value: btcGainOut}("");
            require(ok, "BTC transfer failed");
        }
    }

    /// @notice Harvests pending sMUSD yield from all buckets and compounds it into the Reserve Bucket.
    function harvestYield() external returns (uint256 harvested) {
        uint256 claimable = smusd.claimableYield(address(this));
        if (claimable > 0) {
            reserveBucketMUSD += claimable;
            emit YieldHarvestedToReserve(claimable);
            harvested = _claimAndDepositSMUSDYield();
        }
    }

    function _claimAndDepositSMUSDYield() internal returns (uint256 harvested) {
        harvested = smusd.claimYield();
        if (harvested > 0) {
            require(musd.approve(address(smusd), harvested), "ERC20 call failed");
            smusd.deposit(harvested);
        }
    }

    /// @notice Hyperbolic accrual curve: accruedBMUSD = (principal / backingPrice) * dt / (dt + alpha)
    function calcAccruedBMUSD(uint256 bondId) public view override returns (uint256) {
        Bond memory b = bonds[bondId];
        if (b.status != BondStatus.ActiveEgg) return b.claimedBMUSD;
        uint256 dt = block.timestamp - b.startTime;
        if (dt == 0) return 0;

        uint256 backingPrice = getBMUSDBackingPrice();
        uint256 capBMUSD = (b.musdPrincipal * 1e18) / backingPrice;
        return (capBMUSD * dt) / (dt + accrualParameterAlpha);
    }

    /// @notice Returns the MUSD backing per 1e18 bMUSD in the Reserve Bucket (starts at 1.00 MUSD).
    function getBMUSDBackingPrice() public view returns (uint256) {
        uint256 supply = bMusd.totalSupply();
        uint256 pendingYield = smusd.claimableYield(address(this));
        uint256 effectiveReserve = reserveBucketMUSD + pendingYield;
        if (supply == 0 || effectiveReserve == 0) return 1e18;
        return (effectiveReserve * 1e18) / supply;
    }

    /// @notice Alias for getBMUSDBackingPrice() returning the MUSD redemption floor per 1e18 bMUSD.
    function redemptionPrice() external view returns (uint256) {
        return getBMUSDBackingPrice();
    }

    /// @notice Returns the timestamp at which Chickening In becomes break-even assuming a market premium.
    function getBreakEvenTimestamp(uint256 bondId, uint256 marketPriceWad) external view returns (uint256) {
        Bond memory b = bonds[bondId];
        uint256 backingPrice = getBMUSDBackingPrice();
        if (marketPriceWad <= backingPrice) return b.startTime + (accrualParameterAlpha * 10);
        // Break-even when accruedBMUSD * marketPrice >= principal => dt / (dt + alpha) >= backing / market
        uint256 spread = marketPriceWad - backingPrice;
        uint256 dtRequired = (accrualParameterAlpha * backingPrice) / spread;
        return b.startTime + dtRequired;
    }

    function getBondData(uint256 bondId)
        external
        view
        override
        returns (
            address bondOwner,
            uint256 musdPrincipal,
            uint256 startTime,
            uint256 endTime,
            uint256 claimedBMUSD,
            BondStatus status
        )
    {
        Bond memory b = bonds[bondId];
        bondOwner = b.status == BondStatus.ActiveEgg ? bondNft.ownerOf(bondId) : b.owner;
        return (bondOwner, b.musdPrincipal, b.startTime, b.endTime, b.claimedBMUSD, b.status);
    }

    function getSystemBuckets()
        external
        view
        returns (
            uint256 pendingMUSD,
            uint256 reserveMUSD,
            uint256 permanentMUSD,
            uint256 backingPriceWad,
            uint256 totalBMUSDSupply
        )
    {
        return (
            pendingBucketMUSD,
            reserveBucketMUSD + smusd.claimableYield(address(this)),
            permanentBucketMUSD,
            getBMUSDBackingPrice(),
            bMusd.totalSupply()
        );
    }

    receive() external payable {}
}

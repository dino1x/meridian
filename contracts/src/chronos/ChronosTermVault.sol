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
import {ChronosPT, ChronosYT, IChronosVaultCallback} from "./ChronosTokens.sol";

/// @title ChronosTermVault
/// @notice Splits Mezo sMUSD (0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16) into fixed-maturity
///         Principal Tokens (PT-MUSD) and Yield Tokens (YT-MUSD), with a 1-tx BTC Trove-to-Fixed-Term Zap.
contract ChronosTermVault is IChronosVaultCallback {
    struct Series {
        uint256 seriesId;
        uint256 duration;
        uint256 maturity;
        ChronosPT pt;
        ChronosYT yt;
        uint256 totalPrincipalMUSD;
        uint256 accYieldPerYT; // scaled by 1e18
        bool active;
    }

    IMUSD public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    IStabilityPool public immutable stabilityPool;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IPriceFeed public immutable priceFeed;

    address public feeTreasury;
    address public owner;

    /// @notice 5.00% protocol fee on harvested YT yield (500 bps explicit revenue model)
    uint256 public constant PROTOCOL_YIELD_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public nextSeriesId = 1;
    mapping(uint256 => Series) public series;
    mapping(uint256 => mapping(address => uint256)) public userYTRewardDebt;
    mapping(uint256 => mapping(address => uint256)) public userPendingYieldMUSD;

    event SeriesCreated(
        uint256 indexed seriesId,
        uint256 duration,
        uint256 maturity,
        address ptToken,
        address ytToken
    );
    event MintedPTAndYT(uint256 indexed seriesId, address indexed user, uint256 musdAmount);
    event ZappedTroveToFixedTerm(
        uint256 indexed seriesId,
        address indexed user,
        uint256 btcCollateral,
        uint256 musdAmount,
        bool recoveryMode
    );
    event YieldClaimed(uint256 indexed seriesId, address indexed user, uint256 netYieldMUSD, uint256 protocolFee);
    event RedeemedAtMaturity(uint256 indexed seriesId, address indexed user, uint256 ptBurned, uint256 musdOut);

    error SeriesNotActive();
    error SeriesAlreadyMatured();
    error SeriesNotYetMatured(uint256 currentTime, uint256 maturity);
    error ZeroAmount();
    error InsufficientICRForMode(uint256 actualICR, uint256 requiredICR, bool recoveryMode);
    error BelowMinNetDebt(uint256 requested, uint256 minRequired);
    error OnlyYT();

    constructor(
        address _musd,
        address _smusd,
        address _stabilityPool,
        address _borrowerOperations,
        address _troveManager,
        address _priceFeed,
        address _feeTreasury
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

        // Deploy canonical 30D, 90D, and 180D Mezo Sovereign Term Series
        _createSeries("Chronos PT MUSD 30D", "PT-MUSD-30D", "Chronos YT MUSD 30D", "YT-MUSD-30D", 30 days);
        _createSeries("Chronos PT MUSD 90D", "PT-MUSD-90D", "Chronos YT MUSD 90D", "YT-MUSD-90D", 90 days);
        _createSeries("Chronos PT MUSD 180D", "PT-MUSD-180D", "Chronos YT MUSD 180D", "YT-MUSD-180D", 180 days);
    }

    function createSeries(
        string memory ptName,
        string memory ptSymbol,
        string memory ytName,
        string memory ytSymbol,
        uint256 duration
    ) external returns (uint256 seriesId) {
        return _createSeries(ptName, ptSymbol, ytName, ytSymbol, duration);
    }

    function _createSeries(
        string memory ptName,
        string memory ptSymbol,
        string memory ytName,
        string memory ytSymbol,
        uint256 duration
    ) internal returns (uint256 seriesId) {
        seriesId = nextSeriesId++;
        uint256 mat = block.timestamp + duration;
        ChronosPT pt = new ChronosPT(ptName, ptSymbol, address(this), seriesId, mat);
        ChronosYT yt = new ChronosYT(ytName, ytSymbol, address(this), seriesId, mat);

        series[seriesId] = Series({
            seriesId: seriesId,
            duration: duration,
            maturity: mat,
            pt: pt,
            yt: yt,
            totalPrincipalMUSD: 0,
            accYieldPerYT: 0,
            active: true
        });

        // forge-lint: disable-next-line(reentrancy-events)
        emit SeriesCreated(seriesId, duration, mat, address(pt), address(yt));
    }

    /// @notice Deposits MUSD into sMUSD and mints equal Principal Tokens (PT) and Yield Tokens (YT).
    function mintPTAndYT(uint256 seriesId, uint256 musdAmount) external {
        if (musdAmount == 0) revert ZeroAmount();
        _mintPTAndYTFor(seriesId, msg.sender, musdAmount, true);
    }

    /// @notice 1-Click BTC Trove-to-Fixed-Term Zap: opens/adjusts Trove via BorrowerOperations,
    ///         enforces Recovery Mode (TCR < 150%) and live minNetDebt, and mints PT + YT.
    function zapTroveToFixedTerm(
        uint256 seriesId,
        uint256 musdAmount,
        uint256 /*maxFeePercentage*/,
        address upperHint,
        address lowerHint
    ) external payable {
        if (musdAmount == 0) revert ZeroAmount();

        uint256 btcPrice = priceFeed.fetchPrice();
        bool isRecovery = troveManager.checkRecoveryMode(btcPrice);
        uint256 requiredICR = isRecovery ? troveManager.CCR() : troveManager.MCR();
        uint256 liveMinNetDebt = borrowerOperations.minNetDebt();

        // Read existing Trove coll/debt without double-counting pendingInterest
        (
            uint256 existingColl,
            uint256 existingPrincipal,
            uint256 existingInterest,
            uint256 pendingColl,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        ) = troveManager.getEntireDebtAndColl(address(this));
        (pendingColl, pendingPrincipal, pendingInterest);
        uint256 existingDebt = existingPrincipal + existingInterest;
        uint256 fee = (musdAmount * borrowerOperations.borrowingRate()) / 1e18;

        if (existingDebt == 0) {
            if (musdAmount < liveMinNetDebt) revert BelowMinNetDebt(musdAmount, liveMinNetDebt);
            uint256 projectedDebt = musdAmount + fee + 200e18;
            uint256 projectedICR = (msg.value * btcPrice) / projectedDebt;
            if (projectedICR < requiredICR) {
                revert InsufficientICRForMode(projectedICR, requiredICR, isRecovery);
            }
        } else {
            uint256 projectedDebt = existingDebt + musdAmount + fee;
            uint256 projectedColl = existingColl + msg.value;
            uint256 projectedICR = (projectedColl * btcPrice) / projectedDebt;
            if (projectedICR < requiredICR) {
                revert InsufficientICRForMode(projectedICR, requiredICR, isRecovery);
            }
        }

        uint256 claimable = _accrueSeriesYieldState(seriesId);
        Series storage s = series[seriesId];
        if (!s.active) revert SeriesNotActive();
        if (block.timestamp >= s.maturity) revert SeriesAlreadyMatured();

        _settleUserYield(seriesId, msg.sender);
        s.totalPrincipalMUSD += musdAmount;
        uint256 newYtBalance = s.yt.balanceOf(msg.sender) + musdAmount;
        userYTRewardDebt[seriesId][msg.sender] = (newYtBalance * s.accYieldPerYT) / 1e18;

        emit ZappedTroveToFixedTerm(seriesId, msg.sender, msg.value, musdAmount, isRecovery);
        emit MintedPTAndYT(seriesId, msg.sender, musdAmount);

        if (existingDebt == 0) {
            borrowerOperations.openTrove{value: msg.value}(musdAmount, upperHint, lowerHint);
        } else {
            borrowerOperations.adjustTrove{value: msg.value}(
                0,
                musdAmount,
                true,
                upperHint,
                lowerHint
            );
        }

        _executeClaimYield(claimable);
        s.pt.mint(msg.sender, musdAmount);
        s.yt.mint(msg.sender, musdAmount);

        require(musd.approve(address(smusd), musdAmount), "ERC20 call failed");
        smusd.deposit(musdAmount);
    }

    function _mintPTAndYTFor(uint256 seriesId, address recipient, uint256 musdAmount, bool pullFromSender) internal {
        Series storage s = series[seriesId];
        if (!s.active) revert SeriesNotActive();
        if (block.timestamp >= s.maturity) revert SeriesAlreadyMatured();

        uint256 claimable = _accrueSeriesYieldState(seriesId);
        _settleUserYield(seriesId, recipient);

        s.totalPrincipalMUSD += musdAmount;
        uint256 newYtBalance = s.yt.balanceOf(recipient) + musdAmount;
        userYTRewardDebt[seriesId][recipient] = (newYtBalance * s.accYieldPerYT) / 1e18;

        emit MintedPTAndYT(seriesId, recipient, musdAmount);

        _executeClaimYield(claimable);
        if (pullFromSender) {
            require(musd.transferFrom(recipient, address(this), musdAmount), "ERC20 call failed");
        }
        s.pt.mint(recipient, musdAmount);
        s.yt.mint(recipient, musdAmount);

        require(musd.approve(address(smusd), musdAmount), "ERC20 call failed");
        smusd.deposit(musdAmount);
    }

    /// @notice Recombines equal PT + YT before maturity to unlock underlying MUSD early.
    function recombineBeforeMaturity(uint256 seriesId, uint256 amount) public {
        if (amount == 0) revert ZeroAmount();
        Series storage s = series[seriesId];
        uint256 claimable = _accrueSeriesYieldState(seriesId);
        _settleUserYield(seriesId, msg.sender);

        s.totalPrincipalMUSD -= amount;
        uint256 currentYt = s.yt.balanceOf(msg.sender);
        uint256 remainingYt = currentYt >= amount ? currentYt - amount : 0;
        userYTRewardDebt[seriesId][msg.sender] = (remainingYt * s.accYieldPerYT) / 1e18;

        _executeClaimYield(claimable);
        s.pt.burn(msg.sender, amount);
        s.yt.burn(msg.sender, amount);

        smusd.withdraw(amount);
        require(musd.transfer(msg.sender, amount), "ERC20 call failed");
    }

    /// @notice Alias for recombineBeforeMaturity to support both naming conventions.
    function combineAndRedeemEarly(uint256 seriesId, uint256 amount) external {
        recombineBeforeMaturity(seriesId, amount);
    }

    /// @notice Redeems PT 1:1 for MUSD at or after series maturity.
    function redeemAtMaturity(uint256 seriesId, uint256 ptAmount) public {
        if (ptAmount == 0) revert ZeroAmount();
        Series storage s = series[seriesId];
        if (block.timestamp < s.maturity) revert SeriesNotYetMatured(block.timestamp, s.maturity);

        uint256 claimable = _accrueSeriesYieldState(seriesId);

        s.totalPrincipalMUSD -= ptAmount;
        emit RedeemedAtMaturity(seriesId, msg.sender, ptAmount, ptAmount);

        _executeClaimYield(claimable);
        s.pt.burn(msg.sender, ptAmount);

        smusd.withdraw(ptAmount);
        require(musd.transfer(msg.sender, ptAmount), "ERC20 call failed");
    }

    /// @notice Alias for redeemAtMaturity to support both naming conventions.
    function redeemPTAtMaturity(uint256 seriesId, uint256 ptAmount) external {
        redeemAtMaturity(seriesId, ptAmount);
    }

    /// @notice Claims accrued sMUSD yield for YT holders.
    function claimYield(uint256 seriesId) public returns (uint256 netOut) {
        uint256 claimable = _accrueSeriesYieldState(seriesId);
        _settleUserYield(seriesId, msg.sender);

        uint256 gross = userPendingYieldMUSD[seriesId][msg.sender];
        if (gross == 0) {
            _executeClaimYield(claimable);
            return 0;
        }
        userPendingYieldMUSD[seriesId][msg.sender] = 0;

        uint256 fee = (gross * PROTOCOL_YIELD_FEE_BPS) / BPS_DENOMINATOR;
        netOut = gross - fee;

        emit YieldClaimed(seriesId, msg.sender, netOut, fee);

        _executeClaimYield(claimable);
        if (fee > 0) {
            require(musd.transfer(feeTreasury, fee), "ERC20 call failed");
        }
        require(musd.transfer(msg.sender, netOut), "ERC20 call failed");
    }

    /// @notice Alias for claimYield to support both naming conventions.
    function claimYTYield(uint256 seriesId) external returns (uint256 netOut) {
        return claimYield(seriesId);
    }

    function onYTTransfer(uint256 seriesId, address from, address to) external override {
        Series storage s = series[seriesId];
        if (msg.sender != address(s.yt)) revert OnlyYT();
        uint256 claimable = _accrueSeriesYieldState(seriesId);
        if (from != address(0)) _settleUserYield(seriesId, from);
        if (to != address(0)) _settleUserYield(seriesId, to);
        _executeClaimYield(claimable);
    }

    function _executeClaimYield(uint256 claimable) internal {
        if (claimable > 0) {
            uint256 claimed = smusd.claimYield();
            (claimed);
        }
    }

    function _accrueSeriesYieldState(uint256 seriesId) internal returns (uint256 claimable) {
        Series storage s = series[seriesId];
        uint256 ytSupply = s.yt.totalSupply();
        if (ytSupply == 0) return 0;

        claimable = smusd.claimableYield(address(this));
        if (claimable > 0) {
            s.accYieldPerYT += (claimable * 1e18) / ytSupply;
        }
    }

    function _settleUserYield(uint256 seriesId, address user) internal {
        Series storage s = series[seriesId];
        uint256 bal = s.yt.balanceOf(user);
        if (bal > 0) {
            uint256 accumulated = (bal * s.accYieldPerYT) / 1e18;
            uint256 debt = userYTRewardDebt[seriesId][user];
            if (accumulated > debt) {
                userPendingYieldMUSD[seriesId][user] += (accumulated - debt);
            }
        }
        userYTRewardDebt[seriesId][user] = (bal * s.accYieldPerYT) / 1e18;
    }

    receive() external payable {}
}

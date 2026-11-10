// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20,
    IMUSDSavingsRate,
    IBorrowerOperations,
    ITroveManager,
    IPriceFeed
} from "./interfaces/IMezo.sol";

/// @title DrawdownDesk
/// @notice Just-in-Time Corporate BTC Trove Streaming Payroll & Thermal Receipt Terminal on Mezo.
/// @dev Treasuries lock BTC in a Mezo Trove and open per-second MUSD pay slips for contributors.
///      Unlike standard L2 payroll contracts, DrawdownDesk borrows MUSD Just-in-Time via
///      BorrowerOperations.withdrawMUSD ONLY when a contributor claims their pay slip (or falls back
///      to the treasury's sMUSD buffer if Mezo is in Recovery Mode or ICR would breach safety bounds).
contract DrawdownDesk {
    struct PayStream {
        uint256 streamId;
        address employer;
        address recipient;
        uint256 ratePerSecond;
        uint256 startTime;
        uint256 stopTime;
        uint256 totalClaimedMUSD;
        bool autoRouteToSMUSD;
        bool active;
    }

    struct ThermalReceipt {
        uint256 receiptNo;
        uint256 streamId;
        address recipient;
        uint256 grossMUSD;
        uint256 netMUSD;
        bool drawnFromTroveJIT;
        bool routedToSMUSD;
        uint256 timestamp;
    }

    IERC20 public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IPriceFeed public immutable priceFeed;

    address public treasuryAdmin;
    address public feeTreasury;
    bool public troveInitialized;

    /// @notice 0.50% payroll clearing fee on JIT drawdowns (50 bps explicit revenue model)
    uint256 public constant CLEARING_FEE_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Safety buffer above MCR/CCR (15% extra collateral cushion)
    uint256 public constant SAFETY_CUSHION_WAD = 0.15e18;

    uint256 public nextStreamId = 1;
    uint256 public nextReceiptNo = 10_001;

    mapping(uint256 => PayStream) public streams;
    mapping(address => uint256) public recipientSMUSDShares;
    ThermalReceipt[] public receipts;

    event TreasuryTroveOpened(uint256 btcCollateral, uint256 initialSeedMUSD, uint256 parkedInSMUSD);
    event PayStreamCreated(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 ratePerSecond,
        uint256 startTime,
        uint256 stopTime,
        bool autoRouteToSMUSD
    );
    event ThermalReceiptPrinted(
        uint256 indexed receiptNo,
        uint256 indexed streamId,
        address indexed recipient,
        uint256 netMUSD,
        bool drawnFromTroveJIT,
        bool routedToSMUSD
    );

    error OnlyTreasuryAdmin();
    error StreamNotActive();
    error NothingToClaim();
    error InsufficientICRForOpening(uint256 projectedICR, uint256 requiredICR);
    error BelowMinNetDebt(uint256 requested, uint256 minRequired);

    modifier onlyAdmin() {
        if (msg.sender != treasuryAdmin) revert OnlyTreasuryAdmin();
        _;
    }

    constructor(
        address _musd,
        address _smusd,
        address _borrowerOperations,
        address _troveManager,
        address _priceFeed,
        address _feeTreasury
    ) {
        require(_musd != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_borrowerOperations != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        musd = IERC20(_musd);
        smusd = IMUSDSavingsRate(_smusd);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        troveManager = ITroveManager(_troveManager);
        priceFeed = IPriceFeed(_priceFeed);
        treasuryAdmin = msg.sender;
        feeTreasury = _feeTreasury;
    }

    /// @notice Opens the corporate BTC Trove at minimum initial debt (minNetDebt = 1,800 MUSD)
    ///         and parks 100% of the initial seed MUSD inside sMUSD as a Recovery Mode reserve buffer.
    function initializeCorporateTrove(
        uint256 initialSeedMUSD,
        uint256 /*maxFeePercentage*/,
        address upperHint,
        address lowerHint
    ) external payable onlyAdmin {
        uint256 btcPrice = priceFeed.fetchPrice();
        bool isRecovery = troveManager.checkRecoveryMode(btcPrice);
        uint256 requiredICR = (isRecovery ? troveManager.CCR() : troveManager.MCR()) + SAFETY_CUSHION_WAD;
        uint256 minNetDebt = borrowerOperations.minNetDebt();

        if (initialSeedMUSD < minNetDebt) revert BelowMinNetDebt(initialSeedMUSD, minNetDebt);

        uint256 fee = (initialSeedMUSD * borrowerOperations.borrowingRate()) / 1e18;
        uint256 totalDebt = initialSeedMUSD + fee + borrowerOperations.MUSD_GAS_COMPENSATION();
        uint256 projectedICR = (msg.value * btcPrice) / totalDebt;
        if (projectedICR < requiredICR) {
            revert InsufficientICRForOpening(projectedICR, requiredICR);
        }

        troveInitialized = true;

        emit TreasuryTroveOpened(msg.value, initialSeedMUSD, initialSeedMUSD);

        borrowerOperations.openTrove{value: msg.value}(initialSeedMUSD, upperHint, lowerHint);

        require(musd.approve(address(smusd), initialSeedMUSD), "ERC20 call failed");
        smusd.deposit(initialSeedMUSD);
    }

    function createPayStream(
        address recipient,
        uint256 ratePerSecond,
        uint256 durationSeconds,
        bool autoRouteToSMUSD
    ) external onlyAdmin returns (uint256 streamId) {
        require(recipient != address(0), "Zero address");
        streamId = nextStreamId++;
        uint256 start = block.timestamp;
        uint256 stop = start + durationSeconds;

        streams[streamId] = PayStream({
            streamId: streamId,
            employer: msg.sender,
            recipient: recipient,
            ratePerSecond: ratePerSecond,
            startTime: start,
            stopTime: stop,
            totalClaimedMUSD: 0,
            autoRouteToSMUSD: autoRouteToSMUSD,
            active: true
        });

        emit PayStreamCreated(streamId, recipient, ratePerSecond, start, stop, autoRouteToSMUSD);
    }

    function claimablePaySlip(uint256 streamId) public view returns (uint256) {
        PayStream memory s = streams[streamId];
        if (!s.active || block.timestamp <= s.startTime) return 0;
        uint256 effectiveNow = block.timestamp < s.stopTime ? block.timestamp : s.stopTime;
        uint256 totalAccrued = (effectiveNow - s.startTime) * s.ratePerSecond;
        return totalAccrued > s.totalClaimedMUSD ? totalAccrued - s.totalClaimedMUSD : 0;
    }

    /// @notice Prints a Thermal Pay Slip: executes a Just-in-Time BorrowerOperations.withdrawMUSD
    ///         drawdown against the corporate BTC Trove (or draws from the sMUSD reserve buffer if
    ///         Mezo is in Recovery Mode TCR < 150%), and delivers MUSD or sMUSD to the contributor.
    function claimPaySlip(
        uint256 streamId,
        uint256 /*maxFeePercentage*/,
        address upperHint,
        address lowerHint
    ) external returns (uint256 netPayoutMUSD, uint256 receiptNo) {
        PayStream storage s = streams[streamId];
        if (!s.active) revert StreamNotActive();

        uint256 grossClaim = claimablePaySlip(streamId);
        if (grossClaim == 0) revert NothingToClaim();

        uint256 btcPrice = priceFeed.fetchPrice();
        bool isRecovery = troveManager.checkRecoveryMode(btcPrice);
        uint256 minSafeICR = (isRecovery ? troveManager.CCR() : troveManager.MCR()) + SAFETY_CUSHION_WAD;

        (uint256 entireColl, uint256 entireDebt) = _readCorporateTrovePosition();
        uint256 fee = (grossClaim * borrowerOperations.borrowingRate()) / 1e18;
        uint256 projectedICR = entireColl > 0 ? (entireColl * btcPrice) / (entireDebt + grossClaim + fee) : 0;

        bool drawnJIT = !isRecovery && projectedICR >= minSafeICR;
        uint256 clearingFee = (grossClaim * CLEARING_FEE_BPS) / BPS_DENOMINATOR;
        netPayoutMUSD = grossClaim - clearingFee;

        address recipient = s.recipient;
        bool autoRoute = s.autoRouteToSMUSD;

        // Effects: update all contract storage before external token/protocol mutations
        s.totalClaimedMUSD += grossClaim;
        if (autoRoute) {
            recipientSMUSDShares[recipient] += netPayoutMUSD;
        }
        receiptNo = nextReceiptNo++;
        receipts.push(
            ThermalReceipt({
                receiptNo: receiptNo,
                streamId: streamId,
                recipient: recipient,
                grossMUSD: grossClaim,
                netMUSD: netPayoutMUSD,
                drawnFromTroveJIT: drawnJIT,
                routedToSMUSD: autoRoute,
                timestamp: block.timestamp
            })
        );

        emit ThermalReceiptPrinted(receiptNo, streamId, recipient, netPayoutMUSD, drawnJIT, autoRoute);

        // Interactions
        if (drawnJIT) {
            // Normal Mode & healthy ICR: Just-in-Time Trove drawdown via BorrowerOperations!
            borrowerOperations.withdrawMUSD(grossClaim, upperHint, lowerHint);
        } else {
            // Recovery Mode (TCR < 150%) or tight ICR: draw seamlessly from the treasury's sMUSD reserve buffer!
            smusd.withdraw(grossClaim);
        }

        if (clearingFee > 0) {
            require(musd.transfer(feeTreasury, clearingFee), "ERC20 call failed");
        }

        if (autoRoute) {
            require(musd.approve(address(smusd), netPayoutMUSD), "ERC20 call failed");
            smusd.deposit(netPayoutMUSD);
        } else {
            require(musd.transfer(recipient, netPayoutMUSD), "ERC20 call failed");
        }
    }

    function _readCorporateTrovePosition() internal view returns (uint256 entireColl, uint256 entireDebt) {
        (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingCollateralReward,
            uint256 pendingPrincipalDebtReward,
            uint256 pendingInterestDebtReward
        ) = troveManager.getEntireDebtAndColl(address(this));
        (pendingCollateralReward, pendingPrincipalDebtReward, pendingInterestDebtReward);
        return (coll, principal + interest);
    }

    function receiptsLength() external view returns (uint256) {
        return receipts.length;
    }

    receive() external payable {}
}

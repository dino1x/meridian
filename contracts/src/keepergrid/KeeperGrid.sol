// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20,
    IMUSDSavingsRate,
    IBorrowerOperations,
    ITroveManager,
    IHintHelpers,
    ISortedTroves,
    IPriceFeed,
    IBoostVoter
} from "./interfaces/IMezo.sol";

/// @title KeeperGrid
/// @notice Permissionless Bonded Keeper Network for Mezo MUSD with Productive sMUSD Slashing Bonds.
/// @dev Keepers post MUSD bonds (deployed into sMUSD to earn continuous savings yield while idle).
///      Supports 4 on-chain job modules: Batch Liquidations, Hinted Redemptions, Recovery-Mode-aware
///      Trove Top-Ups, and Gauge Epoch Pokes. Includes deterministic slot windows and 10% bond slashing.
contract KeeperGrid {
    enum JobType {
        BATCH_LIQUIDATION,
        HINTED_REDEMPTION,
        TROVE_TOPUP,
        GAUGE_EPOCH_POKE
    }

    struct KeeperNode {
        address operator;
        uint256 bondedMUSD;
        uint256 jobsCompleted;
        uint256 totalTipEarnedMUSD;
        uint256 timesSlashed;
        bool active;
    }

    struct SignalJob {
        uint256 jobId;
        address poster;
        JobType jobType;
        address targetAddress; // borrower or voter contract
        uint256 paramAmount; // n troves, MUSD to redeem/repay, or tokenId
        uint256 triggerICR; // for TROVE_TOPUP
        uint256 tipMUSD;
        address assignedKeeper;
        uint256 slotDeadline;
        bool executed;
        bool cancelled;
    }

    IERC20 public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IHintHelpers public immutable hintHelpers;
    ISortedTroves public immutable sortedTroves;
    IPriceFeed public immutable priceFeed;
    IBoostVoter public immutable boostVoter;

    address public feeTreasury;

    uint256 public constant MIN_KEEPER_BOND = 500e18; // 500 MUSD minimum bond
    uint256 public constant SLOT_WINDOW = 15 minutes;
    /// @notice 10.00% slash on delinquent assigned keeper bond when backup keeper executes
    uint256 public constant SLASH_BPS = 1000;
    /// @notice 5.00% protocol dispatch fee on job tips & slashes (explicit revenue model)
    uint256 public constant PROTOCOL_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address[] public activeKeepers;
    mapping(address => KeeperNode) public keepers;
    uint256 public roundRobinCursor;

    uint256 public nextJobId = 1;
    mapping(uint256 => SignalJob) public jobs;
    mapping(uint256 => uint256) public jobEscrowedRepayMUSD;

    event KeeperBonded(address indexed keeper, uint256 musdAmount, uint256 totalBond);
    event KeeperUnbonded(address indexed keeper, uint256 musdWithdrawn);
    event SignalJobPosted(
        uint256 indexed jobId,
        address indexed poster,
        JobType jobType,
        address assignedKeeper,
        uint256 tipMUSD,
        uint256 slotDeadline
    );
    event SignalJobExecuted(
        uint256 indexed jobId,
        address indexed executor,
        JobType jobType,
        uint256 keeperPayoutMUSD,
        bool slashedAssignedKeeper
    );
    event KeeperSlashed(address indexed delinquentKeeper, address indexed backupKeeper, uint256 slashAmountMUSD);

    error BondBelowMinimum(uint256 provided, uint256 required);
    error NotActiveKeeper();
    error JobNotExecutable();
    error AssignedKeeperWindowStillOpen(address assignedKeeper, uint256 deadline);
    error TroveHealthyAboveThreshold(uint256 currentICR, uint256 thresholdICR);

    constructor(
        address _musd,
        address _smusd,
        address _borrowerOperations,
        address _troveManager,
        address _hintHelpers,
        address _sortedTroves,
        address _priceFeed,
        address _boostVoter,
        address _feeTreasury
    ) {
        require(_musd != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_borrowerOperations != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_hintHelpers != address(0), "Zero address");
        require(_sortedTroves != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_boostVoter != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        musd = IERC20(_musd);
        smusd = IMUSDSavingsRate(_smusd);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        troveManager = ITroveManager(_troveManager);
        hintHelpers = IHintHelpers(_hintHelpers);
        sortedTroves = ISortedTroves(_sortedTroves);
        priceFeed = IPriceFeed(_priceFeed);
        boostVoter = IBoostVoter(_boostVoter);
        feeTreasury = _feeTreasury;
    }

    /// @notice Registers or tops up a keeper node and deploys the MUSD bond into sMUSD.
    function postKeeperBond(uint256 musdAmount) external {
        KeeperNode storage k = keepers[msg.sender];
        if (k.bondedMUSD + musdAmount < MIN_KEEPER_BOND) {
            revert BondBelowMinimum(k.bondedMUSD + musdAmount, MIN_KEEPER_BOND);
        }

        if (!k.active) {
            k.operator = msg.sender;
            k.active = true;
            activeKeepers.push(msg.sender);
        }
        k.bondedMUSD += musdAmount;
        uint256 newTotalBond = k.bondedMUSD;

        emit KeeperBonded(msg.sender, musdAmount, newTotalBond);

        require(musd.transferFrom(msg.sender, address(this), musdAmount), "ERC20 call failed");
        require(musd.approve(address(smusd), musdAmount), "ERC20 call failed");
        smusd.deposit(musdAmount);
    }

    function withdrawKeeperBond(uint256 musdAmount) external {
        KeeperNode storage k = keepers[msg.sender];
        require(k.bondedMUSD >= musdAmount, "Insufficient bond");
        k.bondedMUSD -= musdAmount;
        if (k.bondedMUSD < MIN_KEEPER_BOND) {
            k.active = false;
        }
        emit KeeperUnbonded(msg.sender, musdAmount);
        smusd.withdraw(musdAmount);
        require(musd.transfer(msg.sender, musdAmount), "ERC20 call failed");
    }

    /// @notice Posts an on-chain keeper job with a MUSD tip (and optional repay reserve for TROVE_TOPUP).
    function postSignalJob(
        JobType jobType,
        address targetAddress,
        uint256 paramAmount,
        uint256 triggerICR,
        uint256 tipMUSD
    ) external returns (uint256 jobId) {
        uint256 totalPull = tipMUSD + (jobType == JobType.TROVE_TOPUP || jobType == JobType.HINTED_REDEMPTION ? paramAmount : 0);

        address assigned = activeKeepers.length > 0
            ? activeKeepers[roundRobinCursor++ % activeKeepers.length]
            : address(0);

        jobId = nextJobId++;
        uint256 deadline = block.timestamp + SLOT_WINDOW;
        jobs[jobId] = SignalJob({
            jobId: jobId,
            poster: msg.sender,
            jobType: jobType,
            targetAddress: targetAddress,
            paramAmount: paramAmount,
            triggerICR: triggerICR,
            tipMUSD: tipMUSD,
            assignedKeeper: assigned,
            slotDeadline: deadline,
            executed: false,
            cancelled: false
        });

        if (jobType == JobType.TROVE_TOPUP || jobType == JobType.HINTED_REDEMPTION) {
            jobEscrowedRepayMUSD[jobId] = paramAmount;
        }

        emit SignalJobPosted(jobId, msg.sender, jobType, assigned, tipMUSD, deadline);

        if (totalPull > 0) {
            require(musd.transferFrom(msg.sender, address(this), totalPull), "ERC20 call failed");
            require(musd.approve(address(smusd), totalPull), "ERC20 call failed");
            smusd.deposit(totalPull);
        }
    }

    /// @notice Executes a posted job. During the first SLOT_WINDOW, only the assigned keeper can execute.
    ///         If the assigned keeper misses the deadline, any active backup keeper can execute AND slashes
    ///         10% of the delinquent keeper's sMUSD bond!
    function executeSignalJob(
        uint256 jobId,
        address upperHint,
        address lowerHint
    ) external returns (uint256 keeperPayout) {
        KeeperNode storage execNode = keepers[msg.sender];
        if (!execNode.active) revert NotActiveKeeper();

        SignalJob storage j = jobs[jobId];
        if (j.executed || j.cancelled) revert JobNotExecutable();

        bool slashed = false;
        uint256 slashBonus = 0;

        if (j.assignedKeeper != address(0) && msg.sender != j.assignedKeeper) {
            if (block.timestamp <= j.slotDeadline) {
                revert AssignedKeeperWindowStillOpen(j.assignedKeeper, j.slotDeadline);
            }
            // Assigned keeper missed window -> slash 10% of their bond!
            KeeperNode storage delinquent = keepers[j.assignedKeeper];
            if (delinquent.bondedMUSD > 0) {
                slashBonus = (delinquent.bondedMUSD * SLASH_BPS) / BPS_DENOMINATOR;
                delinquent.bondedMUSD -= slashBonus;
                delinquent.timesSlashed += 1;
                if (delinquent.bondedMUSD < MIN_KEEPER_BOND) {
                    delinquent.active = false;
                }
                slashed = true;
                emit KeeperSlashed(j.assignedKeeper, msg.sender, slashBonus);
            }
        }

        j.executed = true;
        SignalJob memory jobSnapshot = j;

        // Calculate reward and update state before external interactions (CEI)
        uint256 grossReward = jobSnapshot.tipMUSD + slashBonus;
        uint256 protoFee = (grossReward * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        keeperPayout = grossReward - protoFee;

        execNode.jobsCompleted += 1;
        execNode.totalTipEarnedMUSD += keeperPayout;

        emit SignalJobExecuted(jobId, msg.sender, jobSnapshot.jobType, keeperPayout, slashed);

        // Execute the underlying Mezo protocol operation
        _dispatchJobModule(jobSnapshot, upperHint, lowerHint);

        // Pay out tip + slashBonus (minus 5% protocol dispatch fee)
        if (grossReward > 0) {
            smusd.withdraw(grossReward);
            if (protoFee > 0) require(musd.transfer(feeTreasury, protoFee), "ERC20 call failed");
            if (keeperPayout > 0) require(musd.transfer(msg.sender, keeperPayout), "ERC20 call failed");
        }
    }

    function _dispatchJobModule(SignalJob memory j, address upperHint, address lowerHint) internal {
        if (j.jobType == JobType.BATCH_LIQUIDATION) {
            troveManager.liquidateTroves(j.paramAmount);
        } else if (j.jobType == JobType.HINTED_REDEMPTION) {
            uint256 amount = jobEscrowedRepayMUSD[j.jobId];
            jobEscrowedRepayMUSD[j.jobId] = 0;
            smusd.withdraw(amount);
            uint256 price = priceFeed.fetchPrice();
            (address firstHint, uint256 partialNICR, uint256 truncated) = hintHelpers.getRedemptionHints(
                amount,
                price,
                15
            );
            uint256 redeemAmt = truncated > 0 ? truncated : amount;
            (address up, address low) = sortedTroves.findInsertPosition(partialNICR, address(0), address(0));
            uint256 btcBefore = address(this).balance;
            troveManager.redeemCollateral(redeemAmt, firstHint, up, low, partialNICR, 15);
            uint256 btcOut = address(this).balance - btcBefore;
            if (btcOut > 0) {
                (bool ok, ) = j.poster.call{value: btcOut}("");
                require(ok, "BTC send failed");
            }
        } else if (j.jobType == JobType.TROVE_TOPUP) {
            uint256 price = priceFeed.fetchPrice();
            bool isRecovery = troveManager.checkRecoveryMode(price);
            uint256 minSafeICR = isRecovery ? troveManager.CCR() : troveManager.MCR();
            uint256 effectiveTrigger = j.triggerICR > minSafeICR ? j.triggerICR : minSafeICR;

            (uint256 entireColl, uint256 entireDebt) = _readTroveCollAndDebt(j.targetAddress);
            uint256 currentICR = (entireColl * price) / entireDebt;
            if (currentICR > effectiveTrigger) {
                revert TroveHealthyAboveThreshold(currentICR, effectiveTrigger);
            }

            uint256 repayAmt = jobEscrowedRepayMUSD[j.jobId];
            jobEscrowedRepayMUSD[j.jobId] = 0;
            smusd.withdraw(repayAmt);
            borrowerOperations.repayMUSD(repayAmt, upperHint, lowerHint);
        } else {
            boostVoter.poke(j.paramAmount);
        }
    }

    function _readTroveCollAndDebt(address target) internal view returns (uint256 entireColl, uint256 entireDebt) {
        (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingCollateralReward,
            uint256 pendingPrincipalDebtReward,
            uint256 pendingInterestDebtReward
        ) = troveManager.getEntireDebtAndColl(target);
        (pendingCollateralReward, pendingPrincipalDebtReward, pendingInterestDebtReward);
        return (coll, principal + interest);
    }

    function activeKeepersCount() external view returns (uint256) {
        return activeKeepers.length;
    }

    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAutopayFactory,
    IBorrowerOperations,
    ITroveManager,
    IStabilityPool,
    IMUSDSavingsRate,
    IPriceFeed,
    IMUSD
} from "./interfaces/IMezo.sol";

/// @title TroveVault
/// @notice Individual user EIP-1167 minimal proxy vault that owns a self-strengthening,
///         self-repaying Mezo BTC Trove.
/// @dev Routes a configurable slice of borrowed MUSD into sMUSD and StabilityPool, harvests
///      sMUSD yield to auto-repay Trove debt, compounds StabilityPool BTC liquidation gains
///      directly into Trove collateral via withdrawCollateralGainToTrove, and rebalances
///      between lowerBandICR (dynamically raised to CCR=150% in Recovery Mode) and upperBandICR.
contract TroveVault {
    IAutopayFactory public factory;
    address public owner;
    bool public initialized;

    uint256 public reserveBps; // e.g., 3000 = 30% of borrowed MUSD goes to growth reserve
    uint256 public lowerBandICR; // e.g., 1.35e18 (135%), auto-raised to CCR (150%) in Recovery Mode
    uint256 public upperBandICR; // e.g., 2.20e18 (220%)

    uint256 public totalDebtAutoRepaid;
    uint256 public totalBtcGainsCompounded;
    uint256 public growthRingCount;

    /// @notice 1.00% protocol fee + 0.50% keeper tip on harvested yield (explicit revenue model)
    uint256 public constant PROTOCOL_FEE_BPS = 100;
    uint256 public constant KEEPER_TIP_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    event VaultInitialized(address indexed owner, uint256 reserveBps, uint256 lowerBandICR, uint256 upperBandICR);
    event SelfPayingTroveOpened(
        address indexed owner,
        uint256 btcCollateral,
        uint256 spendableMUSD,
        uint256 reserveMUSD,
        bool recoveryMode
    );
    event HarvestedAndStrengthened(
        address indexed keeper,
        uint256 debtRepaidMUSD,
        uint256 btcCollateralAdded,
        uint256 newRingIndex
    );
    event BandRebalanced(
        address indexed keeper,
        bool wasDefensiveDeleverage,
        uint256 musdDelta,
        uint256 resultingICR,
        bool recoveryMode
    );

    error AlreadyInitialized();
    error NotOwner();
    error InvalidBandConfig();
    error InsufficientICRForMode(uint256 actualICR, uint256 requiredICR, bool recoveryMode);
    error BelowMinNetDebt(uint256 requested, uint256 minRequired);
    error NoRebalanceNeeded(uint256 currentICR);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function initialize(
        address _factory,
        address _owner,
        uint256 _reserveBps,
        uint256 _lowerBandICR,
        uint256 _upperBandICR
    ) external {
        require(_factory != address(0), "Zero address");
        require(_owner != address(0), "Zero address");
        if (initialized) revert AlreadyInitialized();
        if (_lowerBandICR >= _upperBandICR || _reserveBps == 0 || _reserveBps > 8000 || _lowerBandICR < 1.1e18) {
            revert InvalidBandConfig();
        }
        initialized = true;
        factory = IAutopayFactory(_factory);
        owner = _owner;
        reserveBps = _reserveBps;
        lowerBandICR = _lowerBandICR;
        upperBandICR = _upperBandICR;
        emit VaultInitialized(_owner, _reserveBps, _lowerBandICR, _upperBandICR);
    }

    /// @notice Opens the user's self-paying BTC Trove on BorrowerOperations, sends spendable MUSD
    ///         to the owner, and seeds the Growth Reserve in sMUSD (50%) and StabilityPool (50%).
    function openSelfPayingTrove(
        uint256 totalMUSD,
        uint256 /*maxFeePercentage*/,
        address upperHint,
        address lowerHint
    ) external payable onlyOwner {
        IBorrowerOperations bo = IBorrowerOperations(factory.borrowerOperations());
        ITroveManager tm = ITroveManager(factory.troveManager());
        IPriceFeed pf = IPriceFeed(factory.priceFeed());
        IMUSD musd = IMUSD(factory.musd());
        IMUSDSavingsRate smusd = IMUSDSavingsRate(factory.smusd());
        IStabilityPool sp = IStabilityPool(factory.stabilityPool());

        uint256 btcPrice = pf.fetchPrice();
        bool isRecovery = tm.checkRecoveryMode(btcPrice);
        uint256 requiredICR = isRecovery ? tm.CCR() : tm.MCR();
        uint256 minNetDebt = bo.minNetDebt();

        if (totalMUSD < minNetDebt) revert BelowMinNetDebt(totalMUSD, minNetDebt);

        uint256 fee = (totalMUSD * bo.borrowingRate()) / 1e18;
        uint256 gasComp = bo.MUSD_GAS_COMPENSATION();
        uint256 totalDebt = totalMUSD + fee + gasComp;
        uint256 projectedICR = (msg.value * btcPrice) / totalDebt;
        if (projectedICR < requiredICR) {
            revert InsufficientICRForMode(projectedICR, requiredICR, isRecovery);
        }

        uint256 reserveMUSD = (totalMUSD * reserveBps) / BPS_DENOMINATOR;
        uint256 spendableMUSD = totalMUSD - reserveMUSD;

        growthRingCount = 1;
        emit SelfPayingTroveOpened(owner, msg.value, spendableMUSD, reserveMUSD, isRecovery);

        bo.openTrove{value: msg.value}(totalMUSD, upperHint, lowerHint);

        if (spendableMUSD > 0) {
            require(musd.transfer(owner, spendableMUSD), "ERC20 call failed");
        }

        if (reserveMUSD > 0) {
            uint256 toSMUSD = reserveMUSD / 2;
            uint256 toSP = reserveMUSD - toSMUSD;
            if (toSMUSD > 0) {
                require(musd.approve(address(smusd), toSMUSD), "ERC20 call failed");
                smusd.deposit(toSMUSD);
            }
            if (toSP > 0) {
                require(musd.approve(address(sp), toSP), "ERC20 call failed");
                sp.provideToSP(toSP);
            }
        }
    }

    /// @notice Permissionless keeper call: harvests sMUSD yield to auto-repay Trove debt and
    ///         compounds StabilityPool BTC liquidation gains directly into Trove collateral.
    function harvestAndStrengthen(
        address upperHint,
        address lowerHint
    ) external returns (uint256 netDebtRepaid, uint256 btcGainCompounded) {
        IBorrowerOperations bo = IBorrowerOperations(factory.borrowerOperations());
        ITroveManager tm = ITroveManager(factory.troveManager());
        IStabilityPool sp = IStabilityPool(factory.stabilityPool());
        IMUSDSavingsRate smusd = IMUSDSavingsRate(factory.smusd());
        IMUSD musd = IMUSD(factory.musd());

        uint256 claimable = smusd.claimableYield(address(this));
        uint256 protoFee = 0;
        uint256 keeperTip = 0;
        uint256 netYield = 0;
        bool canRepayDebt = false;

        if (claimable > 0) {
            protoFee = (claimable * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
            keeperTip = (claimable * KEEPER_TIP_BPS) / BPS_DENOMINATOR;
            netYield = claimable - protoFee - keeperTip;

            // Ensure remaining net debt stays >= minNetDebt (never double-counting pendingInterest!)
            (
                uint256 currentColl,
                uint256 principal,
                uint256 interest,
                uint256 pendingColl,
                uint256 pendingPrincipal,
                uint256 pendingInterest
            ) = tm.getEntireDebtAndColl(address(this));
            (currentColl, pendingColl, pendingPrincipal, pendingInterest);
            uint256 entireDebt = principal + interest;
            uint256 minFloor = bo.minNetDebt() + bo.MUSD_GAS_COMPENSATION();

            canRepayDebt = entireDebt > minFloor + netYield;
            if (canRepayDebt) {
                netDebtRepaid = netYield;
                totalDebtAutoRepaid += netDebtRepaid;
            }
        }

        btcGainCompounded = sp.getDepositorCollateralGain(address(this));
        if (btcGainCompounded > 0) {
            totalBtcGainsCompounded += btcGainCompounded;
        }

        if (netDebtRepaid > 0 || btcGainCompounded > 0) {
            growthRingCount += 1;
        }

        emit HarvestedAndStrengthened(msg.sender, netDebtRepaid, btcGainCompounded, growthRingCount);

        if (claimable > 0) {
            uint256 harvested = smusd.claimYield();
            if (harvested > 0) {
                if (protoFee > 0) {
                    require(musd.transfer(factory.protocolTreasury(), protoFee), "ERC20 call failed");
                }
                if (keeperTip > 0) {
                    require(musd.transfer(msg.sender, keeperTip), "ERC20 call failed");
                }
                if (canRepayDebt) {
                    bo.repayMUSD(netDebtRepaid, upperHint, lowerHint);
                } else {
                    require(musd.approve(address(smusd), netYield), "ERC20 call failed");
                    smusd.deposit(netYield);
                }
            }
        }

        if (btcGainCompounded > 0) {
            sp.withdrawCollateralGainToTrove(upperHint, lowerHint);
        }
    }

    /// @notice Permissionless band rebalancer:
    ///         - If ICR < effectiveLowerBand (raised to CCR=150% in Recovery Mode), pulls MUSD from
    ///           sMUSD/StabilityPool reserve and repays Trove debt.
    ///         - If ICR > upperBandICR and NOT in Recovery Mode, skims excess MUSD capacity to sMUSD.
    function rebalanceBand(
        uint256 /*maxFeePercentage*/,
        address upperHint,
        address lowerHint
    ) external returns (bool wasDefensive, uint256 musdDelta) {
        IBorrowerOperations bo = IBorrowerOperations(factory.borrowerOperations());
        ITroveManager tm = ITroveManager(factory.troveManager());
        IMUSDSavingsRate smusd = IMUSDSavingsRate(factory.smusd());
        IStabilityPool sp = IStabilityPool(factory.stabilityPool());
        IPriceFeed pf = IPriceFeed(factory.priceFeed());
        IMUSD musd = IMUSD(factory.musd());

        uint256 btcPrice = pf.fetchPrice();
        bool isRecovery = tm.checkRecoveryMode(btcPrice);
        uint256 protocolMinICR = isRecovery ? tm.CCR() : tm.MCR();
        uint256 effectiveLower = lowerBandICR > protocolMinICR ? lowerBandICR : protocolMinICR;

        // Read coll/debt without double-counting pendingInterest
        (
            uint256 entireColl,
            uint256 principal,
            uint256 interest,
            uint256 pendingColl,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        ) = tm.getEntireDebtAndColl(address(this));
        (pendingColl, pendingPrincipal, pendingInterest);
        uint256 entireDebt = principal + interest;
        uint256 currentICR = (entireColl * btcPrice) / entireDebt;

        uint256 fromSMUSD = 0;
        uint256 fromSP = 0;
        uint256 projectedAfterDebt = entireDebt;

        if (currentICR < effectiveLower) {
            wasDefensive = true;
            uint256 targetDebt = (entireColl * btcPrice) / effectiveLower;
            uint256 neededRepay = entireDebt > targetDebt ? entireDebt - targetDebt : 0;

            uint256 smusdBal = smusd.balanceOf(address(this));
            fromSMUSD = neededRepay <= smusdBal ? neededRepay : smusdBal;
            uint256 rem = neededRepay - fromSMUSD;
            uint256 spBal = sp.getCompoundedMUSDDeposit(address(this));
            fromSP = rem <= spBal ? rem : spBal;

            musdDelta = fromSMUSD + fromSP;
            growthRingCount += 1;
            if (musdDelta > 0) {
                totalDebtAutoRepaid += musdDelta;
                projectedAfterDebt = entireDebt - musdDelta;
            }
        } else if (currentICR > upperBandICR && !isRecovery) {
            wasDefensive = false;
            uint256 targetDebt = (entireColl * btcPrice) / upperBandICR;
            growthRingCount += 1;
            if (targetDebt > entireDebt) {
                musdDelta = targetDebt - entireDebt;
                projectedAfterDebt = entireDebt + musdDelta;
            }
        } else {
            revert NoRebalanceNeeded(currentICR);
        }

        uint256 projectedAfterICR = (entireColl * btcPrice) / projectedAfterDebt;
        emit BandRebalanced(msg.sender, wasDefensive, musdDelta, projectedAfterICR, isRecovery);

        if (wasDefensive) {
            if (fromSMUSD > 0) {
                smusd.withdraw(fromSMUSD);
            }
            if (fromSP > 0) {
                sp.withdrawFromSP(fromSP);
            }
            if (musdDelta > 0) {
                bo.repayMUSD(musdDelta, upperHint, lowerHint);
            }
        } else if (musdDelta > 0) {
            bo.withdrawMUSD(musdDelta, upperHint, lowerHint);
            require(musd.approve(address(smusd), musdDelta), "ERC20 call failed");
            smusd.deposit(musdDelta);
        }
    }

    receive() external payable {}
}

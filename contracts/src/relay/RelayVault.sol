// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20,
    IVotingEscrow,
    IVoter,
    IBoostVoter,
    IBribe,
    ITigrisRouter,
    IMUSDSavingsRate,
    IStabilityPool,
    IBorrowerOperations,
    ITroveManager,
    IPriceFeed
} from "./interfaces/IMezoVe.sol";

/// @title RelayVault
/// @notice Non-custodial automated epoch voter, bribe harvester & MUSD compounder for Mezo veBTC & veMEZO.
/// @dev Users NEVER transfer their veBTC or veMEZO NFT. They retain custody in their wallet and approve
///      RelayVault via `ve.approve(address(relayVault), tokenId)` or `setApprovalForAll`.
///      Includes a strict token whitelist on bribe swaps, so arbitrary reward tokens never reach the router
///      and Recovery-Mode-aware BorrowerOperations Trove debt auto-repayment.
contract RelayVault {
    enum EscrowKind {
        VeBTC,
        VeMEZO
    }

    enum YieldRoute {
        COMPOUND_SMUSD,
        PROVIDE_STABILITY_POOL,
        REPAY_TROVE_DEBT
    }

    struct FlightPlan {
        address owner;
        EscrowKind kind;
        uint256 tokenId;
        YieldRoute route;
        bool autoExtendLock;
        bool active;
        uint256 totalMUSDCompounded;
        uint256 lastExecutedEpoch;
    }

    IVotingEscrow public immutable veBTC;
    IVotingEscrow public immutable veMEZO;
    IVoter public immutable poolsVoter;
    IBoostVoter public immutable boostVoter;
    ITigrisRouter public immutable tigrisRouter;
    IERC20 public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    IStabilityPool public immutable stabilityPool;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IPriceFeed public immutable priceFeed;

    address public immutable governor;
    address public feeTreasury;

    /// @notice Protocol performance fee on harvested bribes (200 bps = 2.00% explicit revenue model)
    uint256 public constant PROTOCOL_FEE_BPS = 200;
    /// @notice Permissionless keeper execution bounty (50 bps = 0.50%)
    uint256 public constant KEEPER_BOUNTY_BPS = 50;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;

    uint256 public nextPlanId = 1;
    mapping(uint256 => FlightPlan) public flightPlans;
    mapping(address => mapping(uint256 => uint256)) public tokenToPlanId;
    mapping(address => bool) public whitelistedRewardTokens;
    mapping(address => uint256) public userSMUSDBalance;
    mapping(address => uint256) public userSPDepositedMUSD;

    event FlightPlanRegistered(
        uint256 indexed planId,
        address indexed owner,
        EscrowKind kind,
        uint256 tokenId,
        YieldRoute route,
        bool autoExtendLock
    );
    event FlightPlanUpdated(uint256 indexed planId, YieldRoute route, bool autoExtendLock, bool active);
    event EpochRelayExecuted(
        uint256 indexed planId,
        address indexed owner,
        address indexed keeper,
        uint256 musdHarvested,
        uint256 netRoutedMUSD,
        YieldRoute route
    );
    event RewardTokenWhitelisted(address indexed token, bool status);
    event SMUSDWithdrawn(address indexed user, uint256 amount);
    event TreasuryUpdated(address indexed newTreasury);

    error NotNFTOwner();
    error OperatorNotApprovedOnVE();
    error NotNFTApprovedOrOwner();
    error InvalidWeightSum();
    error InvalidFlightPlan();
    error TokenNotWhitelisted(address token);
    error NotGovernor();
    error RecoveryModeRepayRestricted();
    error WouldBreachMinNetDebt(uint256 remainingDebt, uint256 minNetDebt);

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotGovernor();
        _;
    }

    constructor(
        address _veBTC,
        address _veMEZO,
        address _poolsVoter,
        address _boostVoter,
        address _tigrisRouter,
        address _musd,
        address _smusd,
        address _stabilityPool,
        address _borrowerOperations,
        address _troveManager,
        address _priceFeed,
        address _feeTreasury
    ) {
        require(_veBTC != address(0), "Zero address");
        require(_veMEZO != address(0), "Zero address");
        require(_poolsVoter != address(0), "Zero address");
        require(_boostVoter != address(0), "Zero address");
        require(_tigrisRouter != address(0), "Zero address");
        require(_musd != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_stabilityPool != address(0), "Zero address");
        require(_borrowerOperations != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        veBTC = IVotingEscrow(_veBTC);
        veMEZO = IVotingEscrow(_veMEZO);
        poolsVoter = IVoter(_poolsVoter);
        boostVoter = IBoostVoter(_boostVoter);
        tigrisRouter = ITigrisRouter(_tigrisRouter);
        musd = IERC20(_musd);
        smusd = IMUSDSavingsRate(_smusd);
        stabilityPool = IStabilityPool(_stabilityPool);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        troveManager = ITroveManager(_troveManager);
        priceFeed = IPriceFeed(_priceFeed);
        governor = msg.sender;
        feeTreasury = _feeTreasury;

        whitelistedRewardTokens[_musd] = true;
    }

    function setTreasury(address _feeTreasury) external onlyGovernor {
        require(_feeTreasury != address(0), "Zero address");
        feeTreasury = _feeTreasury;
        emit TreasuryUpdated(_feeTreasury);
    }

    function setWhitelistedRewardToken(address token, bool allowed) external onlyGovernor {
        require(token != address(0), "Zero address");
        whitelistedRewardTokens[token] = allowed;
        emit RewardTokenWhitelisted(token, allowed);
    }

    /// @notice Non-custodial registration: user keeps NFT in wallet and approves RelayVault on veBTC/veMEZO.
    function registerFlightPlan(
        EscrowKind kind,
        uint256 tokenId,
        YieldRoute route,
        bool autoExtendLock
    ) external returns (uint256 planId) {
        IVotingEscrow ve = kind == EscrowKind.VeBTC ? veBTC : veMEZO;
        if (ve.ownerOf(tokenId) != msg.sender || !ve.isApprovedOrOwner(address(this), tokenId)) {
            revert NotNFTApprovedOrOwner();
        }

        planId = tokenToPlanId[address(ve)][tokenId];
        if (planId == 0) {
            planId = nextPlanId++;
            tokenToPlanId[address(ve)][tokenId] = planId;
        }

        flightPlans[planId] = FlightPlan({
            owner: msg.sender,
            kind: kind,
            tokenId: tokenId,
            route: route,
            autoExtendLock: autoExtendLock,
            active: true,
            totalMUSDCompounded: flightPlans[planId].totalMUSDCompounded,
            lastExecutedEpoch: flightPlans[planId].lastExecutedEpoch
        });

        emit FlightPlanRegistered(planId, msg.sender, kind, tokenId, route, autoExtendLock);
    }

    function updateFlightPlan(uint256 planId, YieldRoute route, bool autoExtendLock, bool active) external {
        FlightPlan storage fp = flightPlans[planId];
        if (fp.owner != msg.sender) revert NotNFTOwner();
        fp.route = route;
        fp.autoExtendLock = autoExtendLock;
        fp.active = active;
        emit FlightPlanUpdated(planId, route, autoExtendLock, active);
    }

    /// @notice Permissionless keeper entrypoint: casts optimal votes on Voter / BoostVoter, claims bribes,
    ///         converts whitelisted reward tokens to MUSD, and routes net MUSD to sMUSD, StabilityPool, or Trove repayment.
    function executeEpochRelay(
        uint256 planId,
        address[] calldata targetPoolsOrGauges,
        uint256[] calldata weights,
        address[] calldata bribeContracts,
        address[][] calldata bribeTokens
    ) external returns (uint256 netRoutedMUSD) {
        FlightPlan storage fp = flightPlans[planId];
        if (!fp.active) revert InvalidFlightPlan();

        IVotingEscrow ve = fp.kind == EscrowKind.VeBTC ? veBTC : veMEZO;
        address currentOwner = ve.ownerOf(fp.tokenId);
        fp.owner = currentOwner;
        if (!ve.isApprovedOrOwner(address(this), fp.tokenId)) revert NotNFTApprovedOrOwner();

        if (targetPoolsOrGauges.length != weights.length) revert InvalidWeightSum();
        if (targetPoolsOrGauges.length > 0) {
            uint256 weightSum = 0;
            for (uint256 i = 0; i < weights.length; i++) {
                weightSum += weights[i];
            }
            if (weightSum != BPS_DENOMINATOR) revert InvalidWeightSum();
        }

        // 1. Optional lock extension to preserve maximum voting power
        if (fp.autoExtendLock) {
            try ve.increaseUnlockTime(fp.tokenId, MAX_LOCK_DURATION) {} catch {}
        }

        // 2. Cast non-custodial votes & claim bribes on Voter (veBTC) or BoostVoter (veMEZO)
        uint256 musdBefore = musd.balanceOf(address(this));

        if (fp.kind == EscrowKind.VeBTC) {
            if (targetPoolsOrGauges.length > 0) {
                poolsVoter.vote(fp.tokenId, targetPoolsOrGauges, weights);
            }
            if (bribeContracts.length > 0) {
                poolsVoter.claimBribes(bribeContracts, bribeTokens, fp.tokenId);
            }
        } else {
            if (targetPoolsOrGauges.length > 0) {
                boostVoter.vote(fp.tokenId, targetPoolsOrGauges, weights);
            }
            if (bribeContracts.length > 0) {
                boostVoter.claimBribes(bribeContracts, bribeTokens, fp.tokenId);
            }
        }

        // 3. Swap any non-MUSD whitelisted reward tokens received into MUSD via TigrisRouter
        for (uint256 i = 0; i < bribeTokens.length; i++) {
            for (uint256 j = 0; j < bribeTokens[i].length; j++) {
                address tok = bribeTokens[i][j];
                if (!whitelistedRewardTokens[tok]) revert TokenNotWhitelisted(tok);
                if (tok != address(musd)) {
                    uint256 bal = IERC20(tok).balanceOf(address(this));
                    if (bal > 0) {
                        require(IERC20(tok).approve(address(tigrisRouter), bal), "ERC20 call failed");
                        ITigrisRouter.Route[] memory routes = new ITigrisRouter.Route[](1);
                        routes[0] = ITigrisRouter.Route({
                            from: tok,
                            to: address(musd),
                            stable: false,
                            factory: tigrisRouter.defaultFactory()
                        });
                        uint256[] memory amounts =
                            tigrisRouter.swapExactTokensForTokens(bal, 0, routes, address(this), block.timestamp);
                        amounts;
                    }
                }
            }
        }

        uint256 musdHarvested = musd.balanceOf(address(this)) - musdBefore;
        if (musdHarvested == 0) {
            fp.lastExecutedEpoch = block.timestamp;
            return 0;
        }

        // 4. Deduct 2% protocol fee + 0.5% keeper bounty
        uint256 protocolFee = (musdHarvested * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 keeperBounty = (musdHarvested * KEEPER_BOUNTY_BPS) / BPS_DENOMINATOR;
        netRoutedMUSD = musdHarvested - protocolFee - keeperBounty;

        // Effects before trailing interactions (CEI)
        YieldRoute selectedRoute = fp.route;
        fp.totalMUSDCompounded += netRoutedMUSD;
        fp.lastExecutedEpoch = block.timestamp;

        // forge-lint: disable-next-line(reentrancy-events)
        emit EpochRelayExecuted(planId, currentOwner, msg.sender, musdHarvested, netRoutedMUSD, selectedRoute);

        if (protocolFee > 0) {
            require(musd.transfer(feeTreasury, protocolFee), "ERC20 call failed");
        }
        if (keeperBounty > 0) {
            require(musd.transfer(msg.sender, keeperBounty), "ERC20 call failed");
        }

        // 5. Execute User's YieldRoute
        _routeNetMUSD(currentOwner, netRoutedMUSD, selectedRoute);
    }

    function _routeNetMUSD(address user, uint256 amount, YieldRoute route) internal {
        if (route == YieldRoute.COMPOUND_SMUSD) {
            userSMUSDBalance[user] += amount;
            require(musd.approve(address(smusd), amount), "ERC20 call failed");
            uint256 shares = smusd.deposit(amount);
            shares;
        } else if (route == YieldRoute.PROVIDE_STABILITY_POOL) {
            userSPDepositedMUSD[user] += amount;
            require(musd.approve(address(stabilityPool), amount), "ERC20 call failed");
            stabilityPool.provideToSP(amount);
        } else {
            // REPAY_TROVE_DEBT: Check live Trove debt and minNetDebt without double-counting pendingInterest
            uint256 btcPrice = priceFeed.fetchPrice();
            // Note: Debt repayment is allowed in both Normal and Recovery Mode, but we must never
            // push remaining net debt below BorrowerOperations.minNetDebt() (1,800 MUSD on Mezo Testnet).
            (
                uint256 entireColl,
                uint256 principal,
                uint256 interest,
                uint256 pendingColl,
                uint256 pendingPrincipal,
                uint256 pendingInterest
            ) = troveManager.getEntireDebtAndColl(user);
            pendingColl;
            pendingPrincipal;
            pendingInterest;
            uint256 entireDebt = principal + interest;
            uint256 minNetDebt = borrowerOperations.minNetDebt();
            bool isRecovery = troveManager.checkRecoveryMode(btcPrice);

            // Check if Trove is active, not blocked by Recovery Mode, and can accept repayment without breaching minNetDebt floor
            if (!isRecovery && entireColl > 0 && entireDebt > minNetDebt + 200e18 + amount) {
                require(musd.transfer(user, amount), "ERC20 call failed");
                borrowerOperations.repayMUSD(amount, address(0), address(0));
            } else {
                // Graceful fallback to sMUSD if Trove debt is already near the 1,800 MUSD minNetDebt floor
                // or if system is in Recovery Mode
                userSMUSDBalance[user] += amount;
                require(musd.approve(address(smusd), amount), "ERC20 call failed");
                uint256 shares = smusd.deposit(amount);
                shares;
            }
        }
    }

    /// @notice Withdraws compounded sMUSD back to the user as MUSD.
    function withdrawCompoundedSMUSD(uint256 amount) external {
        require(userSMUSDBalance[msg.sender] >= amount, "Insufficient sMUSD balance");
        userSMUSDBalance[msg.sender] -= amount;
        emit SMUSDWithdrawn(msg.sender, amount);
        uint256 withdrawn = smusd.withdraw(amount);
        withdrawn;
        require(musd.transfer(msg.sender, amount), "ERC20 call failed");
    }
}

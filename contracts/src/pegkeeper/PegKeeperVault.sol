// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IERC20,
    IMUSDSavingsRate,
    ITroveManager,
    IHintHelpers,
    ISortedTroves,
    IPriceFeed,
    ITigrisRouter
} from "./interfaces/IMezo.sol";

/// @title PegKeeperVault
/// @notice Hinted Redemption Arbitrage & Peg Defense Vault for Mezo MUSD.
/// @dev Parks idle MUSD in sMUSD (0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16). When MUSD trades below
///      $1.00 on Tigris, executes hinted redemptions via HintHelpers + SortedTroves + TroveManager.redeemCollateral,
///      swaps redeemed BTC back into discounted MUSD on Tigris, and compounds the net arbitrage spread.
contract PegKeeperVault {
    string public constant name = "PegKeeper Metrology Vault Share";
    string public constant symbol = "pkMUSD";
    uint8 public constant decimals = 18;

    IERC20 public immutable musd;
    IMUSDSavingsRate public immutable smusd;
    ITroveManager public immutable troveManager;
    IHintHelpers public immutable hintHelpers;
    ISortedTroves public immutable sortedTroves;
    IPriceFeed public immutable priceFeed;
    ITigrisRouter public immutable tigrisRouter;
    address public immutable wbtcPrecompile;

    address public feeTreasury;
    uint256 public totalSupply;
    uint256 public totalArbitrageProfitMUSD;
    uint256 public calibrationSerialCounter = 1000;
    uint256 public minProfitBps = 20; // 0.20% default minimum profit threshold

    /// @notice 10.00% protocol fee + 2.00% keeper bounty on net redemption arbitrage spread
    uint256 public constant PROTOCOL_FEE_BPS = 1000;
    uint256 public constant KEEPER_BOUNTY_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    mapping(address => uint256) public balanceOf;

    struct CalibrationReport {
        uint256 serialNo;
        uint256 timestamp;
        address keeper;
        uint256 musdRedeemed;
        uint256 btcReceived;
        uint256 musdSwappedBack;
        uint256 netProfitMUSD;
    }

    CalibrationReport[] public reports;

    event Deposited(address indexed user, uint256 musdAmount, uint256 sharesMinted);
    event Withdrawn(address indexed user, uint256 sharesBurned, uint256 musdReturned);
    event PegCalibrationExecuted(
        uint256 indexed serialNo,
        address indexed keeper,
        uint256 musdRedeemed,
        uint256 btcReceived,
        uint256 musdSwappedBack,
        uint256 netProfitMUSD
    );

    error ZeroAmount();
    error InsufficientShares();
    error RecoveryModeRedemptionBlocked();
    error RedemptionTruncatedToZero();
    error UnprofitablePegCycle(uint256 musdUsed, uint256 musdReturned, uint256 minRequired);

    constructor(
        address _musd,
        address _smusd,
        address _troveManager,
        address _hintHelpers,
        address _sortedTroves,
        address _priceFeed,
        address _tigrisRouter,
        address _wbtcPrecompile,
        address _feeTreasury
    ) {
        require(_musd != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_hintHelpers != address(0), "Zero address");
        require(_sortedTroves != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_tigrisRouter != address(0), "Zero address");
        require(_wbtcPrecompile != address(0), "Zero address");
        require(_feeTreasury != address(0), "Zero address");

        musd = IERC20(_musd);
        smusd = IMUSDSavingsRate(_smusd);
        troveManager = ITroveManager(_troveManager);
        hintHelpers = IHintHelpers(_hintHelpers);
        sortedTroves = ISortedTroves(_sortedTroves);
        priceFeed = IPriceFeed(_priceFeed);
        tigrisRouter = ITigrisRouter(_tigrisRouter);
        wbtcPrecompile = _wbtcPrecompile;
        feeTreasury = _feeTreasury;
    }

    /// @notice Total MUSD managed by the vault (sMUSD principal + claimable sMUSD yield + liquid MUSD).
    function totalAssets() public view returns (uint256) {
        return smusd.balanceOf(address(this)) + smusd.claimableYield(address(this)) + musd.balanceOf(address(this));
    }

    /// @notice Previews whether a hinted redemption cycle is executable in the current protocol state.
    function previewRedemptionOpportunity(uint256 musdToRedeem)
        external
        view
        returns (
            bool executable,
            address firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedMUSDAmount,
            uint256 btcPrice
        )
    {
        btcPrice = priceFeed.fetchPrice();
        bool inRecoveryMode = troveManager.checkRecoveryMode(btcPrice);
        (firstRedemptionHint, partialRedemptionHintNICR, truncatedMUSDAmount) =
            hintHelpers.getRedemptionHints(musdToRedeem, btcPrice, 35);
        executable = !inRecoveryMode && musdToRedeem > 0 && truncatedMUSDAmount > 0;
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
        emit Deposited(msg.sender, musdAmount, shares);

        // Interactions
        _harvestSMUSD();
        require(musd.transferFrom(msg.sender, address(this), musdAmount), "ERC20 call failed");
        require(musd.approve(address(smusd), musdAmount), "ERC20 call failed");
        smusd.deposit(musdAmount);
    }

    function withdraw(uint256 shares) external returns (uint256 musdOut) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < shares) revert InsufficientShares();

        musdOut = (shares * totalAssets()) / totalSupply;

        // Effects before external interactions
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        emit Withdrawn(msg.sender, shares, musdOut);

        // Interactions
        _harvestSMUSD();
        uint256 liquid = musd.balanceOf(address(this));
        if (liquid < musdOut) {
            smusd.withdraw(musdOut - liquid);
        }
        require(musd.transfer(msg.sender, musdOut), "ERC20 call failed");
    }

    /// @notice Computes on-chain redemption hints via HintHelpers & SortedTroves and executes
    ///         a profitable peg-defense redemption cycle.
    function executePegCalibration(
        uint256 musdToRedeem,
        uint256 maxIterations,
        uint256 minProfitBpsOrMaxFee
    ) external returns (uint256 netProfitMUSD) {
        if (musdToRedeem == 0) revert ZeroAmount();

        uint256 btcPrice = priceFeed.fetchPrice();
        if (troveManager.checkRecoveryMode(btcPrice)) revert RecoveryModeRedemptionBlocked();

        // 1. Compute exact redemption hints via HintHelpers and SortedTroves
        (
            address firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedMUSDAmount
        ) = hintHelpers.getRedemptionHints(musdToRedeem, btcPrice, maxIterations);

        if (truncatedMUSDAmount == 0) revert RedemptionTruncatedToZero();
        uint256 redeemAmount = truncatedMUSDAmount;

        (address upperPartialHint, address lowerPartialHint) = sortedTroves.findInsertPosition(
            partialRedemptionHintNICR,
            address(0),
            address(0)
        );

        uint256 effectiveMinBps = minProfitBpsOrMaxFee <= BPS_DENOMINATOR ? minProfitBpsOrMaxFee : minProfitBps;
        uint256 minRequiredOut = redeemAmount + (redeemAmount * effectiveMinBps) / BPS_DENOMINATOR;

        _harvestSMUSD();

        // 2. Pull MUSD from sMUSD reserve
        smusd.withdraw(redeemAmount);

        uint256 btcBefore = address(this).balance;
        uint256 musdBefore = musd.balanceOf(address(this)); // includes redeemAmount

        // 3. Execute TroveManager.redeemCollateral
        troveManager.redeemCollateral(
            redeemAmount,
            firstRedemptionHint,
            upperPartialHint,
            lowerPartialHint,
            partialRedemptionHintNICR,
            maxIterations
        );

        uint256 btcReceived = address(this).balance - btcBefore;

        // 4. Swap redeemed BTC back into discounted MUSD on TigrisRouter
        ITigrisRouter.Route[] memory routes = new ITigrisRouter.Route[](1);
        routes[0] = ITigrisRouter.Route({
            from: wbtcPrecompile,
            to: address(musd),
            stable: false,
            factory: tigrisRouter.defaultFactory()
        });

        tigrisRouter.swapExactETHForTokens{value: btcReceived}(
            redeemAmount,
            routes,
            address(this),
            block.timestamp
        );

        uint256 musdAfter = musd.balanceOf(address(this));
        uint256 musdSwappedBack = musdAfter - (musdBefore - redeemAmount);
        if (musdAfter <= musdBefore || musdSwappedBack < minRequiredOut) {
            revert UnprofitablePegCycle(redeemAmount, musdSwappedBack, minRequiredOut);
        }

        uint256 grossProfit = musdAfter - musdBefore;
        uint256 protocolFee = (grossProfit * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 keeperBounty = (grossProfit * KEEPER_BOUNTY_BPS) / BPS_DENOMINATOR;
        netProfitMUSD = grossProfit - protocolFee - keeperBounty;

        // Effects before external token transfers / re-deposits
        totalArbitrageProfitMUSD += netProfitMUSD;
        uint256 serial = ++calibrationSerialCounter;
        reports.push(
            CalibrationReport({
                serialNo: serial,
                timestamp: block.timestamp,
                keeper: msg.sender,
                musdRedeemed: redeemAmount,
                btcReceived: btcReceived,
                musdSwappedBack: musdSwappedBack,
                netProfitMUSD: netProfitMUSD
            })
        );
        // forge-lint: disable-next-line(reentrancy-events)
        emit PegCalibrationExecuted(serial, msg.sender, redeemAmount, btcReceived, musdSwappedBack, netProfitMUSD);

        // Interactions
        if (protocolFee > 0) {
            require(musd.transfer(feeTreasury, protocolFee), "ERC20 call failed");
        }
        if (keeperBounty > 0) {
            require(musd.transfer(msg.sender, keeperBounty), "ERC20 call failed");
        }

        // Re-park principal + net arbitrage profit back into sMUSD
        uint256 toReDeposit = musd.balanceOf(address(this));
        if (toReDeposit > 0) {
            require(musd.approve(address(smusd), toReDeposit), "ERC20 call failed");
            smusd.deposit(toReDeposit);
        }
    }

    function _harvestSMUSD() internal {
        uint256 claimable = smusd.claimableYield(address(this));
        if (claimable > 0) {
            uint256 y = smusd.claimYield();
            if (y > 0) {
                require(musd.approve(address(smusd), y), "ERC20 call failed");
                smusd.deposit(y);
            }
        }
    }

    function reportsLength() external view returns (uint256) {
        return reports.length;
    }

    receive() external payable {}
}

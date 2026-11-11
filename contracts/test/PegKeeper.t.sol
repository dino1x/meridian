// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PegKeeperVault} from "../src/pegkeeper/PegKeeperVault.sol";
import {ITigrisRouter} from "../src/pegkeeper/interfaces/IMezo.sol";

contract PegkeeperMockMUSD {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract PegkeeperMockSMUSD {
    PegkeeperMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public simYield;

    constructor(address _musd) {
        musd = PegkeeperMockMUSD(_musd);
    }

    function deposit(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        musd.transfer(msg.sender, amount);
    }

    function claimableYield(address acc) external view returns (uint256) {
        return simYield[acc];
    }

    function claimYield() external returns (uint256 y) {
        y = simYield[msg.sender];
        simYield[msg.sender] = 0;
        if (y > 0) musd.transfer(msg.sender, y);
    }
}

contract PegkeeperMockHintHelpers {
    bool public forceZeroTruncated;

    function setForceZeroTruncated(bool _force) external {
        forceZeroTruncated = _force;
    }

    function getRedemptionHints(uint256 amount, uint256, uint256)
        external
        view
        returns (address, uint256, uint256)
    {
        return (address(0x111), 1.25e18, forceZeroTruncated ? 0 : amount);
    }
}

contract PegkeeperMockSortedTroves {
    function findInsertPosition(uint256, address, address) external pure returns (address, address) {
        return (address(0x111), address(0x222));
    }
}

contract PegkeeperMockPF {
    function fetchPrice() external pure returns (uint256) {
        return 75_000e18;
    }
}

contract PegkeeperMockTM {
    PegkeeperMockMUSD public immutable musd;
    bool public recoveryMode;

    constructor(address _musd) {
        musd = PegkeeperMockMUSD(_musd);
    }

    function setRecoveryMode(bool _r) external {
        recoveryMode = _r;
    }

    function checkRecoveryMode(uint256) external view returns (bool) {
        return recoveryMode;
    }

    function redeemCollateral(uint256 amount, address, address, address, uint256, uint256) external {
        musd.burn(msg.sender, amount);
        // Send BTC worth `amount` at $75,000/BTC (minus 0.5% redemption fee)
        uint256 netUSD = (amount * 995) / 1000;
        uint256 btcOut = (netUSD * 1e18) / 75_000e18;
        (bool ok, ) = msg.sender.call{value: btcOut}("");
        require(ok, "btc send");
    }
}

contract PegkeeperMockTigrisRouter {
    PegkeeperMockMUSD public immutable musd;
    address public defaultFactory = address(0xFAC);
    // Simulate MUSD trading at $0.975 on Tigris -> 1 BTC ($75,000) buys 76,923 MUSD!
    uint256 public musdPerBTC = 76_923e18;
    uint256 public exactMusdOutOverride;

    constructor(address _musd) {
        musd = PegkeeperMockMUSD(_musd);
    }

    function setMusdPerBTC(uint256 _rate) external {
        musdPerBTC = _rate;
    }

    function setExactMusdOutOverride(uint256 _out) external {
        exactMusdOutOverride = _out;
    }

    function swapExactETHForTokens(
        uint256,
        ITigrisRouter.Route[] calldata,
        address to,
        uint256
    ) external payable returns (uint256[] memory amounts) {
        uint256 out = exactMusdOutOverride > 0 ? exactMusdOutOverride : (msg.value * musdPerBTC) / 1e18;
        musd.mint(to, out);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = out;
    }
}

contract PegKeeperTest is Test {
    PegkeeperMockMUSD internal musd;
    PegkeeperMockSMUSD internal smusd;
    PegkeeperMockHintHelpers internal hh;
    PegkeeperMockSortedTroves internal st;
    PegkeeperMockPF internal pf;
    PegkeeperMockTM internal tm;
    PegkeeperMockTigrisRouter internal router;
    PegKeeperVault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal keeper = address(0xBEEF);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new PegkeeperMockMUSD();
        smusd = new PegkeeperMockSMUSD(address(musd));
        hh = new PegkeeperMockHintHelpers();
        st = new PegkeeperMockSortedTroves();
        pf = new PegkeeperMockPF();
        tm = new PegkeeperMockTM(address(musd));
        router = new PegkeeperMockTigrisRouter(address(musd));

        vm.deal(address(tm), 10_000 ether);

        vault = new PegKeeperVault(
            address(musd),
            address(smusd),
            address(tm),
            address(hh),
            address(st),
            address(pf),
            address(router),
            address(0x7b7C000000000000000000000000000000000000),
            treasury
        );

        musd.mint(alice, 50_000e18);
        musd.mint(bob, 50_000e18);
    }

    function test_DepositAndExecuteHintedRedemptionArbitrage() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        uint256 shares = vault.deposit(10_000e18);
        vm.stopPrank();

        assertEq(shares, 10_000e18);

        // Execute hinted redemption on 5,000 MUSD when MUSD trades at $0.975
        vm.prank(keeper);
        uint256 netProfit = vault.executePegCalibration(5_000e18, 10, 5e16);

        assertGt(netProfit, 80e18, "Vault captured >80 MUSD net arbitrage spread");
        assertGt(musd.balanceOf(keeper), 0, "Keeper earned bounty");
        assertGt(musd.balanceOf(treasury), 0, "Protocol earned fee");
        assertEq(vault.reportsLength(), 1);

        // Alice withdraws her shares and receives >10,000 MUSD
        vm.prank(alice);
        uint256 musdOut = vault.withdraw(shares);
        assertEq(musdOut, 10_000e18 + netProfit);
    }

    function test_BlocksRedemptionInRecoveryModeAndPreviewsOpportunity() public {
        (bool executableNormal, address hint, uint256 nicr, uint256 truncated, uint256 price) =
            vault.previewRedemptionOpportunity(5_000e18);
        assertTrue(executableNormal, "Executable in Normal Mode");
        assertEq(hint, address(0x111));
        assertEq(nicr, 1.25e18);
        assertEq(truncated, 5_000e18);
        assertEq(price, 75_000e18);

        vm.startPrank(alice);
        musd.approve(address(vault), 5_000e18);
        vault.deposit(5_000e18);
        vm.stopPrank();

        tm.setRecoveryMode(true);
        (bool executableRecovery, , , , ) = vault.previewRedemptionOpportunity(5_000e18);
        assertFalse(executableRecovery, "Not executable in Recovery Mode");

        vm.prank(keeper);
        vm.expectRevert(PegKeeperVault.RecoveryModeRedemptionBlocked.selector);
        vault.executePegCalibration(2_000e18, 10, 5e16);
    }

    function test_RevertWhen_InvalidShareAmountsOrZeroTruncatedRedemption() public {
        vm.startPrank(alice);
        vm.expectRevert(PegKeeperVault.ZeroAmount.selector);
        vault.deposit(0);

        vm.expectRevert(PegKeeperVault.ZeroAmount.selector);
        vault.withdraw(0);

        musd.approve(address(vault), 10_000e18);
        uint256 shares = vault.deposit(10_000e18);

        vm.expectRevert(PegKeeperVault.InsufficientShares.selector);
        vault.withdraw(shares + 1);
        vm.stopPrank();

        hh.setForceZeroTruncated(true);
        vm.prank(keeper);
        vm.expectRevert(PegKeeperVault.RedemptionTruncatedToZero.selector);
        vault.executePegCalibration(5_000e18, 10, 20);
    }

    function test_RevertWhen_CycleIsUnprofitableBelowMinProfitBps() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        vault.deposit(10_000e18);
        vm.stopPrank();

        // Swap output only returns 5,005 MUSD on 5,000 MUSD redeemed (+10 bps), below 50 bps minProfitBps
        router.setExactMusdOutOverride(5_005e18);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                PegKeeperVault.UnprofitablePegCycle.selector,
                5_000e18,
                5_005e18,
                5_025e18
            )
        );
        vault.executePegCalibration(5_000e18, 10, 50);
    }

    function test_MultiUserSharePriceAppreciationAfterArbitrageCycle() public {
        // Alice deposits 10,000 MUSD (1/3 of pool) and Bob deposits 20,000 MUSD (2/3 of pool)
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        uint256 aliceShares = vault.deposit(10_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        musd.approve(address(vault), 20_000e18);
        uint256 bobShares = vault.deposit(20_000e18);
        vm.stopPrank();

        // Arbitrage cycle on 15,000 MUSD returns 15,600 MUSD (+600 MUSD gross profit -> +528 MUSD net after 12% fees)
        router.setExactMusdOutOverride(15_600e18);
        vm.prank(keeper);
        uint256 netProfit = vault.executePegCalibration(15_000e18, 10, 20);
        assertEq(netProfit, 528e18);

        vm.prank(alice);
        uint256 aliceOut = vault.withdraw(aliceShares);
        vm.prank(bob);
        uint256 bobOut = vault.withdraw(bobShares);

        // Alice receives 10,000 + 1/3 of 528 = 10,176 MUSD; Bob receives 20,000 + 2/3 of 528 = 20,352 MUSD
        assertEq(aliceOut, 10_176e18);
        assertEq(bobOut, 20_352e18);
    }

    function test_KeeperTipAndProtocolFeeSplitOnProfitOnly() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        vault.deposit(10_000e18);
        vm.stopPrank();

        // 10,000 MUSD redeemed -> 10,500 MUSD returned from DEX -> 500 MUSD gross arbitrage profit
        router.setExactMusdOutOverride(10_500e18);

        vm.prank(keeper);
        uint256 netProfit = vault.executePegCalibration(10_000e18, 10, 20);

        // 10% protocol fee on 500 MUSD = 50 MUSD; 2% keeper bounty on 500 MUSD = 10 MUSD; 88% net = 440 MUSD
        assertEq(musd.balanceOf(treasury), 50e18, "10% protocol fee charged strictly on profit");
        assertEq(musd.balanceOf(keeper), 10e18, "2% keeper bounty charged strictly on profit");
        assertEq(netProfit, 440e18, "88% net profit retained by vault depositors");
        assertEq(vault.totalAssets(), 10_440e18, "Principal + 88% profit compounded in sMUSD");
    }

    function testFuzz_DepositRedemptionAndWithdrawConservesVaultAccounting(
        uint256 depositAmt,
        uint256 arbBonus
    ) public {
        depositAmt = bound(depositAmt, 1_000e18, 500_000e18);
        arbBonus = bound(arbBonus, 50e18, 10_000e18);

        address fuzzer = address(0xF022);
        musd.mint(fuzzer, depositAmt);

        vm.startPrank(fuzzer);
        musd.approve(address(vault), depositAmt);
        uint256 shares = vault.deposit(depositAmt);
        vm.stopPrank();

        router.setExactMusdOutOverride(depositAmt + arbBonus);

        vm.prank(keeper);
        uint256 netProfit = vault.executePegCalibration(depositAmt, 10, 1);

        uint256 expectedProtocolFee = (arbBonus * 1000) / 10_000;
        uint256 expectedKeeperBounty = (arbBonus * 200) / 10_000;
        uint256 expectedNetProfit = arbBonus - expectedProtocolFee - expectedKeeperBounty;

        assertEq(netProfit, expectedNetProfit);

        vm.prank(fuzzer);
        uint256 withdrawn = vault.withdraw(shares);
        assertEq(withdrawn, depositAmt + expectedNetProfit);
        assertEq(vault.totalSupply(), 0);
    }
}

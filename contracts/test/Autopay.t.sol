// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AutopayFactory} from "../src/autopay/AutopayFactory.sol";
import {TroveVault} from "../src/autopay/TroveVault.sol";

contract AutopayMockMUSD {
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

contract AutopayMockPF {
    uint256 public price = 76_559e18;

    function setPrice(uint256 _p) external {
        price = _p;
    }

    function fetchPrice() external view returns (uint256) {
        return price;
    }
}

contract AutopayMockTM {
    uint256 public constant MCR = 1.1e18;
    uint256 public constant CCR = 1.5e18;
    bool public recoveryMode;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public coll;

    function setRecoveryMode(bool _r) external {
        recoveryMode = _r;
    }

    function setTrove(address u, uint256 d, uint256 c) external {
        debt[u] = d;
        coll[u] = c;
    }

    function checkRecoveryMode(uint256) external view returns (bool) {
        return recoveryMode;
    }

    function getEntireDebtAndColl(address u)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        uint256 d = debt[u];
        uint256 p = d > 12e18 ? d - 12e18 : d;
        return (coll[u], p, d > 12e18 ? 12e18 : 0, 0, 0, 12e18);
    }
}

contract AutopayMockBO {
    AutopayMockMUSD public immutable musd;
    AutopayMockTM public immutable tm;
    uint256 public minNetDebt = 1800e18;
    uint256 public borrowingRate = 1e15;
    uint256 public constant MUSD_GAS_COMPENSATION = 200e18;

    constructor(address _musd, address _tm) {
        musd = AutopayMockMUSD(_musd);
        tm = AutopayMockTM(_tm);
    }

    function openTrove(uint256 musdAmount, address, address) external payable {
        uint256 fee = (musdAmount * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, musdAmount + fee + MUSD_GAS_COMPENSATION, msg.value);
        musd.mint(msg.sender, musdAmount);
    }

    function repayMUSD(uint256 amount, address, address) external {
        musd.burn(msg.sender, amount);
        (uint256 c, uint256 p, uint256 i, , , ) = tm.getEntireDebtAndColl(msg.sender);
        tm.setTrove(msg.sender, p + i - amount, c);
    }

    function withdrawMUSD(uint256 amount, address, address) external {
        (uint256 c, uint256 p, uint256 i, , , ) = tm.getEntireDebtAndColl(msg.sender);
        tm.setTrove(msg.sender, p + i + amount, c);
        musd.mint(msg.sender, amount);
    }
}

contract AutopayMockSMUSD {
    AutopayMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public simYield;

    constructor(address _musd) {
        musd = AutopayMockMUSD(_musd);
    }

    function deposit(uint256 amount) external {
        require(musd.transferFrom(msg.sender, address(this), amount), "ERC20 call failed");
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        require(musd.transfer(msg.sender, amount), "ERC20 call failed");
    }

    function addYield(address acc, uint256 y) external {
        musd.mint(address(this), y);
        simYield[acc] += y;
    }

    function claimableYield(address acc) external view returns (uint256) {
        return simYield[acc];
    }

    function claimYield() external returns (uint256 y) {
        y = simYield[msg.sender];
        simYield[msg.sender] = 0;
        if (y > 0) {
            require(musd.transfer(msg.sender, y), "ERC20 call failed");
        }
    }
}

contract AutopayMockSP {
    AutopayMockMUSD public immutable musd;
    AutopayMockTM public immutable tm;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public gains;

    constructor(address _musd, address _tm) {
        musd = AutopayMockMUSD(_musd);
        tm = AutopayMockTM(_tm);
    }

    function provideToSP(uint256 amount) external {
        require(musd.transferFrom(msg.sender, address(this), amount), "ERC20 call failed");
        deposits[msg.sender] += amount;
    }

    function withdrawFromSP(uint256 amount) external {
        deposits[msg.sender] -= amount;
        require(musd.transfer(msg.sender, amount), "ERC20 call failed");
    }

    function setCollateralGain(address acc, uint256 btcGain) external {
        gains[acc] = btcGain;
    }

    function getDepositorCollateralGain(address acc) external view returns (uint256) {
        return gains[acc];
    }

    function getCompoundedMUSDDeposit(address acc) external view returns (uint256) {
        return deposits[acc];
    }

    function withdrawCollateralGainToTrove(address, address) external {
        uint256 g = gains[msg.sender];
        gains[msg.sender] = 0;
        (uint256 c, uint256 p, uint256 i, , , ) = tm.getEntireDebtAndColl(msg.sender);
        tm.setTrove(msg.sender, p + i, c + g);
    }
}

contract AutopayTest is Test {
    AutopayMockMUSD internal musd;
    AutopayMockPF internal pf;
    AutopayMockTM internal tm;
    AutopayMockBO internal bo;
    AutopayMockSMUSD internal smusd;
    AutopayMockSP internal sp;
    AutopayFactory internal factory;

    address internal alice = address(0xA11CE);
    address internal keeper = address(0xBEEF);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new AutopayMockMUSD();
        pf = new AutopayMockPF();
        tm = new AutopayMockTM();
        bo = new AutopayMockBO(address(musd), address(tm));
        smusd = new AutopayMockSMUSD(address(musd));
        sp = new AutopayMockSP(address(musd), address(tm));

        factory = new AutopayFactory(
            address(bo),
            address(tm),
            address(sp),
            address(smusd),
            address(pf),
            address(musd),
            treasury
        );

        vm.deal(alice, 10 ether);
    }

    function test_PlantVaultAndHarvestAndStrengthenTrove() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18); // 30% reserve, 135%-220% band
        TroveVault vault = TroveVault(payable(vAddr));
        vault.openSelfPayingTrove{value: 0.1 ether}(3_000e18, 5e16, address(0), address(0));
        vm.stopPrank();

        // 70% spendable (2,100 MUSD) sent to Alice, 30% (900 MUSD) split 450 sMUSD + 450 SP
        assertEq(musd.balanceOf(alice), 2_100e18);
        assertEq(smusd.balanceOf(vAddr), 450e18);
        assertEq(sp.deposits(vAddr), 450e18);

        // Simulate 200 MUSD yield in sMUSD and 0.01 BTC liquidation gain in StabilityPool
        smusd.addYield(vAddr, 200e18);
        sp.setCollateralGain(vAddr, 0.01 ether);

        (uint256 collBefore, uint256 pBefore, uint256 iBefore, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtBefore = pBefore + iBefore;

        vm.prank(keeper);
        (uint256 debtRepaid, uint256 btcAdded) = vault.harvestAndStrengthen(address(0), address(0));

        (uint256 collAfter, uint256 pAfter, uint256 iAfter, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtAfter = pAfter + iAfter;
        assertEq(debtBefore - debtAfter, debtRepaid);
        assertEq(collAfter - collBefore, 0.01 ether);
        assertEq(btcAdded, 0.01 ether);
        assertEq(vault.growthRingCount(), 2);
    }

    function test_BandRebalanceDefensiveInRecoveryModeAndSkimOnBTCAppreciation() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        // 0.06 BTC at $76,559 = $4,593.54 vs ~3,203 MUSD debt = 143.4% ICR
        // In Normal Mode, 143.4% > 135% lowerBandICR, so no defensive rebalance needed.
        vault.openSelfPayingTrove{value: 0.06 ether}(3_000e18, 5e16, address(0), address(0));
        vm.stopPrank();

        // Flip system into Recovery Mode (TCR < 150% -> effectiveLowerBand automatically jumps from 135% to CCR=150%!)
        tm.setRecoveryMode(true);

        vm.prank(keeper);
        (bool wasDefensive, uint256 repaidMUSD) = vault.rebalanceBand(5e16, address(0), address(0));
        assertTrue(wasDefensive, "Recovery Mode raised threshold to 150% CCR and triggered defensive repayment");
        assertGt(repaidMUSD, 0);

        // Now turn off Recovery Mode and pump BTC to $120,000 -> ICR jumps above 220% upperBandICR
        tm.setRecoveryMode(false);
        pf.setPrice(120_000e18);

        vm.prank(keeper);
        (bool wasDefensive2, uint256 skimmedMUSD) = vault.rebalanceBand(5e16, address(0), address(0));
        assertFalse(wasDefensive2, "Capacity skimmed into sMUSD when ICR > upperBandICR");
        assertGt(skimmedMUSD, 0);
    }

    function test_RevertWhen_OpenTroveBelowMinNetDebt1800MUSD() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        vm.expectRevert(
            abi.encodeWithSelector(TroveVault.BelowMinNetDebt.selector, 1_500e18, 1_800e18)
        );
        vault.openSelfPayingTrove{value: 0.1 ether}(1_500e18, 5e16, address(0), address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_OpenTroveBelowMCRInNormalMode() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        // 0.025 BTC at $76,559 = $1,913.975 against ~2,001.8 MUSD total debt (~95.6% ICR < 110% MCR)
        vm.expectRevert();
        vault.openSelfPayingTrove{value: 0.025 ether}(1_800e18, 5e16, address(0), address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_OpenTroveBelowCCRInRecoveryMode() public {
        tm.setRecoveryMode(true);
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        // 0.035 BTC at $76,559 = $2,679.565 against ~2,001.8 MUSD total debt (~133.8% ICR < 150% CCR)
        vm.expectRevert();
        vault.openSelfPayingTrove{value: 0.035 ether}(1_800e18, 5e16, address(0), address(0));
        vm.stopPrank();
    }

    function test_HarvestWhenNearMinNetDebtFloorParksYieldInSMUSD() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        // Open right at 1,800 MUSD minNetDebt -> total debt is ~2,001.8 MUSD (floor is 2,000 MUSD)
        vault.openSelfPayingTrove{value: 0.1 ether}(1_800e18, 5e16, address(0), address(0));
        vm.stopPrank();

        uint256 smusdBefore = smusd.balanceOf(vAddr);
        (, uint256 pBefore, uint256 iBefore, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtBefore = pBefore + iBefore;

        // Add 100 MUSD yield: repaying ~98.5 MUSD would drop debt below the 2,000 MUSD floor, so it parks in sMUSD
        smusd.addYield(vAddr, 100e18);

        vm.prank(keeper);
        (uint256 netDebtRepaid, ) = vault.harvestAndStrengthen(address(0), address(0));

        (, uint256 pAfter, uint256 iAfter, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtAfter = pAfter + iAfter;

        assertEq(netDebtRepaid, 0, "No debt repayment when near minNetDebt floor");
        assertEq(debtAfter, debtBefore, "Trove debt unchanged");
        assertEq(smusd.balanceOf(vAddr) - smusdBefore, 98.5e18, "Net harvested yield compounded into sMUSD");
    }

    function test_RevertWhen_InvalidReserveBpsOrBandConfiguration() public {
        vm.startPrank(alice);
        // reserveBps > 8000 reverts
        vm.expectRevert(TroveVault.InvalidBandConfig.selector);
        factory.plantVault(8500, 1.35e18, 2.20e18);

        // lowerBandICR >= upperBandICR reverts
        vm.expectRevert(TroveVault.InvalidBandConfig.selector);
        factory.plantVault(3000, 2.20e18, 1.80e18);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerCallsOpenSelfPayingTrove() public {
        vm.prank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));

        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        vm.expectRevert(TroveVault.NotOwner.selector);
        vault.openSelfPayingTrove{value: 0.1 ether}(3_000e18, 5e16, address(0), address(0));
    }

    function test_KeeperAndProtocolFeeAccountingOnHarvest() public {
        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        vault.openSelfPayingTrove{value: 0.1 ether}(4_000e18, 5e16, address(0), address(0));
        vm.stopPrank();

        // Simulate 1,000 MUSD yield in sMUSD
        smusd.addYield(vAddr, 1_000e18);

        uint256 treasuryBefore = musd.balanceOf(treasury);
        uint256 keeperBefore = musd.balanceOf(keeper);

        vm.prank(keeper);
        (uint256 netDebtRepaid, ) = vault.harvestAndStrengthen(address(0), address(0));

        assertEq(musd.balanceOf(treasury) - treasuryBefore, 10e18, "1.00% protocol fee (10 MUSD)");
        assertEq(musd.balanceOf(keeper) - keeperBefore, 5e18, "0.50% keeper tip (5 MUSD)");
        assertEq(netDebtRepaid, 985e18, "98.50% net yield used to repay Trove debt");
    }

    function testFuzz_HarvestAndStrengthenReducesDebtMonotonically(uint256 yieldAmount, uint256 btcGain) public {
        yieldAmount = bound(yieldAmount, 10e18, 1_000e18);
        btcGain = bound(btcGain, 0.001 ether, 0.5 ether);

        vm.startPrank(alice);
        address vAddr = factory.plantVault(3000, 1.35e18, 2.20e18);
        TroveVault vault = TroveVault(payable(vAddr));
        vault.openSelfPayingTrove{value: 0.15 ether}(5_000e18, 5e16, address(0), address(0));
        vm.stopPrank();

        uint256 btcPrice = pf.fetchPrice();
        (uint256 collBefore, uint256 pBefore, uint256 iBefore, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtBefore = pBefore + iBefore;
        uint256 icrBefore = (collBefore * btcPrice) / debtBefore;

        smusd.addYield(vAddr, yieldAmount);
        sp.setCollateralGain(vAddr, btcGain);

        vm.prank(keeper);
        vault.harvestAndStrengthen(address(0), address(0));

        (uint256 collAfter, uint256 pAfter, uint256 iAfter, , , ) = tm.getEntireDebtAndColl(vAddr);
        uint256 debtAfter = pAfter + iAfter;
        uint256 icrAfter = (collAfter * btcPrice) / debtAfter;

        assertLt(debtAfter, debtBefore, "Post-harvest debt strictly lower than pre-harvest debt");
        assertGt(collAfter, collBefore, "Post-harvest collateral strictly greater than pre-harvest collateral");
        assertGt(icrAfter, icrBefore, "Post-harvest ICR strictly greater than pre-harvest ICR");
    }

    function test_MultipleVaultsTrackedIndependentlyByFactory() public {
        address bob = address(0xB0B);
        vm.deal(bob, 10 ether);

        vm.prank(alice);
        address aliceVault = factory.plantVault(2500, 1.30e18, 2.10e18);

        vm.prank(bob);
        address bobVault = factory.plantVault(4000, 1.40e18, 2.40e18);

        assertTrue(aliceVault != bobVault, "Distinct EIP-1167 clone addresses");
        assertEq(factory.userVault(alice), aliceVault);
        assertEq(factory.userVault(bob), bobVault);
        assertEq(factory.allVaultsLength(), 2);
        assertEq(factory.allVaults(0), aliceVault);
        assertEq(factory.allVaults(1), bobVault);
        assertEq(TroveVault(payable(aliceVault)).owner(), alice);
        assertEq(TroveVault(payable(bobVault)).owner(), bob);
        assertEq(TroveVault(payable(aliceVault)).reserveBps(), 2500);
        assertEq(TroveVault(payable(bobVault)).reserveBps(), 4000);
    }
}

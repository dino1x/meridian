// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KeeperGrid} from "../src/keepergrid/KeeperGrid.sol";

contract KeepergridMockMUSD {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
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

contract KeepergridMockSMUSD {
    KeepergridMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;

    constructor(address _musd) {
        musd = KeepergridMockMUSD(_musd);
    }

    function deposit(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        musd.transfer(msg.sender, amount);
    }
}

contract KeepergridMockTM {
    uint256 public constant MCR = 1.1e18;
    uint256 public constant CCR = 1.5e18;
    bool public recoveryMode;
    uint256 public liquidatedBatches;
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
        return (coll[u], debt[u], 0, 0, 0, 10e18);
    }

    function liquidateTroves(uint256 n) external {
        liquidatedBatches += n;
    }

    function redeemCollateral(
        uint256 _MUSDAmount,
        address,
        address,
        address,
        uint256,
        uint256
    ) external {
        uint256 btcToSend = (_MUSDAmount * 1e18) / 75_000e18;
        (bool ok, ) = msg.sender.call{value: btcToSend}("");
        require(ok, "KeepergridMock redeem send failed");
    }

    receive() external payable {}
}

contract KeepergridMockBO {
    uint256 public lastRepaid;

    function repayMUSD(uint256 amount, address, address) external {
        lastRepaid += amount;
    }
}

contract KeepergridMockHH {
    function getRedemptionHints(
        uint256 _MUSDamount,
        uint256,
        uint256
    ) external pure returns (address firstRedemptionHint, uint256 partialRedemptionHintNICR, uint256 truncatedMUSDamount) {
        return (address(0xBEEF), 1.5e18, _MUSDamount);
    }
}

contract KeepergridMockST {
    function findInsertPosition(
        uint256,
        address,
        address
    ) external pure returns (address, address) {
        return (address(0xCAFE), address(0xBABE));
    }
}
contract KeepergridMockBV {
    uint256 public lastPokedTokenId;
    uint256 public pokeCount;

    function poke(uint256 _tokenId) external {
        lastPokedTokenId = _tokenId;
        pokeCount += 1;
    }
}
contract KeepergridMockPF {
    function fetchPrice() external pure returns (uint256) {
        return 75_000e18;
    }
}

contract KeeperGridTest is Test {
    KeepergridMockMUSD internal musd;
    KeepergridMockSMUSD internal smusd;
    KeepergridMockTM internal tm;
    KeepergridMockBO internal bo;
    KeepergridMockHH internal hh;
    KeepergridMockST internal st;
    KeepergridMockPF internal pf;
    KeepergridMockBV internal bv;
    KeeperGrid internal grid;

    address internal keeper1 = address(0x1111);
    address internal keeper2 = address(0x2222);
    address internal poster = address(0x3333);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new KeepergridMockMUSD();
        smusd = new KeepergridMockSMUSD(address(musd));
        tm = new KeepergridMockTM();
        bo = new KeepergridMockBO();
        hh = new KeepergridMockHH();
        st = new KeepergridMockST();
        pf = new KeepergridMockPF();
        bv = new KeepergridMockBV();

        grid = new KeeperGrid(
            address(musd),
            address(smusd),
            address(bo),
            address(tm),
            address(hh),
            address(st),
            address(pf),
            address(bv),
            treasury
        );

        musd.mint(keeper1, 5_000e18);
        musd.mint(keeper2, 5_000e18);
        musd.mint(poster, 10_000e18);
    }

    function test_KeeperBondSlashingWhenAssignedKeeperMissesSlotWindow() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 1_000e18);
        grid.postKeeperBond(1_000e18);
        vm.stopPrank();

        vm.startPrank(keeper2);
        musd.approve(address(grid), 1_000e18);
        grid.postKeeperBond(1_000e18);
        vm.stopPrank();

        // Poster posts a Batch Liquidation job (assigned to keeper1 via round-robin) with 50 MUSD tip
        vm.startPrank(poster);
        musd.approve(address(grid), 50e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.BATCH_LIQUIDATION,
            address(tm),
            5,
            0,
            50e18
        );
        vm.stopPrank();

        // Keeper2 tries to execute before slotDeadline -> reverts!
        vm.prank(keeper2);
        vm.expectRevert();
        grid.executeSignalJob(jobId, address(0), address(0));

        // Warp past the 15-minute slotDeadline -> Keeper1 missed their window!
        vm.warp(block.timestamp + 16 minutes);

        // Keeper2 steps in, executes the job, and claims the 50 MUSD tip + 100 MUSD (10% slash of Keeper1's 1,000 MUSD bond)!
        vm.prank(keeper2);
        uint256 payout = grid.executeSignalJob(jobId, address(0), address(0));

        // 150 MUSD gross - 5% protocol fee (7.5 MUSD) = 142.5 MUSD
        assertEq(payout, 142.5e18);
        (, uint256 k1BondAfter, , , uint256 k1Slashes, ) = grid.keepers(keeper1);
        assertEq(k1BondAfter, 900e18);
        assertEq(k1Slashes, 1);
    }

    function test_RecoveryModeAwareTroveTopupJob() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 1_000e18);
        grid.postKeeperBond(1_000e18);
        vm.stopPrank();

        // Borrower has 0.06 BTC ($4,500 at $75k) and 3,100 MUSD debt -> 145.1% ICR
        // Poster sets normal triggerICR = 130%, but when Recovery Mode is active, trigger auto-raises to CCR=150%!
        tm.setTrove(poster, 3_100e18, 0.06 ether);
        tm.setRecoveryMode(true);

        vm.startPrank(poster);
        musd.approve(address(grid), 520e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.TROVE_TOPUP,
            poster,
            500e18,
            1.30e18,
            20e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        grid.executeSignalJob(jobId, address(0), address(0));
        assertEq(bo.lastRepaid(), 500e18);
    }

    function test_RevertWhen_RegisterKeeperBelowMinBond500MUSD() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 499e18);
        vm.expectRevert(abi.encodeWithSelector(KeeperGrid.BondBelowMinimum.selector, 499e18, 500e18));
        grid.postKeeperBond(499e18);
        vm.stopPrank();
    }

    function test_AssignedKeeperExecutesInWindowWithoutSlashing() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 1_000e18);
        grid.postKeeperBond(1_000e18);
        vm.stopPrank();

        vm.startPrank(poster);
        musd.approve(address(grid), 100e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.BATCH_LIQUIDATION,
            address(tm),
            3,
            0,
            100e18
        );
        vm.stopPrank();

        uint256 k1BalBefore = musd.balanceOf(keeper1);
        vm.prank(keeper1);
        uint256 payout = grid.executeSignalJob(jobId, address(0), address(0));

        // 95% of 100 MUSD = 95 MUSD to keeper1, 5 MUSD to treasury, zero slashing
        assertEq(payout, 95e18);
        assertEq(musd.balanceOf(keeper1) - k1BalBefore, 95e18);
        assertEq(musd.balanceOf(treasury), 5e18);
        (, uint256 k1BondAfter, uint256 jobsDone, uint256 totalTips, uint256 slashes, bool active) = grid.keepers(keeper1);
        assertEq(k1BondAfter, 1_000e18);
        assertEq(jobsDone, 1);
        assertEq(totalTips, 95e18);
        assertEq(slashes, 0);
        assertTrue(active);
    }

    function test_RevertWhen_UnassignedKeeperTriesToExecuteBeforeWindowExpires() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 600e18);
        grid.postKeeperBond(600e18);
        vm.stopPrank();

        vm.startPrank(keeper2);
        musd.approve(address(grid), 600e18);
        grid.postKeeperBond(600e18);
        vm.stopPrank();

        vm.startPrank(poster);
        musd.approve(address(grid), 40e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.BATCH_LIQUIDATION,
            address(tm),
            2,
            0,
            40e18
        );
        vm.stopPrank();

        uint256 expectedDeadline = block.timestamp + grid.SLOT_WINDOW();
        vm.prank(keeper2);
        vm.expectRevert(
            abi.encodeWithSelector(KeeperGrid.AssignedKeeperWindowStillOpen.selector, keeper1, expectedDeadline)
        );
        grid.executeSignalJob(jobId, address(0), address(0));
    }

    function test_RevertWhen_TroveTopupCalledOnHealthyTrove() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 1_000e18);
        grid.postKeeperBond(1_000e18);
        vm.stopPrank();

        // Borrower has 0.10 BTC ($7,500 at $75k) and 3,000 MUSD debt -> 250% ICR (healthy above 135% trigger)
        tm.setTrove(poster, 3_000e18, 0.10 ether);
        tm.setRecoveryMode(false);

        vm.startPrank(poster);
        musd.approve(address(grid), 330e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.TROVE_TOPUP,
            poster,
            300e18,
            1.35e18,
            30e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(KeeperGrid.TroveHealthyAboveThreshold.selector, 2.5e18, 1.35e18)
        );
        grid.executeSignalJob(jobId, address(0), address(0));
    }

    function test_GaugeEpochPokeJobExecution() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 800e18);
        grid.postKeeperBond(800e18);
        vm.stopPrank();

        vm.startPrank(poster);
        musd.approve(address(grid), 60e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.GAUGE_EPOCH_POKE,
            address(bv),
            42,
            0,
            60e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        uint256 payout = grid.executeSignalJob(jobId, address(0), address(0));

        assertEq(bv.lastPokedTokenId(), 42);
        assertEq(bv.pokeCount(), 1);
        assertEq(payout, 57e18); // 95% of 60 MUSD
        assertEq(musd.balanceOf(treasury), 3e18);
    }

    function test_UnbondKeeperWithdrawsProductiveSMUSD() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 800e18);
        grid.postKeeperBond(800e18);

        assertEq(smusd.balanceOf(address(grid)), 800e18);

        // Partial withdraw of 200 MUSD keeps bond at 600 MUSD (>= 500 MUSD min), still active
        grid.withdrawKeeperBond(200e18);
        (, uint256 bondMid, , , , bool activeMid) = grid.keepers(keeper1);
        assertEq(bondMid, 600e18);
        assertTrue(activeMid);

        // Withdraw remaining 600 MUSD -> bond drops below 500 MUSD, node deactivated
        grid.withdrawKeeperBond(600e18);
        (, uint256 bondAfter, , , , bool activeAfter) = grid.keepers(keeper1);
        assertEq(bondAfter, 0);
        assertFalse(activeAfter);
        assertEq(musd.balanceOf(keeper1), 5_000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_ExecuteExpiredOrAlreadyExecutedJob() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 700e18);
        grid.postKeeperBond(700e18);
        vm.stopPrank();

        vm.startPrank(poster);
        musd.approve(address(grid), 20e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.GAUGE_EPOCH_POKE,
            address(bv),
            7,
            0,
            20e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        grid.executeSignalJob(jobId, address(0), address(0));

        // Second execution attempt on already executed job reverts with JobNotExecutable
        vm.prank(keeper1);
        vm.expectRevert(KeeperGrid.JobNotExecutable.selector);
        grid.executeSignalJob(jobId, address(0), address(0));

        // Unbonded keeper trying to execute also reverts with NotActiveKeeper
        vm.prank(address(0x9999));
        vm.expectRevert(KeeperGrid.NotActiveKeeper.selector);
        grid.executeSignalJob(jobId, address(0), address(0));
    }

    function testFuzz_SlashingAndProtocolFeeAccountingExact(uint256 bondAmount, uint256 tipAmount) public {
        bondAmount = bound(bondAmount, 500e18, 50_000e18);
        tipAmount = bound(tipAmount, 10e18, 5_000e18);

        address k1 = address(0xA11CE);
        address k2 = address(0xB0B);
        address user = address(0xCAFE);

        musd.mint(k1, bondAmount);
        musd.mint(k2, bondAmount);
        musd.mint(user, tipAmount);

        vm.startPrank(k1);
        musd.approve(address(grid), bondAmount);
        grid.postKeeperBond(bondAmount);
        vm.stopPrank();

        vm.startPrank(k2);
        musd.approve(address(grid), bondAmount);
        grid.postKeeperBond(bondAmount);
        vm.stopPrank();

        vm.startPrank(user);
        musd.approve(address(grid), tipAmount);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.BATCH_LIQUIDATION,
            address(tm),
            1,
            0,
            tipAmount
        );
        vm.stopPrank();

        // Advance past slot window so k1 misses their slot
        vm.warp(block.timestamp + grid.SLOT_WINDOW() + 1);

        uint256 treasuryBefore = musd.balanceOf(treasury);
        uint256 k2Before = musd.balanceOf(k2);

        vm.prank(k2);
        uint256 payout = grid.executeSignalJob(jobId, address(0), address(0));

        uint256 expectedSlash = (bondAmount * grid.SLASH_BPS()) / grid.BPS_DENOMINATOR();
        uint256 grossReward = tipAmount + expectedSlash;
        uint256 expectedProtoFee = (grossReward * grid.PROTOCOL_FEE_BPS()) / grid.BPS_DENOMINATOR();
        uint256 expectedKeeperPayout = grossReward - expectedProtoFee;

        assertEq(payout, expectedKeeperPayout);
        assertEq(musd.balanceOf(k2) - k2Before, expectedKeeperPayout);
        assertEq(musd.balanceOf(treasury) - treasuryBefore, expectedProtoFee);
        (, uint256 k1BondRemaining, , , uint256 k1Slashes, ) = grid.keepers(k1);
        assertEq(k1BondRemaining, bondAmount - expectedSlash);
        assertEq(k1Slashes, 1);
    }

    function test_BatchLiquidationJobDispatchesToTroveManager() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 600e18);
        grid.postKeeperBond(600e18);
        vm.stopPrank();

        vm.startPrank(poster);
        musd.approve(address(grid), 25e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.BATCH_LIQUIDATION,
            address(tm),
            8,
            0,
            25e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        grid.executeSignalJob(jobId, address(0), address(0));

        assertEq(tm.liquidatedBatches(), 8);
    }

    function test_HintedRedemptionJobExecutesAndForwardsBTC() public {
        vm.deal(address(tm), 10 ether);

        vm.startPrank(keeper1);
        musd.approve(address(grid), 800e18);
        grid.postKeeperBond(800e18);
        vm.stopPrank();

        uint256 posterBtcBefore = poster.balance;
        vm.startPrank(poster);
        musd.approve(address(grid), 1_540e18);
        uint256 jobId = grid.postSignalJob(
            KeeperGrid.JobType.HINTED_REDEMPTION,
            poster,
            1_500e18,
            0,
            40e18
        );
        vm.stopPrank();

        vm.prank(keeper1);
        uint256 payout = grid.executeSignalJob(jobId, address(0), address(0));

        // 1,500 MUSD redeemed at $75,000/BTC = 0.02 BTC forwarded to poster
        assertEq(poster.balance - posterBtcBefore, 0.02 ether);
        assertEq(payout, 38e18);
    }

    function test_RoundRobinAssignsDistinctKeepersAcrossJobs() public {
        vm.startPrank(keeper1);
        musd.approve(address(grid), 500e18);
        grid.postKeeperBond(500e18);
        vm.stopPrank();

        vm.startPrank(keeper2);
        musd.approve(address(grid), 500e18);
        grid.postKeeperBond(500e18);
        vm.stopPrank();

        assertEq(grid.activeKeepersCount(), 2);

        vm.startPrank(poster);
        musd.approve(address(grid), 60e18);
        uint256 j1 = grid.postSignalJob(KeeperGrid.JobType.GAUGE_EPOCH_POKE, address(bv), 1, 0, 20e18);
        uint256 j2 = grid.postSignalJob(KeeperGrid.JobType.GAUGE_EPOCH_POKE, address(bv), 2, 0, 20e18);
        uint256 j3 = grid.postSignalJob(KeeperGrid.JobType.GAUGE_EPOCH_POKE, address(bv), 3, 0, 20e18);
        vm.stopPrank();

        (, , , , , , , address assigned1, , , ) = grid.jobs(j1);
        (, , , , , , , address assigned2, , , ) = grid.jobs(j2);
        (, , , , , , , address assigned3, , , ) = grid.jobs(j3);

        assertEq(assigned1, keeper1);
        assertEq(assigned2, keeper2);
        assertEq(assigned3, keeper1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DrawdownDesk} from "../src/drawdown/DrawdownDesk.sol";

contract DrawdownMockMUSD {
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

contract DrawdownMockSMUSD {
    DrawdownMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;

    constructor(address _musd) {
        musd = DrawdownMockMUSD(_musd);
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

contract DrawdownMockPF {
    uint256 public price = 76_559e18;

    function setPrice(uint256 _p) external {
        price = _p;
    }

    function fetchPrice() external view returns (uint256) {
        return price;
    }
}

contract DrawdownMockTM {
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
        return (coll[u], debt[u], 0, 0, 0, 20e18);
    }
}

contract DrawdownMockBO {
    DrawdownMockMUSD public immutable musd;
    DrawdownMockTM public immutable tm;
    uint256 public minNetDebt = 1800e18;
    uint256 public borrowingRate = 1e15;
    uint256 public constant MUSD_GAS_COMPENSATION = 200e18;
    uint256 public jitDrawsCount;

    constructor(address _musd, address _tm) {
        musd = DrawdownMockMUSD(_musd);
        tm = DrawdownMockTM(_tm);
    }

    function openTrove(uint256 musdAmount, address, address) external payable {
        uint256 fee = (musdAmount * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, musdAmount + fee + MUSD_GAS_COMPENSATION, msg.value);
        musd.mint(msg.sender, musdAmount);
    }

    function withdrawMUSD(uint256 musdAmount, address, address) external {
        (uint256 c, uint256 d, , , , ) = tm.getEntireDebtAndColl(msg.sender);
        uint256 fee = (musdAmount * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, d + musdAmount + fee, c);
        musd.mint(msg.sender, musdAmount);
        jitDrawsCount += 1;
    }
}

contract DrawdownTest is Test {
    DrawdownMockMUSD internal musd;
    DrawdownMockSMUSD internal smusd;
    DrawdownMockPF internal pf;
    DrawdownMockTM internal tm;
    DrawdownMockBO internal bo;
    DrawdownDesk internal desk;

    address internal dev = address(0xDE01);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new DrawdownMockMUSD();
        smusd = new DrawdownMockSMUSD(address(musd));
        pf = new DrawdownMockPF();
        tm = new DrawdownMockTM();
        bo = new DrawdownMockBO(address(musd), address(tm));

        desk = new DrawdownDesk(
            address(musd),
            address(smusd),
            address(bo),
            address(tm),
            address(pf),
            treasury
        );

        vm.deal(address(this), 100 ether);
    }

    function test_InitializeCorporateTroveAndJITDrawdownAndRecoveryModeFallback() public {
        // Initialize corporate Trove with 0.25 BTC (~$19,139) and 2,000 MUSD seed parked in sMUSD
        desk.initializeCorporateTrove{value: 0.25 ether}(2_000e18, 5e16, address(0), address(0));
        assertEq(smusd.balanceOf(address(desk)), 2_000e18);

        // Create pay stream: 0.01 MUSD/sec for 30 days
        uint256 streamId = desk.createPayStream(dev, 0.01e18, 30 days, false);

        // Advance 10,000 seconds -> 100 MUSD vested
        vm.warp(block.timestamp + 10_000);
        assertEq(desk.claimablePaySlip(streamId), 100e18);

        // 1. Normal mode: claims via Just-in-Time BorrowerOperations.withdrawMUSD!
        vm.prank(dev);
        (uint256 netOut, uint256 receiptNo) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));
        assertEq(bo.jitDrawsCount(), 1, "Borrowed Just-in-Time from BorrowerOperations");
        assertEq(netOut, 99.5e18);
        assertEq(musd.balanceOf(dev), 99.5e18);
        assertEq(receiptNo, 10_001);

        // 2. Flip system into Recovery Mode (TCR < 150%) -> JIT borrowing blocked, seamlessly falls back to sMUSD buffer!
        tm.setRecoveryMode(true);
        vm.warp(block.timestamp + 10_000);

        vm.prank(dev);
        (uint256 netOut2, ) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));
        assertEq(bo.jitDrawsCount(), 1, "Did not increase Trove debt during Recovery Mode");
        assertEq(netOut2, 99.5e18);
        assertEq(smusd.balanceOf(address(desk)), 1_900e18, "Drew 100 MUSD from sMUSD buffer");
    }

    function test_RevertWhen_InvalidTroveOpeningOrUnauthorizedCaller() public {
        // 1. Below minNetDebt (1,800 MUSD) reverts
        vm.expectRevert(abi.encodeWithSelector(DrawdownDesk.BelowMinNetDebt.selector, 1_799e18, 1_800e18));
        desk.initializeCorporateTrove{value: 0.25 ether}(1_799e18, 5e16, address(0), address(0));

        // 2. Below required ICR (0.025 BTC at $76,559 = $1,913.975 collateral against ~2,001.8 MUSD debt -> ~95.6% ICR < 125%)
        vm.expectRevert();
        desk.initializeCorporateTrove{value: 0.025 ether}(1_800e18, 5e16, address(0), address(0));

        // 3. Non-admin caller reverts on initializeCorporateTrove and createPayStream
        address attacker = address(0xBAD);
        vm.deal(attacker, 1 ether);
        vm.startPrank(attacker);
        vm.expectRevert(DrawdownDesk.OnlyTreasuryAdmin.selector);
        desk.initializeCorporateTrove{value: 0.25 ether}(2_000e18, 5e16, address(0), address(0));

        vm.expectRevert(DrawdownDesk.OnlyTreasuryAdmin.selector);
        desk.createPayStream(dev, 0.01e18, 30 days, false);
        vm.stopPrank();
    }

    function test_AutoRouteToSMUSDCompoundsEmployeePaySlip() public {
        desk.initializeCorporateTrove{value: 0.25 ether}(2_000e18, 5e16, address(0), address(0));
        uint256 streamId = desk.createPayStream(dev, 0.02e18, 30 days, true);

        vm.warp(block.timestamp + 5_000); // 100 MUSD accrued
        vm.prank(dev);
        (uint256 netPayout, ) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        assertEq(netPayout, 99.5e18);
        assertEq(desk.recipientSMUSDShares(dev), 99.5e18);
        assertEq(musd.balanceOf(dev), 0);
        // Desk holds initial 2,000 sMUSD + 99.5 sMUSD compounded for employee
        assertEq(smusd.balanceOf(address(desk)), 2_099.5e18);
    }

    function test_PayStreamCapsAtStopTimeAfterFullDuration() public {
        desk.initializeCorporateTrove{value: 0.5 ether}(2_000e18, 5e16, address(0), address(0));
        uint256 duration = 30 days;
        uint256 rate = 0.0005e18;
        uint256 streamId = desk.createPayStream(dev, rate, duration, false);

        // Warp 60 days (2x duration) -> accrual must cap at 30 days
        vm.warp(block.timestamp + 60 days);
        uint256 expectedMax = duration * rate;
        assertEq(desk.claimablePaySlip(streamId), expectedMax);

        vm.prank(dev);
        desk.claimPaySlip(streamId, 5e16, address(0), address(0));
        assertEq(desk.claimablePaySlip(streamId), 0);
    }

    function test_RevertWhen_ClaimZeroOrInactiveStream() public {
        desk.initializeCorporateTrove{value: 0.25 ether}(2_000e18, 5e16, address(0), address(0));
        uint256 streamId = desk.createPayStream(dev, 0.01e18, 1_000, false);

        // Claiming at startTime (0 elapsed) reverts with NothingToClaim
        vm.expectRevert(DrawdownDesk.NothingToClaim.selector);
        desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        // Claim full stream after stopTime
        vm.warp(block.timestamp + 1_500);
        desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        // Second claim after full duration reverts with NothingToClaim
        vm.expectRevert(DrawdownDesk.NothingToClaim.selector);
        desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        // Claiming non-existent stream reverts with StreamNotActive
        vm.expectRevert(DrawdownDesk.StreamNotActive.selector);
        desk.claimPaySlip(999, 5e16, address(0), address(0));
    }

    function test_ClearingFee50BpsRoutedToFeeTreasury() public {
        desk.initializeCorporateTrove{value: 0.25 ether}(2_000e18, 5e16, address(0), address(0));
        uint256 streamId = desk.createPayStream(dev, 0.1e18, 30 days, false);

        vm.warp(block.timestamp + 2_000); // 200 MUSD gross
        uint256 feeBefore = musd.balanceOf(treasury);

        vm.prank(dev);
        (uint256 netOut, ) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        // 0.50% (50 bps) of 200 MUSD = 1.0 MUSD fee, 199.0 MUSD net
        assertEq(musd.balanceOf(treasury) - feeBefore, 1e18);
        assertEq(netOut, 199e18);
        assertEq(desk.receiptsLength(), 1);
    }

    function test_TightICRInNormalModeFallsBackToSMUSDBuffer() public {
        // Open Trove with 0.04 BTC ($3,062.36 at $76,559) and 1,800 MUSD seed -> ~152.9% initial ICR
        desk.initializeCorporateTrove{value: 0.04 ether}(1_800e18, 5e16, address(0), address(0));
        uint256 streamId = desk.createPayStream(dev, 0.05e18, 30 days, false);

        vm.warp(block.timestamp + 10_000); // 500 MUSD accrued

        // BTC price dips in Normal Mode to $65,000 -> 0.04 BTC = $2,600.
        // Borrowing 500 MUSD more would push debt to ~2,502 MUSD (ICR ~103.9% < 125% minSafeICR).
        pf.setPrice(65_000e18);

        vm.prank(dev);
        (uint256 netOut, ) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));

        assertEq(bo.jitDrawsCount(), 0, "Skipped JIT borrow to protect Trove ICR");
        assertEq(smusd.balanceOf(address(desk)), 1_300e18, "Drew 500 MUSD from sMUSD buffer");
        assertEq(netOut, 497.5e18);
    }

    function testFuzz_StreamingPayrollLinearAccrualAndExactConservation(
        uint256 ratePerSec,
        uint256 elapsedSec
    ) public {
        ratePerSec = bound(ratePerSec, 0.001e18, 1e18);
        elapsedSec = bound(elapsedSec, 100, 30 days);

        // Collateralize with 50 BTC so any fuzzed 30-day stream at up to 1 MUSD/sec (2.592M MUSD) stays well above minSafeICR
        desk.initializeCorporateTrove{value: 50 ether}(2_000e18, 5e16, address(0), address(0));
        uint256 streamId = desk.createPayStream(dev, ratePerSec, 30 days, false);

        vm.warp(block.timestamp + elapsedSec);
        uint256 claimable = desk.claimablePaySlip(streamId);
        assertEq(claimable, ratePerSec * elapsedSec);

        uint256 feeBefore = musd.balanceOf(treasury);
        vm.prank(dev);
        (uint256 netPayoutMUSD, ) = desk.claimPaySlip(streamId, 5e16, address(0), address(0));
        uint256 clearingFee = musd.balanceOf(treasury) - feeBefore;

        assertEq(netPayoutMUSD + clearingFee, claimable);
        assertEq(musd.balanceOf(dev), netPayoutMUSD);
    }
}

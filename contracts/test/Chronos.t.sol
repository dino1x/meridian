// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChronosTermVault} from "../src/chronos/ChronosTermVault.sol";
import {BatchRateAuction} from "../src/chronos/BatchRateAuction.sol";
import {ChronosPT, ChronosYT} from "../src/chronos/ChronosTokens.sol";

contract ChronosMockMUSD {
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
        require(balanceOf[msg.sender] >= amount, "bal");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "bal");
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allow");
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ChronosMockSMUSD {
    ChronosMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public simYield;

    constructor(address _musd) {
        musd = ChronosMockMUSD(_musd);
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

contract ChronosMockSP {}

contract ChronosMockPF {
    function fetchPrice() external pure returns (uint256) {
        return 76_559e18;
    }
}

contract ChronosMockTM {
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
        uint256 p = d > 15e18 ? d - 15e18 : d;
        return (coll[u], p, d > 15e18 ? 15e18 : 0, 0, 0, 15e18);
    }
}

contract ChronosMockBO {
    ChronosMockMUSD public immutable musd;
    ChronosMockTM public immutable tm;
    uint256 public minNetDebt = 1800e18;
    uint256 public borrowingRate = 1e15;

    constructor(address _musd, address _tm) {
        musd = ChronosMockMUSD(_musd);
        tm = ChronosMockTM(_tm);
    }

    function openTrove(uint256 musdAmount, address, address) external payable {
        uint256 fee = (musdAmount * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, musdAmount + fee + 200e18, msg.value);
        musd.mint(msg.sender, musdAmount);
    }

    function adjustTrove(uint256, uint256 musdChange, bool, address, address) external payable {
        (uint256 c, uint256 p, uint256 i, , , ) = tm.getEntireDebtAndColl(msg.sender);
        uint256 d = p + i;
        uint256 fee = (musdChange * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, d + musdChange + fee, c + msg.value);
        musd.mint(msg.sender, musdChange);
    }
}

contract ChronosTest is Test {
    ChronosMockMUSD internal musd;
    ChronosMockSMUSD internal smusd;
    ChronosMockSP internal sp;
    ChronosMockPF internal pf;
    ChronosMockTM internal tm;
    ChronosMockBO internal bo;
    ChronosTermVault internal vault;
    BatchRateAuction internal auction;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal charlie = address(0xC0FFEE);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new ChronosMockMUSD();
        smusd = new ChronosMockSMUSD(address(musd));
        sp = new ChronosMockSP();
        pf = new ChronosMockPF();
        tm = new ChronosMockTM();
        bo = new ChronosMockBO(address(musd), address(tm));

        vault = new ChronosTermVault(
            address(musd),
            address(smusd),
            address(sp),
            address(bo),
            address(tm),
            address(pf),
            treasury
        );
        auction = new BatchRateAuction(address(musd));
        auction.setFeeTreasury(treasury);

        musd.mint(alice, 50_000e18);
        musd.mint(bob, 50_000e18);
        musd.mint(charlie, 50_000e18);
        vm.deal(alice, 10 ether);
    }

    function test_MintPTAndYTAndClaimYieldAndRedeemAtMaturity() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        vault.mintPTAndYT(1, 10_000e18);
        vm.stopPrank();

        (, , uint256 mat, ChronosPT pt, ChronosYT yt, , , ) = vault.series(1);
        assertEq(pt.balanceOf(alice), 10_000e18);
        assertEq(yt.balanceOf(alice), 10_000e18);

        // Simulate 400 MUSD yield in sMUSD
        smusd.addYield(address(vault), 400e18);

        vm.prank(alice);
        uint256 netYield = vault.claimYield(1);
        assertEq(netYield, 380e18, "95% net yield to YT holder, 5% protocol fee");
        assertEq(musd.balanceOf(treasury), 20e18);

        // Warp to 30D maturity and redeem PT 1:1 for MUSD
        vm.warp(mat + 1);
        uint256 balBefore = musd.balanceOf(alice);
        vm.prank(alice);
        vault.redeemAtMaturity(1, 10_000e18);
        assertEq(musd.balanceOf(alice) - balBefore, 10_000e18);
    }

    function test_BatchRateAuctionUniformClearingAndYieldCurve() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 10_000e18);
        vault.mintPTAndYT(2, 10_000e18); // 90D series
        (, , uint256 mat, ChronosPT pt90, , , , ) = vault.series(2);

        uint256 auctionId = auction.openAuction(2, address(pt90), mat);
        pt90.approve(address(auction), 10_000e18);
        auction.placeSellOrder(auctionId, 10_000e18, 0.98e18); // min price 0.98 MUSD
        vm.stopPrank();

        vm.startPrank(bob);
        musd.approve(address(auction), 9_850e18);
        auction.placeBuyBid(auctionId, 9_850e18, 0.99e18); // max price 0.99 MUSD
        vm.stopPrank();

        // Settle at uniform clearing price 0.985 MUSD per PT (~6.17% annualized fixed rate on 90D)
        uint256 cleared = auction.settleAuction(auctionId, 0.985e18);
        assertEq(cleared, 10_000e18);
        assertEq(pt90.balanceOf(bob), 10_000e18);
        (, uint256 rate90d, ) = auction.getYieldCurveBps();
        assertGt(rate90d, 600); // > 6.00% APR
    }

    function test_ZapTroveToFixedTermRecoveryModeEnforcement() public {
        // Normal mode succeeds at ~139% ICR
        vm.prank(alice);
        vault.zapTroveToFixedTerm{value: 0.04 ether}(1, 2_000e18, 5e16, address(0), address(0));

        // Switch to Recovery Mode (TCR < 150% -> requires CCR = 150%)
        tm.setRecoveryMode(true);
        vm.prank(alice);
        vm.expectRevert();
        vault.zapTroveToFixedTerm{value: 0}(1, 1_000e18, 5e16, address(0), address(0));
    }

    function test_EarlyExitCombinePTAndYTBeforeMaturity() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 8_000e18);
        vault.mintPTAndYT(1, 8_000e18);
        vm.stopPrank();

        (, , , ChronosPT pt, ChronosYT yt, , , ) = vault.series(1);
        assertEq(pt.balanceOf(alice), 8_000e18);
        assertEq(yt.balanceOf(alice), 8_000e18);

        // Accrue 200 MUSD yield before maturity
        smusd.addYield(address(vault), 200e18);

        uint256 musdBefore = musd.balanceOf(alice);
        vm.startPrank(alice);
        vault.combineAndRedeemEarly(1, 8_000e18);
        uint256 netYield = vault.claimYTYield(1);
        vm.stopPrank();

        assertEq(pt.balanceOf(alice), 0);
        assertEq(yt.balanceOf(alice), 0);
        assertEq(netYield, 190e18);
        assertEq(musd.balanceOf(alice) - musdBefore, 8_190e18);
    }

    function test_RevertWhen_RedeemPTBeforeMaturityTimestamp() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 5_000e18);
        vault.mintPTAndYT(1, 5_000e18);

        (, , uint256 mat, , , , , ) = vault.series(1);
        vm.expectRevert(
            abi.encodeWithSelector(ChronosTermVault.SeriesNotYetMatured.selector, block.timestamp, mat)
        );
        vault.redeemPTAtMaturity(1, 5_000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_ZapTroveBelowMinNetDebt() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ChronosTermVault.BelowMinNetDebt.selector, 1_500e18, 1_800e18)
        );
        vault.zapTroveToFixedTerm{value: 0.05 ether}(1, 1_500e18, 5e16, address(0), address(0));
    }

    function test_AllThreeMaturityTenors30D90D180DInitialized() public view {
        (uint256 id30, uint256 dur30, uint256 mat30, ChronosPT pt30, ChronosYT yt30, , , bool active30) =
            vault.series(1);
        (uint256 id90, uint256 dur90, uint256 mat90, ChronosPT pt90, ChronosYT yt90, , , bool active90) =
            vault.series(2);
        (uint256 id180, uint256 dur180, uint256 mat180, ChronosPT pt180, ChronosYT yt180, , , bool active180) =
            vault.series(3);

        assertEq(id30, 1);
        assertEq(id90, 2);
        assertEq(id180, 3);
        assertEq(dur30, 30 days);
        assertEq(dur90, 90 days);
        assertEq(dur180, 180 days);
        assertTrue(active30 && active90 && active180);
        assertTrue(mat30 < mat90 && mat90 < mat180);
        assertTrue(address(pt30) != address(pt90) && address(pt90) != address(pt180));
        assertTrue(address(yt30) != address(yt90) && address(yt90) != address(yt180));
    }

    function test_BatchAuctionOutOfMoneyBidsRefundedCleanly() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 5_000e18);
        vault.mintPTAndYT(1, 5_000e18);
        (, , uint256 mat, ChronosPT pt30, , , , ) = vault.series(1);

        uint256 auctionId = auction.openAuction(1, address(pt30), mat);
        pt30.approve(address(auction), 5_000e18);
        auction.placeSellOrder(auctionId, 5_000e18, 0.985e18);
        vm.stopPrank();

        // Bob places an in-the-money bid at maxPrice 0.990 MUSD
        vm.startPrank(bob);
        musd.approve(address(auction), 4_925e18);
        auction.placeBuyBid(auctionId, 4_925e18, 0.990e18);
        vm.stopPrank();

        // Charlie places an out-of-the-money bid demanding a deeper discount (maxPrice 0.970 MUSD < clearing 0.985 MUSD)
        uint256 charlieBalBefore = musd.balanceOf(charlie);
        vm.startPrank(charlie);
        musd.approve(address(auction), 3_000e18);
        auction.placeBuyBid(auctionId, 3_000e18, 0.970e18);
        vm.stopPrank();

        uint256 cleared = auction.settleAuction(auctionId, 0.985e18);
        assertEq(cleared, 5_000e18);
        assertEq(pt30.balanceOf(bob), 5_000e18);
        assertEq(pt30.balanceOf(charlie), 0);
        assertEq(musd.balanceOf(charlie), charlieBalBefore, "Out-of-the-money bid refunded in full");
    }

    function test_FeeTreasuryReceives5PctYieldPerformanceFee() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.mintPTAndYT(2, 20_000e18);
        vm.stopPrank();

        // Simulate 1,000 MUSD yield in sMUSD
        smusd.addYield(address(vault), 1_000e18);

        uint256 treasuryBefore = musd.balanceOf(treasury);
        vm.prank(alice);
        uint256 netClaimed = vault.claimYTYield(2);

        assertEq(netClaimed, 950e18);
        assertEq(musd.balanceOf(treasury) - treasuryBefore, 50e18);
    }

    function testFuzz_MintAndRedeemPTConserves1To1Principal(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 100e18, 500_000e18);
        uint256 simulatedYield = depositAmount / 20; // 5% yield over tenor

        address user = address(0x123456);
        musd.mint(user, depositAmount);

        vm.startPrank(user);
        musd.approve(address(vault), depositAmount);
        vault.mintPTAndYT(3, depositAmount);
        vm.stopPrank();

        (, , uint256 mat, ChronosPT pt, ChronosYT yt, , , ) = vault.series(3);
        assertEq(pt.balanceOf(user), depositAmount);
        assertEq(yt.balanceOf(user), depositAmount);

        smusd.addYield(address(vault), simulatedYield);

        vm.warp(mat + 1);

        uint256 balBeforeRedeem = musd.balanceOf(user);
        vm.prank(user);
        vault.redeemPTAtMaturity(3, depositAmount);
        uint256 principalRedeemed = musd.balanceOf(user) - balBeforeRedeem;

        // 1 PT strictly redeems for 1 MUSD of principal (exact 1:1 conservation)
        assertEq(principalRedeemed, depositAmount);
        assertEq(pt.balanceOf(user), 0);

        vm.prank(user);
        uint256 netYield = vault.claimYTYield(3);

        uint256 expectedFee = (simulatedYield * vault.PROTOCOL_YIELD_FEE_BPS()) / vault.BPS_DENOMINATOR();
        assertApproxEqAbs(netYield, simulatedYield - expectedFee, 1e9);
        assertEq(musd.balanceOf(user), depositAmount + netYield);
    }

    function test_RevertWhen_MintZeroMUSDOrInvalidSeries() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 1_000e18);

        vm.expectRevert(ChronosTermVault.ZeroAmount.selector);
        vault.mintPTAndYT(1, 0);

        vm.expectRevert(ChronosTermVault.SeriesNotActive.selector);
        vault.mintPTAndYT(99, 1_000e18);
        vm.stopPrank();
    }

    function test_BatchAuctionSettlementFee5BpsRoutedToTreasury() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.mintPTAndYT(1, 20_000e18);
        (, , uint256 mat, ChronosPT pt30, , , , ) = vault.series(1);

        uint256 auctionId = auction.openAuction(1, address(pt30), mat);
        pt30.approve(address(auction), 20_000e18);
        auction.placeSellOrder(auctionId, 20_000e18, 0.99e18);
        vm.stopPrank();

        vm.startPrank(bob);
        musd.approve(address(auction), 19_800e18);
        auction.placeBuyBid(auctionId, 19_800e18, 0.99e18);
        vm.stopPrank();

        uint256 treasuryBefore = musd.balanceOf(treasury);
        uint256 aliceMusdBefore = musd.balanceOf(alice);

        uint256 cleared = auction.settleAuction(auctionId, 0.99e18);
        assertEq(cleared, 20_000e18);

        // Gross proceeds = 19,800 MUSD; 5 bps (0.05%) settlement fee = 9.90 MUSD
        uint256 expectedFee = (19_800e18 * 5) / 10_000;
        assertEq(musd.balanceOf(treasury) - treasuryBefore, expectedFee);
        assertEq(musd.balanceOf(alice) - aliceMusdBefore, 19_800e18 - expectedFee);
    }
}

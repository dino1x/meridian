// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChickenBondManager} from "../src/roost/ChickenBondManager.sol";
import {BondNFT, IChickenBondManagerView} from "../src/roost/BondNFT.sol";
import {bMUSDToken} from "../src/roost/bMUSDToken.sol";

contract RoostMockMUSD {
    string public constant name = "Mezo USD";
    string public constant symbol = "MUSD";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "bal");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "bal");
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "allow");
            allowance[from][msg.sender] = allowed - value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

contract RoostMockSMUSD {
    RoostMockMUSD public immutable musd;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public simulatedYield;
    uint256 public totalSupply;
    uint256 public yieldIndex = 1e18;

    constructor(address _musd) {
        musd = RoostMockMUSD(_musd);
    }

    function deposit(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        totalSupply += amount;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "sMUSD bal");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        musd.transfer(msg.sender, amount);
    }

    function addSimulatedYield(address account, uint256 yieldAmount) external {
        musd.mint(address(this), yieldAmount);
        simulatedYield[account] += yieldAmount;
        yieldIndex += 0.05e18;
    }

    function claimableYield(address account) external view returns (uint256) {
        return simulatedYield[account];
    }

    function claimYield() external returns (uint256 amount) {
        amount = simulatedYield[msg.sender];
        simulatedYield[msg.sender] = 0;
        if (amount > 0) {
            musd.transfer(msg.sender, amount);
        }
    }
}

contract RoostMockStabilityPool {
    RoostMockMUSD public immutable musd;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public collateralGains;
    uint256 public totalDeposits;

    constructor(address _musd) {
        musd = RoostMockMUSD(_musd);
    }

    function provideToSP(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposits += amount;
    }

    function withdrawFromSP(uint256 amount) external {
        if (amount > 0) {
            require(deposits[msg.sender] >= amount, "sp bal");
            deposits[msg.sender] -= amount;
            totalDeposits -= amount;
            musd.transfer(msg.sender, amount);
        }
        uint256 gain = collateralGains[msg.sender];
        if (gain > 0) {
            collateralGains[msg.sender] = 0;
            (bool ok, ) = msg.sender.call{value: gain}("");
            require(ok, "btc send");
        }
    }

    function getDepositorCollateralGain(address depositor) external view returns (uint256) {
        return collateralGains[depositor];
    }

    function getCompoundedMUSDDeposit(address depositor) external view returns (uint256) {
        return deposits[depositor];
    }

    function getTotalMUSDDeposits() external view returns (uint256) {
        return totalDeposits;
    }
}

contract RoostMockPriceFeed {
    uint256 public price = 76_559e18;

    function setPrice(uint256 _p) external {
        price = _p;
    }

    function fetchPrice() external view returns (uint256) {
        return price;
    }

    function lastGoodPrice() external view returns (uint256) {
        return price;
    }
}

contract RoostMockTroveManager {
    uint256 public constant MCR = 1.1e18;
    uint256 public constant CCR = 1.5e18;
    bool public recoveryMode;

    struct TroveInfo {
        uint256 debt; // ALREADY includes pendingInterest
        uint256 coll;
        uint256 pendingInterest;
    }

    mapping(address => TroveInfo) public troves;

    function setRecoveryMode(bool _rm) external {
        recoveryMode = _rm;
    }

    function setTrove(address borrower, uint256 debtIncludingInterest, uint256 coll, uint256 pendingInterest) external {
        troves[borrower] = TroveInfo(debtIncludingInterest, coll, pendingInterest);
    }

    function checkRecoveryMode(uint256) external view returns (bool) {
        return recoveryMode;
    }

    function getEntireDebtAndColl(address borrower)
        external
        view
        returns (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingCollateral,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        )
    {
        TroveInfo memory t = troves[borrower];
        uint256 p = t.debt > t.pendingInterest ? t.debt - t.pendingInterest : t.debt;
        return (t.coll, p, t.pendingInterest, 0, 0, t.pendingInterest);
    }
}

contract RoostMockBorrowerOperations {
    RoostMockMUSD public immutable musd;
    RoostMockTroveManager public immutable tm;
    uint256 public minNetDebt = 1800e18;
    uint256 public borrowingRate = 1e15; // 0.1%
    uint256 public constant MUSD_GAS_COMPENSATION = 200e18;
    mapping(address => uint256) public maxBorrowingCapacity;

    constructor(address _musd, address _tm) {
        musd = RoostMockMUSD(_musd);
        tm = RoostMockTroveManager(_tm);
    }

    function openTrove(uint256 musdAmount, address, address) external payable {
        uint256 fee = (musdAmount * borrowingRate) / 1e18;
        tm.setTrove(msg.sender, musdAmount + fee + MUSD_GAS_COMPENSATION, msg.value, 0);
        musd.mint(msg.sender, musdAmount);
    }

    function adjustTrove(uint256, uint256 musdChange, bool isDebtIncrease, address, address) external payable {
        (uint256 coll, uint256 principal, uint256 interest, , , uint256 pendingInt) = tm.getEntireDebtAndColl(msg.sender);
        uint256 debt = principal + interest;
        if (isDebtIncrease) {
            uint256 fee = (musdChange * borrowingRate) / 1e18;
            tm.setTrove(msg.sender, debt + musdChange + fee, coll + msg.value, pendingInt);
            musd.mint(msg.sender, musdChange);
        }
    }
}

contract RoostTest is Test {
    RoostMockMUSD internal musd;
    RoostMockSMUSD internal smusd;
    RoostMockStabilityPool internal sp;
    RoostMockPriceFeed internal pf;
    RoostMockTroveManager internal tm;
    RoostMockBorrowerOperations internal bo;
    ChickenBondManager internal manager;
    bMUSDToken internal bMusd;
    BondNFT internal bondNft;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new RoostMockMUSD();
        smusd = new RoostMockSMUSD(address(musd));
        sp = new RoostMockStabilityPool(address(musd));
        pf = new RoostMockPriceFeed();
        tm = new RoostMockTroveManager();
        bo = new RoostMockBorrowerOperations(address(musd), address(tm));

        manager = new ChickenBondManager(
            address(musd),
            address(smusd),
            address(sp),
            address(bo),
            address(tm),
            address(pf),
            treasury,
            15 days
        );
        bMusd = manager.bMusd();
        bondNft = manager.bondNft();

        musd.mint(alice, 50_000e18);
        musd.mint(bob, 50_000e18);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_CreateBondAndAccrueHyperbolic() public {
        vm.startPrank(alice);
        musd.approve(address(manager), 10_000e18);
        uint256 bondId = manager.createBond(10_000e18);
        vm.stopPrank();

        assertEq(bondNft.ownerOf(bondId), alice);
        assertEq(manager.pendingBucketMUSD(), 10_000e18);

        // After 15 days (t == alpha), accrued bMUSD should be exactly 50% of cap (5,000 bMUSD)
        vm.warp(block.timestamp + 15 days);
        uint256 accrued = manager.calcAccruedBMUSD(bondId);
        assertEq(accrued, 5_000e18);

        // Verify on-chain SVG tokenURI renders valid data URI
        string memory uri = bondNft.tokenURI(bondId);
        assertTrue(bytes(uri).length > 200);
    }

    function test_ChickenOutPrincipalProtectedAndLeavesYieldInReserve() public {
        vm.startPrank(alice);
        musd.approve(address(manager), 5_000e18);
        uint256 bondId = manager.createBond(5_000e18);
        vm.stopPrank();

        // Simulate 250 MUSD yield earned in sMUSD while Alice's bond incubates
        smusd.addSimulatedYield(address(manager), 250e18);
        vm.warp(block.timestamp + 10 days);

        uint256 aliceBalBefore = musd.balanceOf(alice);
        vm.prank(alice);
        manager.chickenOut(bondId);

        assertEq(musd.balanceOf(alice) - aliceBalBefore, 5_000e18, "100% principal returned");
        assertEq(manager.pendingBucketMUSD(), 0);
        assertEq(manager.reserveBucketMUSD(), 250e18, "Foregone sMUSD yield stays in Reserve Bucket");
    }

    function test_ChickenInAndRedeemBMUSDAppreciation() public {
        vm.startPrank(alice);
        musd.approve(address(manager), 10_000e18);
        uint256 bondId = manager.createBond(10_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);
        smusd.addSimulatedYield(address(manager), 500e18);

        vm.prank(alice);
        uint256 minted = manager.chickenIn(bondId);
        assertEq(minted, 5_000e18);
        assertEq(bMusd.balanceOf(alice), 5_000e18);
        assertEq(musd.balanceOf(treasury), 100e18, "1% protocol fee sent to treasury");
        assertGt(manager.permanentBucketMUSD(), 0, "Permanent bucket funded in StabilityPool");
        assertGt(manager.getBMUSDBackingPrice(), 1e18, "bMUSD backing price rose above 1.00 MUSD");

        // Redeem half of bMUSD for appreciated MUSD
        uint256 balBefore = musd.balanceOf(alice);
        vm.prank(alice);
        (uint256 musdOut, ) = manager.redeemBMUSD(2_500e18);
        assertGt(musdOut, 2_500e18);
        assertEq(musd.balanceOf(alice) - balBefore, musdOut);
    }

    function test_TroveToBondZapNormalAndRecoveryModeAndPendingInterest() public {
        // 1. Normal mode: 130% ICR succeeds (MCR = 110%)
        // Borrow 2,000 MUSD (+2 MUSD fee + 200 gas comp = 2,202 MUSD debt).
        // At BTC = $76,559, 0.04 BTC = $3,062.36 (~139% ICR)
        vm.prank(alice);
        uint256 bondId = manager.createBondFromTrove{value: 0.04 ether}(5e16, 2_000e18, address(0), address(0));
        assertEq(bondId, 1);
        assertEq(manager.pendingBucketMUSD(), 2_000e18);

        // 2. Simulate pendingInterest on the existing Trove; verify getEntireDebtAndColl is NOT double-counted
        // Set debt = 2,250 MUSD (which already includes 48 MUSD of pendingInterest)
        tm.setTrove(address(manager), 2_250e18, 0.04 ether, 48e18);

        // 3. Activate Recovery Mode (TCR < 150% -> requires CCR = 150% instead of MCR = 110%)
        tm.setRecoveryMode(true);

        // Trying to borrow 1,000 more MUSD with 0 extra BTC would drop ICR below 150% -> must revert!
        vm.prank(bob);
        vm.expectRevert();
        manager.createBondFromTrove{value: 0}(5e16, 1_000e18, address(0), address(0));

        // Adding sufficient BTC (0.04 BTC -> total 0.08 BTC = $6,124.72 vs ~3,251 MUSD debt = 188% ICR >= 150% CCR) succeeds!
        vm.prank(bob);
        uint256 bondId2 = manager.createBondFromTrove{value: 0.04 ether}(5e16, 1_000e18, address(0), address(0));
        assertEq(bondId2, 2);
    }

    function test_RevertWhen_CreateBondZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(ChickenBondManager.ZeroAmount.selector);
        manager.createBond(0);

        vm.expectRevert(ChickenBondManager.ZeroAmount.selector);
        manager.createBondFromTrove{value: 0.1 ether}(5e16, 0, address(0), address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_ChickenInOrOutByNonOwnerOrTwice() public {
        vm.startPrank(alice);
        musd.approve(address(manager), 10_000e18);
        uint256 bondId1 = manager.createBond(5_000e18);
        uint256 bondId2 = manager.createBond(5_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 10 days);

        // Non-owner Bob cannot chickenIn or chickenOut Alice's bonds
        vm.startPrank(bob);
        vm.expectRevert(ChickenBondManager.NotBondOwner.selector);
        manager.chickenIn(bondId1);

        vm.expectRevert(ChickenBondManager.NotBondOwner.selector);
        manager.chickenOut(bondId2);
        vm.stopPrank();

        // Alice settles bondId1 via chickenIn and bondId2 via chickenOut
        vm.startPrank(alice);
        manager.chickenIn(bondId1);
        manager.chickenOut(bondId2);

        // Settling an already-settled bond a second time reverts with BondNotActive
        vm.expectRevert(ChickenBondManager.BondNotActive.selector);
        manager.chickenIn(bondId1);

        vm.expectRevert(ChickenBondManager.BondNotActive.selector);
        manager.chickenOut(bondId1);

        vm.expectRevert(ChickenBondManager.BondNotActive.selector);
        manager.chickenOut(bondId2);

        vm.expectRevert(ChickenBondManager.BondNotActive.selector);
        manager.chickenIn(bondId2);
        vm.stopPrank();
    }

    function test_CreateBondFromTroveEnforcesMinNetDebtAndNormalMCR() public {
        // 1. Reverts below 1,800 MUSD minNetDebt when opening a new Trove
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ChickenBondManager.BelowMinNetDebt.selector, 1_500e18, 1_800e18)
        );
        manager.createBondFromTrove{value: 0.1 ether}(5e16, 1_500e18, address(0), address(0));

        // 2. Reverts below 110% MCR in Normal Mode
        // Borrow 2,000 MUSD -> total debt = 2,202 MUSD. 0.025 BTC @ $76,559 = $1,913.975 (~86.9% ICR < 110% MCR)
        vm.prank(alice);
        vm.expectRevert();
        manager.createBondFromTrove{value: 0.025 ether}(5e16, 2_000e18, address(0), address(0));

        // 3. Succeeds at healthy ICR (0.04 BTC @ $76,559 = $3,062.36 vs 2,202 MUSD debt = ~139% ICR >= 110% MCR)
        vm.prank(alice);
        uint256 bondId = manager.createBondFromTrove{value: 0.04 ether}(5e16, 2_000e18, address(0), address(0));
        assertEq(bondId, 1);
        assertEq(bondNft.ownerOf(bondId), alice);
    }

    function test_RedeemBMUSDProRataAndRevertWhenZeroSupplyOrAmount() public {
        // Reverts when bMUSD amount is zero
        vm.prank(alice);
        vm.expectRevert(ChickenBondManager.ZeroAmount.selector);
        manager.redeemBMUSD(0);

        // Reverts when total bMUSD supply is zero
        vm.prank(alice);
        vm.expectRevert(ChickenBondManager.ZeroAmount.selector);
        manager.redeemBMUSD(100e18);

        // Create and Chicken-In two bonds (Alice & Bob)
        vm.startPrank(alice);
        musd.approve(address(manager), 10_000e18);
        uint256 aliceBond = manager.createBond(10_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        musd.approve(address(manager), 10_000e18);
        uint256 bobBond = manager.createBond(10_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);
        smusd.addSimulatedYield(address(manager), 600e18);

        vm.prank(alice);
        uint256 aliceBMUSD = manager.chickenIn(aliceBond);

        vm.prank(bob);
        uint256 bobBMUSD = manager.chickenIn(bobBond);

        // Partial redemption by Alice (50%)
        uint256 aliceHalf = aliceBMUSD / 2;
        uint256 aliceBalBefore = musd.balanceOf(alice);
        vm.prank(alice);
        (uint256 partialOut, ) = manager.redeemBMUSD(aliceHalf);
        assertGt(partialOut, aliceHalf);
        assertEq(musd.balanceOf(alice) - aliceBalBefore, partialOut);

        // Full remaining redemption by Alice and Bob
        vm.prank(alice);
        (uint256 aliceRestOut, ) = manager.redeemBMUSD(aliceBMUSD - aliceHalf);
        assertGt(aliceRestOut, 0);

        vm.prank(bob);
        (uint256 bobFullOut, ) = manager.redeemBMUSD(bobBMUSD);
        assertGt(bobFullOut, bobBMUSD);
        assertEq(bMusd.totalSupply(), 0);
        assertEq(manager.reserveBucketMUSD(), 0);
    }

    function test_SetFeeTreasuryAccessControlAndZeroAddressRevert() public {
        // Non-owner cannot update feeTreasury
        vm.prank(alice);
        vm.expectRevert(ChickenBondManager.Unauthorized.selector);
        manager.setFeeTreasury(address(0xCAFE));

        // Owner cannot set feeTreasury to address(0)
        vm.expectRevert("Zero address");
        manager.setFeeTreasury(address(0));

        // Owner can update feeTreasury to valid non-zero address
        address newTreasury = address(0xCAFE);
        manager.setFeeTreasury(newTreasury);
        assertEq(manager.feeTreasury(), newTreasury);
    }

    function testFuzz_HyperbolicAccrualMonotonicAndBoundedByCap(uint256 principal, uint256 elapsed) public {
        principal = bound(principal, 100e18, 1_000_000e18);
        elapsed = bound(elapsed, 1, 365 days);

        musd.mint(alice, principal);
        vm.startPrank(alice);
        musd.approve(address(manager), principal);
        uint256 bondId = manager.createBond(principal);
        vm.stopPrank();

        uint256 startTs = block.timestamp;
        vm.warp(startTs + elapsed);
        uint256 accruedT1 = manager.calcAccruedBMUSD(bondId);

        vm.warp(startTs + elapsed + 1 days);
        uint256 accruedT2 = manager.calcAccruedBMUSD(bondId);

        uint256 cap = (principal * 1e18) / manager.redemptionPrice();
        assertGt(accruedT1, 0, "Positive accrual for t >= 1");
        assertGt(accruedT2, accruedT1, "Strictly monotonic with time");
        assertLt(accruedT2, cap, "Strictly bounded below asymptotic cap");
    }
}

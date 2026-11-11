// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BackstopVault} from "../src/backstop/BackstopVault.sol";

contract BackstopMockMUSD {
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

contract BackstopMockSP {
    BackstopMockMUSD public immutable musd;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public gains;

    constructor(address _musd) {
        musd = BackstopMockMUSD(_musd);
    }

    function provideToSP(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
    }

    function withdrawFromSP(uint256 amount) external {
        if (amount > 0) {
            deposits[msg.sender] -= amount;
            musd.transfer(msg.sender, amount);
        }
        uint256 g = gains[msg.sender];
        if (g > 0) {
            gains[msg.sender] = 0;
            (bool ok, ) = msg.sender.call{value: g}("");
            require(ok, "btc send");
        }
    }

    function simulateLiquidation(address depositor, uint256 musdAbsorbed, uint256 btcGained) external {
        deposits[depositor] -= musdAbsorbed;
        gains[depositor] += btcGained;
    }

    function getDepositorCollateralGain(address acc) external view returns (uint256) {
        return gains[acc];
    }

    function getCompoundedMUSDDeposit(address acc) external view returns (uint256) {
        return deposits[acc];
    }

    function getTotalMUSDDeposits() external pure returns (uint256) {
        return 86_211_210e18;
    }
}

contract BackstopMockSMUSD {}

contract BackstopMockPF {
    function fetchPrice() external pure returns (uint256) {
        return 80_000e18;
    }
}

contract BackstopMockTM {}

contract BackstopTest is Test {
    BackstopMockMUSD internal musd;
    BackstopMockSP internal sp;
    BackstopMockSMUSD internal smusd;
    BackstopMockPF internal pf;
    BackstopMockTM internal tm;
    BackstopVault internal vault;

    address internal alice = address(0xA11CE);
    address internal depositor = address(0xD3F1);
    address internal depositor2 = address(0xD3F2);
    address internal bidder = address(0xB1DD);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new BackstopMockMUSD();
        sp = new BackstopMockSP(address(musd));
        smusd = new BackstopMockSMUSD();
        pf = new BackstopMockPF();
        tm = new BackstopMockTM();

        vm.deal(address(sp), 1000 ether);

        vault = new BackstopVault(
            address(musd),
            address(sp),
            address(smusd),
            address(pf),
            address(tm),
            treasury
        );

        musd.mint(alice, 50_000e18);
        musd.mint(depositor, 100_000e18);
        musd.mint(depositor2, 100_000e18);
        musd.mint(bidder, 1_000_000e18);
    }

    function test_DepositCatalogueLiquidationLotAndDutchAuctionGavelStrike() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        uint256 shares = vault.deposit(20_000e18);
        vm.stopPrank();

        // Simulate SP absorbing 7,200 MUSD of debt and gaining 0.1 BTC ($8,000 worth at $80k/BTC -> 10% liquidation bonus)
        sp.simulateLiquidation(address(vault), 7_200e18, 0.1 ether);

        uint256 lotId = vault.catalogueLiquidationLot();
        assertEq(lotId, 1);

        // Advance 1 hour (50% of 2-hour Dutch auction -> 4% discount off $8,000 = $7,680 MUSD)
        vm.warp(block.timestamp + 1 hours);
        (uint256 costMUSD, ) = vault.getCurrentLotCostMUSD(lotId);
        assertEq(costMUSD, 7_680e18);

        uint256 bidderBtcBefore = bidder.balance;
        vm.startPrank(bidder);
        musd.approve(address(vault), costMUSD);
        vault.strikeGavel(lotId);
        vm.stopPrank();

        assertEq(bidder.balance - bidderBtcBefore, 0.1 ether, "Bidder received 0.1 BTC lot");
        // Vault started with 20,000 MUSD, lost 7,200 in liquidation, gained 7,680 - 153.60 (2% fee) = 7,526.40 MUSD -> net 20,326.40 MUSD!
        assertGt(vault.totalAssets(), 20_000e18, "Vault share value appreciated from liquidation premium");

        vm.prank(alice);
        uint256 aliceOut = vault.withdraw(shares);
        assertEq(aliceOut, 20_326.4e18);
    }

    function test_RevertWhen_ZeroAmountOrZeroCollateralGain() public {
        vm.startPrank(alice);
        vm.expectRevert(BackstopVault.ZeroAmount.selector);
        vault.deposit(0);

        vm.expectRevert(BackstopVault.ZeroAmount.selector);
        vault.redeem(0);

        musd.approve(address(vault), 10_000e18);
        vault.deposit(10_000e18);
        vm.stopPrank();

        vm.expectRevert(BackstopVault.NoCollateralGainAvailable.selector);
        vault.catalogueLiquidationLot();
    }

    function test_DutchAuctionPriceDecayAtStartMidpointAndFloor() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.deposit(20_000e18);
        vm.stopPrank();

        // 0.25 BTC at $80,000/BTC = $20,000 MUSD oracle value
        sp.simulateLiquidation(address(vault), 18_000e18, 0.25 ether);
        uint256 t0 = vm.getBlockTimestamp();
        uint256 lotId = vault.catalogueLiquidationLot();

        // At t = 0: 100% of $20,000 = 20,000 MUSD
        assertEq(vault.currentLotAskMUSD(lotId), 20_000e18);

        // At t = 1 hour (midpoint): 96% of $20,000 = 19,200 MUSD
        vm.warp(t0 + 1 hours);
        assertEq(vault.currentLotAskMUSD(lotId), 19_200e18);

        // At t = 2 hours: clamps to 92% floor = 18,400 MUSD
        vm.warp(t0 + 2 hours);
        assertEq(vault.currentLotAskMUSD(lotId), 18_400e18);

        // At t = 5 hours: remains clamped at 92% floor = 18,400 MUSD
        vm.warp(t0 + 5 hours);
        assertEq(vault.currentLotAskMUSD(lotId), 18_400e18);
    }

    function test_RevertWhen_BidOnSettledOrInvalidLot() public {
        // Bidding on non-existent lot ID 999 reverts with LotNotActive
        vm.startPrank(bidder);
        vm.expectRevert(BackstopVault.LotNotActive.selector);
        vault.bidOnLot(999, 100_000e18);
        vm.stopPrank();

        // Create and settle lot #1, then attempt to bid a second time
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.deposit(20_000e18);
        vm.stopPrank();

        sp.simulateLiquidation(address(vault), 7_200e18, 0.1 ether);
        uint256 lotId = vault.catalogueLiquidationLot();

        vm.startPrank(bidder);
        musd.approve(address(vault), 50_000e18);
        vault.bidOnLot(lotId, 50_000e18);

        vm.expectRevert(BackstopVault.LotNotActive.selector);
        vault.bidOnLot(lotId, 50_000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_BidExceedsMaxMUSDWillingToPay() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.deposit(20_000e18);
        vm.stopPrank();

        // 0.1 BTC at $80,000/BTC -> ask = 8,000 MUSD + 0.50% premium (40 MUSD) = 8,040 MUSD totalPayable
        sp.simulateLiquidation(address(vault), 7_200e18, 0.1 ether);
        uint256 lotId = vault.catalogueLiquidationLot();

        vm.startPrank(bidder);
        musd.approve(address(vault), 10_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                BackstopVault.SlippageExceeded.selector,
                8_040e18,
                8_000e18
            )
        );
        vault.bidOnLot(lotId, 8_000e18);
        vm.stopPrank();
    }

    function test_BuyerPremiumRoutedToFeeTreasuryAndPrincipalReplenishesSP() public {
        vm.startPrank(alice);
        musd.approve(address(vault), 20_000e18);
        vault.deposit(20_000e18);
        vm.stopPrank();

        // 0.1 BTC at $80k = $8,000 oracle value; after 1h -> ask = 7,680 MUSD
        sp.simulateLiquidation(address(vault), 7_200e18, 0.1 ether);
        uint256 lotId = vault.catalogueLiquidationLot();

        vm.warp(block.timestamp + 1 hours);
        uint256 askMUSD = vault.currentLotAskMUSD(lotId);
        assertEq(askMUSD, 7_680e18);

        // 0.50% buyer's premium on 7,680 MUSD = 38.40 MUSD; totalPayable = 7,718.40 MUSD
        uint256 expectedPremium = 38.4e18;
        uint256 spBefore = sp.getCompoundedMUSDDeposit(address(vault));

        vm.startPrank(bidder);
        musd.approve(address(vault), askMUSD + expectedPremium);
        (, uint256 totalPaid) = vault.bidOnLot(lotId, askMUSD + expectedPremium);
        vm.stopPrank();

        assertEq(totalPaid, 7_718.4e18);
        assertEq(musd.balanceOf(treasury), expectedPremium, "0.50% buyer premium routed to feeTreasury");
        assertEq(
            sp.getCompoundedMUSDDeposit(address(vault)) - spBefore,
            askMUSD,
            "100% of lot ask MUSD re-deposited into StabilityPool"
        );
    }

    function test_MultiDepositorProRataShareAppreciationAfterAuction() public {
        // depositor puts 10,000 MUSD (1/3), depositor2 puts 20,000 MUSD (2/3)
        vm.startPrank(depositor);
        musd.approve(address(vault), 10_000e18);
        uint256 shares1 = vault.deposit(10_000e18);
        vm.stopPrank();

        vm.startPrank(depositor2);
        musd.approve(address(vault), 20_000e18);
        uint256 shares2 = vault.deposit(20_000e18);
        vm.stopPrank();

        // SP absorbs 7,200 MUSD and receives 0.1 BTC ($8,000 at $80k/BTC)
        sp.simulateLiquidation(address(vault), 7_200e18, 0.1 ether);
        uint256 lotId = vault.catalogueLiquidationLot();

        // At t = 1 hour, lot clears at 7,680 MUSD (+480 MUSD net gain over 7,200 MUSD burned)
        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(bidder);
        musd.approve(address(vault), 10_000e18);
        vault.bidOnLot(lotId, 10_000e18);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 30_480e18);

        vm.prank(depositor);
        uint256 out1 = vault.redeem(shares1);
        vm.prank(depositor2);
        uint256 out2 = vault.redeem(shares2);

        // depositor gets 10,000 + 160 = 10,160 MUSD; depositor2 gets 20,000 + 320 = 20,320 MUSD
        assertEq(out1, 10_160e18);
        assertEq(out2, 20_320e18);
    }

    function test_RedeemVaultSharesWithdrawsFromStabilityPool() public {
        vm.startPrank(depositor);
        musd.approve(address(vault), 15_000e18);
        uint256 shares = vault.deposit(15_000e18);

        assertEq(vault.balanceOf(depositor), 15_000e18);
        assertEq(sp.getCompoundedMUSDDeposit(address(vault)), 15_000e18);

        uint256 musdBefore = musd.balanceOf(depositor);
        uint256 musdRedeemed = vault.redeem(shares);
        vm.stopPrank();

        assertEq(musdRedeemed, 15_000e18);
        assertEq(musd.balanceOf(depositor) - musdBefore, 15_000e18);
        assertEq(vault.balanceOf(depositor), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(sp.getCompoundedMUSDDeposit(address(vault)), 0);
    }

    function testFuzz_DutchAuctionLotClearingAlwaysReplenishesStabilityPool(
        uint256 elapsedSeconds,
        uint256 btcLotSize
    ) public {
        elapsedSeconds = bound(elapsedSeconds, 0, 4 hours);
        btcLotSize = bound(btcLotSize, 0.05 ether, 5 ether);

        uint256 initialDeposit = 500_000e18;
        musd.mint(depositor, initialDeposit);

        vm.startPrank(depositor);
        musd.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit);
        vm.stopPrank();

        // Oracle value at $80,000/BTC; simulate liquidation burning 90% of oracle value
        uint256 oracleValueMUSD = (btcLotSize * 80_000e18) / 1e18;
        uint256 burnedMUSD = (oracleValueMUSD * 9000) / 10_000;
        sp.simulateLiquidation(address(vault), burnedMUSD, btcLotSize);

        uint256 tStart = vm.getBlockTimestamp();
        uint256 lotId = vault.catalogueLiquidationLot();

        vm.warp(tStart + elapsedSeconds);
        uint256 askMUSD = vault.currentLotAskMUSD(lotId);

        uint256 minFloorMUSD = (oracleValueMUSD * 9200) / 10_000;
        assertGe(askMUSD, minFloorMUSD, "Ask MUSD never drops below 92% floor");
        assertLe(askMUSD, oracleValueMUSD, "Ask MUSD never exceeds 100% oracle value");

        uint256 spBefore = sp.getCompoundedMUSDDeposit(address(vault));
        uint256 maxPayable = askMUSD + (askMUSD * 50) / 10_000;

        vm.startPrank(bidder);
        musd.approve(address(vault), maxPayable);
        vault.bidOnLot(lotId, maxPayable);
        vm.stopPrank();

        assertEq(
            sp.getCompoundedMUSDDeposit(address(vault)),
            spBefore + askMUSD,
            "StabilityPool replenished by exact askMUSD"
        );
    }
}

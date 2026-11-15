// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RelayVault} from "../src/relay/RelayVault.sol";
import {BribeRadarLens} from "../src/relay/BribeRadarLens.sol";
import {ITigrisRouter} from "../src/relay/interfaces/IMezoVe.sol";

contract RelayMockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _n, string memory _s) {
        name = _n;
        symbol = _s;
    }

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

contract RelayMockVE {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public approved;
    mapping(address => mapping(address => bool)) public operatorApproved;
    mapping(uint256 => uint256) public unlockDuration;
    uint256 public tokenId;

    function mintNFT(address to, uint256 id) external {
        ownerOf[id] = to;
        tokenId = id;
    }

    function approve(address spender, uint256 id) external {
        require(msg.sender == ownerOf[id], "not owner");
        approved[id] = spender;
    }

    function setApprovalForAll(address op, bool ok) external {
        operatorApproved[msg.sender][op] = ok;
    }

    function isApprovedOrOwner(address spender, uint256 id) external view returns (bool) {
        address o = ownerOf[id];
        return spender == o || approved[id] == spender || operatorApproved[o][spender];
    }

    function votingPowerOfNFT(uint256) external pure returns (uint256) {
        return 1000e18;
    }

    function increaseUnlockTime(uint256 id, uint256 dur) external {
        unlockDuration[id] = dur;
    }
}

contract RelayMockBribe {
    address[] public rewardTokens;
    mapping(address => uint256) public rewardRate;

    function addReward(address tok, uint256 ratePerSec) external {
        rewardTokens.push(tok);
        rewardRate[tok] = ratePerSec;
    }

    function rewardsListLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function rewards(uint256 idx) external view returns (address) {
        return rewardTokens[idx];
    }
}

contract RelayMockVoter {
    RelayMockERC20 public immutable musd;
    RelayMockERC20 public immutable mezoReward;
    uint256 public musdBribePayout = 500e18;
    uint256 public mezoBribePayout = 200e18;
    mapping(uint256 => uint256) public lastVotedWeightSum;

    address[] public gaugeList;
    mapping(address => address) public gaugeToBribe;
    mapping(address => uint256) public weights;

    constructor(address _musd, address _mezo) {
        musd = RelayMockERC20(_musd);
        mezoReward = RelayMockERC20(_mezo);
    }

    function setPayouts(uint256 _musdPayout, uint256 _mezoPayout) external {
        musdBribePayout = _musdPayout;
        mezoBribePayout = _mezoPayout;
    }

    function addGauge(address g, address b, uint256 w) external {
        gaugeList.push(g);
        gaugeToBribe[g] = b;
        weights[g] = w;
    }

    function length() external view returns (uint256) {
        return gaugeList.length;
    }

    function gauges(uint256 idx) external view returns (address) {
        return gaugeList[idx];
    }

    function vote(uint256 id, address[] calldata, uint256[] calldata w) external {
        uint256 sum = 0;
        for (uint256 i = 0; i < w.length; i++) sum += w[i];
        lastVotedWeightSum[id] = sum;
    }

    function claimBribes(address[] calldata, address[][] calldata tokens, uint256) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokens[i].length; j++) {
                if (tokens[i][j] == address(musd) && musdBribePayout > 0) {
                    musd.mint(msg.sender, musdBribePayout);
                } else if (tokens[i][j] == address(mezoReward) && mezoBribePayout > 0) {
                    mezoReward.mint(msg.sender, mezoBribePayout);
                }
            }
        }
    }
}

contract RelayMockTigrisRouter {
    RelayMockERC20 public immutable musd;
    address public defaultFactory = address(0xFAC);

    constructor(address _musd) {
        musd = RelayMockERC20(_musd);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        ITigrisRouter.Route[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        RelayMockERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        musd.mint(to, amountIn); // 1:1 mock swap to MUSD
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}

contract RelayMockSMUSD {
    RelayMockERC20 public immutable musd;
    mapping(address => uint256) public balanceOf;

    constructor(address _musd) {
        musd = RelayMockERC20(_musd);
    }

    function deposit(uint256 amount) external returns (uint256) {
        musd.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        return amount;
    }

    function withdraw(uint256 amount) external returns (uint256) {
        balanceOf[msg.sender] -= amount;
        musd.transfer(msg.sender, amount);
        return amount;
    }
}

contract RelayMockSP {
    RelayMockERC20 public immutable musd;
    mapping(address => uint256) public deposits;

    constructor(address _musd) {
        musd = RelayMockERC20(_musd);
    }

    function provideToSP(uint256 amount) external {
        musd.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
    }
}

contract RelayMockTM {
    uint256 public constant MCR = 1.1e18;
    uint256 public constant CCR = 1.5e18;
    bool public recoveryMode;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public coll;

    function setTrove(address u, uint256 d, uint256 c) external {
        debt[u] = d;
        coll[u] = c;
    }

    function setRecoveryMode(bool _rm) external {
        recoveryMode = _rm;
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
        uint256 p = d > 25e18 ? d - 25e18 : d;
        return (coll[u], p, d > 25e18 ? 25e18 : 0, 0, 0, 25e18);
    }
}

contract RelayMockBO {
    RelayMockTM public immutable tm;
    uint256 public minNetDebt = 1800e18;
    uint256 public lastRepaid;

    constructor(address _tm) {
        tm = RelayMockTM(_tm);
    }

    function repayMUSD(uint256 amount, address, address) external {
        lastRepaid += amount;
    }
}

contract RelayMockPF {
    function fetchPrice() external pure returns (uint256) {
        return 76_559e18;
    }
}

contract RelayTest is Test {
    RelayMockERC20 internal musd;
    RelayMockERC20 internal mezo;
    RelayMockERC20 internal rogueToken;
    RelayMockVE internal veBTC;
    RelayMockVE internal veMEZO;
    RelayMockVoter internal poolsVoter;
    RelayMockVoter internal boostVoter;
    RelayMockTigrisRouter internal router;
    RelayMockSMUSD internal smusd;
    RelayMockSP internal sp;
    RelayMockTM internal tm;
    RelayMockBO internal bo;
    RelayMockPF internal pf;
    RelayVault internal relay;
    BribeRadarLens internal lens;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal keeper = address(0xBEEF);
    address internal treasury = address(0xFEE);

    function setUp() public {
        musd = new RelayMockERC20("Mezo USD", "MUSD");
        mezo = new RelayMockERC20("MEZO", "MEZO");
        rogueToken = new RelayMockERC20("Rogue", "ROGUE");
        veBTC = new RelayMockVE();
        veMEZO = new RelayMockVE();
        poolsVoter = new RelayMockVoter(address(musd), address(mezo));
        boostVoter = new RelayMockVoter(address(musd), address(mezo));
        router = new RelayMockTigrisRouter(address(musd));
        smusd = new RelayMockSMUSD(address(musd));
        sp = new RelayMockSP(address(musd));
        tm = new RelayMockTM();
        bo = new RelayMockBO(address(tm));
        pf = new RelayMockPF();

        relay = new RelayVault(
            address(veBTC),
            address(veMEZO),
            address(poolsVoter),
            address(boostVoter),
            address(router),
            address(musd),
            address(smusd),
            address(sp),
            address(bo),
            address(tm),
            address(pf),
            treasury
        );
        relay.setWhitelistedRewardToken(address(mezo), true);
        lens = new BribeRadarLens(address(poolsVoter), address(boostVoter), address(veBTC), address(veMEZO));

        veBTC.mintNFT(alice, 42);
        veMEZO.mintNFT(alice, 99);
    }

    function test_NonCustodialRegistrationAndSMUSDCompounding() public {
        // Alice keeps NFT #42 in her wallet and approves RelayVault
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            true
        );
        vm.stopPrank();

        assertEq(veBTC.ownerOf(42), alice, "Alice retains 100% NFT custody");

        address[] memory pools = new address[](1);
        pools[0] = address(0x111);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](2);
        tokens[0][0] = address(musd);
        tokens[0][1] = address(mezo);

        vm.prank(keeper);
        uint256 netRouted = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);

        // 500 MUSD + 200 MEZO swapped to MUSD = 700 MUSD total harvested
        // 2% protocol fee = 14 MUSD, 0.5% keeper bounty = 3.5 MUSD, net = 682.5 MUSD
        assertEq(netRouted, 682.5e18);
        assertEq(musd.balanceOf(treasury), 14e18);
        assertEq(musd.balanceOf(keeper), 3.5e18);
        assertEq(relay.userSMUSDBalance(alice), 682.5e18);

        // Alice can withdraw compounded sMUSD back to her wallet
        vm.prank(alice);
        relay.withdrawCompoundedSMUSD(682.5e18);
        assertEq(musd.balanceOf(alice), 682.5e18);
    }

    function test_RevertsOnNonWhitelistedTokenProtectingAgainstArbitraryToken() public {
        vm.startPrank(alice);
        veMEZO.approve(address(relay), 99);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeMEZO,
            99,
            RelayVault.YieldRoute.PROVIDE_STABILITY_POOL,
            false
        );
        vm.stopPrank();

        address[] memory gauges = new address[](0);
        uint256[] memory weights = new uint256[](0);
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x333);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](1);
        tokens[0][0] = address(rogueToken); // Not whitelisted!

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(RelayVault.TokenNotWhitelisted.selector, address(rogueToken)));
        relay.executeEpochRelay(planId, gauges, weights, bribes, tokens);
    }

    function test_RepayTroveDebtRouteAndMinNetDebtFloorFallback() public {
        tm.setTrove(alice, 4_000e18, 0.1 ether);

        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.REPAY_TROVE_DEBT,
            false
        );
        vm.stopPrank();

        address[] memory pools = new address[](0);
        uint256[] memory weights = new uint256[](0);
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](1);
        tokens[0][0] = address(musd);

        vm.prank(keeper);
        uint256 netRouted = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);
        assertEq(bo.lastRepaid(), netRouted, "Bribe MUSD repaid Alice's Trove debt");
    }

    function test_AutoExtendLockAndFlightPlanUpdateAndTreasuryAdmin() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            true
        );

        // Update flight plan route and toggle active
        relay.updateFlightPlan(planId, RelayVault.YieldRoute.PROVIDE_STABILITY_POOL, true, true);
        vm.stopPrank();

        // Non-governor cannot setTreasury
        vm.prank(alice);
        vm.expectRevert(RelayVault.NotGovernor.selector);
        relay.setTreasury(address(0xCAFE));

        // Zero address reverts
        vm.expectRevert("Zero address");
        relay.setTreasury(address(0));

        // Governor updates treasury
        relay.setTreasury(address(0xCAFE));
        assertEq(relay.feeTreasury(), address(0xCAFE));
    }

    function test_RevertWhen_RegisterPositionWithoutNFTApprovalOrOwner() public {
        // 1. Bob is not the owner of NFT #42 -> reverts with NotNFTApprovedOrOwner
        vm.prank(bob);
        vm.expectRevert(RelayVault.NotNFTApprovedOrOwner.selector);
        relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            true
        );

        // 2. Alice owns NFT #42 but has NOT approved RelayVault -> reverts with NotNFTApprovedOrOwner
        vm.prank(alice);
        vm.expectRevert(RelayVault.NotNFTApprovedOrOwner.selector);
        relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            true
        );
    }

    function test_RevertWhen_WeightBpsDoNotSumTo10000() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            false
        );
        vm.stopPrank();

        address[] memory pools = new address[](2);
        pools[0] = address(0x111);
        pools[1] = address(0x222);
        uint256[] memory badWeights = new uint256[](2);
        badWeights[0] = 6_000;
        badWeights[1] = 3_000; // Sums to 9,000 != 10,000 bps

        address[] memory bribes = new address[](0);
        address[][] memory tokens = new address[][](0);

        vm.prank(keeper);
        vm.expectRevert(RelayVault.InvalidWeightSum.selector);
        relay.executeEpochRelay(planId, pools, badWeights, bribes, tokens);
    }

    function test_RouteToStabilityPoolCompoundsHarvestedBribes() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.PROVIDE_STABILITY_POOL,
            false
        );
        vm.stopPrank();

        address[] memory pools = new address[](1);
        pools[0] = address(0x111);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](2);
        tokens[0][0] = address(musd);
        tokens[0][1] = address(mezo);

        vm.prank(keeper);
        uint256 netRouted = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);

        assertEq(netRouted, 682.5e18);
        assertEq(sp.deposits(address(relay)), 682.5e18, "Net harvested MUSD provided to StabilityPool");
        assertEq(relay.userSPDepositedMUSD(alice), 682.5e18);
    }

    function test_RecoveryModeBlocksUnsafeTroveRepayOrFallsBackToSMUSD() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.REPAY_TROVE_DEBT,
            false
        );
        vm.stopPrank();

        address[] memory pools = new address[](0);
        uint256[] memory weights = new uint256[](0);
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](1);
        tokens[0][0] = address(musd); // 500 MUSD bribe -> 487.5 MUSD net

        // Case 1: Alice's Trove debt is 2,100 MUSD (near the 1,800 minNetDebt + 200 gas comp floor)
        // Repaying 487.5 MUSD would push debt below floor, so RelayVault falls back to parking in sMUSD
        tm.setTrove(alice, 2_100e18, 0.05 ether);
        vm.prank(keeper);
        uint256 net1 = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);
        assertEq(bo.lastRepaid(), 0, "Did not breach minNetDebt floor");
        assertEq(relay.userSMUSDBalance(alice), net1, "Parked in sMUSD fallback");

        // Case 2: System enters Recovery Mode (TCR < 150%) -> blocks Trove repayment and falls back to sMUSD
        tm.setTrove(alice, 5_000e18, 0.1 ether);
        tm.setRecoveryMode(true);
        vm.prank(keeper);
        uint256 net2 = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);
        assertEq(bo.lastRepaid(), 0, "Blocked in Recovery Mode");
        assertEq(relay.userSMUSDBalance(alice), net1 + net2, "Compounded into sMUSD during Recovery Mode");
    }

    function test_BribeRadarLensRanksOptimalGauges() public {
        RelayMockBribe bribe1 = new RelayMockBribe();
        RelayMockBribe bribe2 = new RelayMockBribe();

        // Gauge 1: 1,000 votes weight, paying 0.01 MUSD/sec (6,048 MUSD / 7d epoch => 6.048 MUSD/vote)
        bribe1.addReward(address(musd), 0.01e18);
        boostVoter.addGauge(address(0xAAA1), address(bribe1), 1_000e18);

        // Gauge 2: 500 votes weight, paying 0.02 MUSD/sec (12,096 MUSD / 7d epoch => 24.192 MUSD/vote)
        bribe2.addReward(address(musd), 0.02e18);
        boostVoter.addGauge(address(0xAAA2), address(bribe2), 500e18);

        BribeRadarLens.GaugeBlip[] memory blips = lens.scanBoostGauges(0, 10);
        assertEq(blips.length, 2);
        assertEq(blips[0].gauge, address(0xAAA1));
        assertEq(blips[1].gauge, address(0xAAA2));
        assertGt(
            blips[1].estimatedEpochUSDPerVote,
            blips[0].estimatedEpochUSDPerVote,
            "Gauge 2 has higher bribe efficiency per vote"
        );
    }

    function testFuzz_EpochSweepFeeAndKeeperBountySplitExact(uint256 bribeAmount) public {
        bribeAmount = bound(bribeAmount, 10e18, 500_000e18);
        poolsVoter.setPayouts(bribeAmount, 0);

        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            false
        );
        vm.stopPrank();

        address[] memory pools = new address[](1);
        pools[0] = address(0x111);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](1);
        tokens[0][0] = address(musd);

        uint256 treasuryBefore = musd.balanceOf(treasury);
        uint256 keeperBefore = musd.balanceOf(keeper);

        vm.prank(keeper);
        uint256 userNetRouted = relay.executeEpochRelay(planId, pools, weights, bribes, tokens);

        uint256 protocolFee = musd.balanceOf(treasury) - treasuryBefore;
        uint256 keeperBounty = musd.balanceOf(keeper) - keeperBefore;

        assertEq(protocolFee, (bribeAmount * 200) / 10_000, "2.00% protocol fee");
        assertEq(keeperBounty, (bribeAmount * 50) / 10_000, "0.50% keeper bounty");
        assertEq(protocolFee + keeperBounty + userNetRouted, bribeAmount, "Exact conservation of harvested MUSD");
    }

    function test_RevertWhen_SetTreasuryZeroAddressOrUnauthorized() public {
        vm.prank(bob);
        vm.expectRevert(RelayVault.NotGovernor.selector);
        relay.setTreasury(bob);

        vm.expectRevert("Zero address");
        relay.setTreasury(address(0));
    }

    function test_RevertWhen_WhitelistTokenZeroAddressOrUnauthorized() public {
        vm.prank(bob);
        vm.expectRevert(RelayVault.NotGovernor.selector);
        relay.setWhitelistedRewardToken(address(rogueToken), true);

        vm.expectRevert("Zero address");
        relay.setWhitelistedRewardToken(address(0), true);
    }

    function test_DeactivatePositionStopsEpochRelayVoting() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        uint256 planId = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            false
        );
        relay.updateFlightPlan(planId, RelayVault.YieldRoute.COMPOUND_SMUSD, false, false);
        vm.stopPrank();

        address[] memory pools = new address[](1);
        pools[0] = address(0x111);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;
        address[] memory bribes = new address[](0);
        address[][] memory tokens = new address[][](0);

        vm.prank(keeper);
        vm.expectRevert(RelayVault.InvalidFlightPlan.selector);
        relay.executeEpochRelay(planId, pools, weights, bribes, tokens);
    }

    function test_MultipleVeNFTPositionsCompoundedInSingleEpoch() public {
        vm.startPrank(alice);
        veBTC.approve(address(relay), 42);
        veMEZO.approve(address(relay), 99);
        uint256 planBTC = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeBTC,
            42,
            RelayVault.YieldRoute.COMPOUND_SMUSD,
            true
        );
        uint256 planMEZO = relay.registerFlightPlan(
            RelayVault.EscrowKind.VeMEZO,
            99,
            RelayVault.YieldRoute.PROVIDE_STABILITY_POOL,
            false
        );
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(0x111);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10_000;
        address[] memory bribes = new address[](1);
        bribes[0] = address(0x222);
        address[][] memory tokens = new address[][](1);
        tokens[0] = new address[](2);
        tokens[0][0] = address(musd);
        tokens[0][1] = address(mezo);

        vm.startPrank(keeper);
        uint256 netBTC = relay.executeEpochRelay(planBTC, targets, weights, bribes, tokens);
        uint256 netMEZO = relay.executeEpochRelay(planMEZO, targets, weights, bribes, tokens);
        vm.stopPrank();

        assertEq(netBTC, 682.5e18);
        assertEq(netMEZO, 682.5e18);
        assertEq(relay.userSMUSDBalance(alice), 682.5e18);
        assertEq(relay.userSPDepositedMUSD(alice), 682.5e18);
    }
}

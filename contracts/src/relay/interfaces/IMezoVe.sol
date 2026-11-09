// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title IVotingEscrow
 * @notice Verified interface for Mezo veBTC (0x38E35d92E6Bfc6787272A62345856B13eA12130a)
 *         and veMEZO (0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b) on Chain 31611.
 */
interface IVotingEscrow {
    function tokenId() external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);
    function votingPowerOfNFT(uint256 _tokenId) external view returns (uint256);
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;
    function approve(address _approved, uint256 _tokenId) external;
    function setApprovalForAll(address _operator, bool _approved) external;
}

/**
 * @title IVoter
 * @notice Verified interface for Mezo Tigris Voter (0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D)
 */
interface IVoter {
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimFees(address[] calldata _fees, address[][] calldata _tokens, uint256 _tokenId) external;
    function poke(uint256 _tokenId) external;
    function reset(uint256 _tokenId) external;
    function gauges(address _pool) external view returns (address);
    function poolForGauge(address _gauge) external view returns (address);
    function gaugeToBribe(address _gauge) external view returns (address);
    function gaugeToFees(address _gauge) external view returns (address);
    function weights(address _pool) external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function length() external view returns (uint256);
    function pools(uint256 _index) external view returns (address);
}

/**
 * @title IBoostVoter
 * @notice Verified interface for Mezo BoostVoter (0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1)
 */
interface IBoostVoter {
    function vote(uint256 _tokenId, address[] calldata _gauges, uint256[] calldata _weights) external;
    function claimBribes(address[] calldata _bribes, address[][] calldata _tokens, uint256 _tokenId) external;
    function claimRewards(address[] calldata _gauges) external;
    function getBoost(uint256 _veBTCTokenId) external view returns (uint256);
    function poke(uint256 _tokenId) external;
    function reset(uint256 _tokenId) external;
    function gaugeToBribe(address _gauge) external view returns (address);
    function weights(address _gauge) external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function length() external view returns (uint256);
    function gauges(uint256 _index) external view returns (address);
}

/**
 * @title IBribe
 * @notice Bribe & fee reward contract attached to Voter / BoostVoter gauges
 */
interface IBribe {
    function earned(address _token, uint256 _tokenId) external view returns (uint256);
    function rewardsListLength() external view returns (uint256);
    function rewards(uint256 _index) external view returns (address);
    function rewardRate(address _token) external view returns (uint256);
}

/**
 * @title ITigrisRouter
 * @notice Verified Solidly/Velodrome-style Tigris DEX Router (0xD245BeC6836D85e159763a5D2BFcE7CBC3488e03)
 */
interface ITigrisRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function defaultFactory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, Route[] calldata routes)
        external
        view
        returns (uint256[] memory amounts);
}

/**
 * @title IMUSDSavingsRate
 * @notice Verified Mezo sMUSD (0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16)
 */
interface IMUSDSavingsRate is IERC20 {
    function deposit(uint256 _amount) external returns (uint256 shares);
    function withdraw(uint256 _shares) external returns (uint256 amount);
    function claimYield() external returns (uint256);
    function claimableYield(address _user) external view returns (uint256);
    function yieldIndex() external view returns (uint256);
    function musdToken() external view returns (address);
    function yieldToken() external view returns (address);
}

/**
 * @title IStabilityPool
 * @notice Verified Mezo StabilityPool (0x1CCA7E410eE41739792eA0A24e00349Dd247680e)
 */
interface IStabilityPool {
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function getDepositorCollateralGain(address _depositor) external view returns (uint256);
    function getCompoundedMUSDDeposit(address _depositor) external view returns (uint256);
}

/**
 * @title IBorrowerOperations
 * @notice Verified Mezo BorrowerOperations (0xCdF7028ceAB81fA0C6971208e83fa7872994beE5)
 */
interface IBorrowerOperations {
    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;

    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;
    function minNetDebt() external view returns (uint256);
    function borrowingRate() external view returns (uint256);
}

/**
 * @title ITroveManager
 * @notice Verified Mezo TroveManager (0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0)
 */
interface ITroveManager {
    function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);
    function getEntireDebtAndColl(address _borrower)
        external
        view
        returns (
            uint256 coll,
            uint256 principal,
            uint256 interest,
            uint256 pendingCollateral,
            uint256 pendingPrincipal,
            uint256 pendingInterest
        );
    function checkRecoveryMode(uint256 _price) external view returns (bool);
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
}

/**
 * @title IPriceFeed
 * @notice Verified Mezo PriceFeed (0x86bCF0841622a5dAC14A313a15f96A95421b9366)
 */
interface IPriceFeed {
    function fetchPrice() external returns (uint256);
}

/**
 * @title IHintHelpers
 * @notice Verified Mezo HintHelpers (0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6)
 */
interface IHintHelpers {
    function getApproxHint(uint256 _CR, uint256 _numTrials, uint256 _inputRandomSeed)
        external
        view
        returns (address hintAddress, uint256 diff, uint256 latestRandomSeed);
    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256);
    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256);
}

/**
 * @title ISortedTroves
 * @notice Verified Mezo SortedTroves (0x722E4D24FD6Ff8b0AC679450F3D91294607268fA)
 */
interface ISortedTroves {
    function findInsertPosition(uint256 _NICR, address _prevId, address _nextId)
        external
        view
        returns (address, address);
}

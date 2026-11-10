// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title IMUSD
/// @notice Interface for Mezo MUSD stablecoin (`0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503`)
interface IMUSD is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @title IMUSDSavingsRate
/// @notice Interface for Mezo sMUSD (`0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`)
interface IMUSDSavingsRate is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimYield() external returns (uint256);
    function claimableYield(address account) external view returns (uint256);
    function yieldIndex() external view returns (uint256);
    function musdToken() external view returns (address);
    function yieldToken() external view returns (address);
}

/// @title IStabilityPool
/// @notice Interface for Mezo StabilityPool (`0x1CCA7E410eE41739792eA0A24e00349Dd247680e`)
interface IStabilityPool {
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function withdrawCollateralGainToTrove(address _upperHint, address _lowerHint) external;
    function getDepositorCollateralGain(address _depositor) external view returns (uint256);
    function getCompoundedMUSDDeposit(address _depositor) external view returns (uint256);
    function getTotalMUSDDeposits() external view returns (uint256);
}

/// @title IBorrowerOperations
/// @notice Interface for Mezo BorrowerOperations (`0xCdF7028ceAB81fA0C6971208e83fa7872994beE5`)
interface IBorrowerOperations {
    function openTrove(
        uint256 _debtAmount,
        address _upperHint,
        address _lowerHint
    ) external payable;

    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable;

    function closeTrove() external;
    function minNetDebt() external view returns (uint256);
    function borrowingRate() external view returns (uint256);
    function redemptionRate() external view returns (uint256);
    function maxBorrowingCapacity(address _borrower) external view returns (uint256);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
}

/// @title ITroveManager
/// @notice Interface for Mezo TroveManager (`0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0`)
interface ITroveManager {
    function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);
    /// @dev Returns (coll, principal, interest, pendingCollateral, pendingPrincipal, pendingInterest)
    ///      CRITICAL: `principal` ALREADY includes `pendingPrincipal` and `interest` ALREADY includes `pendingInterest`!
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
    function getTCR(uint256 _price) external view returns (uint256);
    function redeemCollateral(
        uint256 _amount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations
    ) external;
    function liquidate(address _borrower) external;
    function liquidateTroves(uint256 _n) external;
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function getTroveOwnersCount() external view returns (uint256);
}

/// @title IPriceFeed
/// @notice Interface for Mezo PriceFeed (`0x86bCF0841622a5dAC14A313a15f96A95421b9366`)
interface IPriceFeed {
    function fetchPrice() external returns (uint256);
    function lastGoodPrice() external view returns (uint256);
}

/// @title IHintHelpers
/// @notice Interface for Mezo HintHelpers (`0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6`)
interface IHintHelpers {
    function getApproxHint(
        uint256 _CR,
        uint256 _numTrials,
        uint256 _inputRandomSeed
    ) external view returns (address hintAddress, uint256 diff, uint256 latestRandomSeed);

    function getRedemptionHints(
        uint256 _MUSDAmount,
        uint256 _price,
        uint256 _maxIterations
    )
        external
        view
        returns (
            address firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedMUSDAmount
        );

    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256);
    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256);
}

/// @title ISortedTroves
/// @notice Interface for Mezo SortedTroves (`0x722E4D24FD6Ff8b0AC679450F3D91294607268fA`)
interface ISortedTroves {
    function findInsertPosition(
        uint256 _NICR,
        address _prevId,
        address _nextId
    ) external view returns (address, address);
    function getFirst() external view returns (address);
    function getLast() external view returns (address);
    function getNext(address _id) external view returns (address);
    function getPrev(address _id) external view returns (address);
    function contains(address _id) external view returns (bool);
}

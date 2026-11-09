// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MezoAddresses
/// @notice Verified Mezo Testnet (Chain ID 31611) canonical protocol addresses
library MezoAddresses {
    address internal constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address internal constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address internal constant STABILITY_POOL = 0x1CCA7E410eE41739792eA0A24e00349Dd247680e;
    address internal constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address internal constant SORTED_TROVES = 0x722E4D24FD6Ff8b0AC679450F3D91294607268fA;
    address internal constant HINT_HELPERS = 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6;
    address internal constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;
    address internal constant PCV = 0x4dDD70f4C603b6089c07875Be02fEdFD626b80Af;
    address internal constant MUSD_TOKEN = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address internal constant BTC_PRECOMPILE = 0x7b7C000000000000000000000000000000000000;
    address internal constant MEZO_PRECOMPILE = 0x7B7c000000000000000000000000000000000001;
}

/// @title IMUSD
/// @notice Standard ERC-20 + Permit interface for MUSD stablecoin on Mezo
interface IMUSD {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

/// @title IPriceFeed
/// @notice Mezo BTC/USD Oracle PriceFeed
interface IPriceFeed {
    function fetchPrice() external view returns (uint256);
    function lastGoodPrice() external view returns (uint256);
}

/// @title IBorrowerOperations
/// @notice Mezo Liquity-based BorrowerOperations interface
interface IBorrowerOperations {
    function openTrove(
        uint256 _debtAmount,
        address _upperHint,
        address _lowerHint
    ) external payable;

    function addColl(address _upperHint, address _lowerHint) external payable;

    function withdrawColl(
        uint256 _collWithdrawal,
        address _upperHint,
        address _lowerHint
    ) external;

    function withdrawMUSD(
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external;

    function repayMUSD(
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external;

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
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
}

/// @title ITroveManager
/// @notice Mezo TroveManager interface
interface ITroveManager {
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function getTroveOwnersCount() external view returns (uint256);
    function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);
    function checkRecoveryMode(uint256 _price) external view returns (bool);
    function getTCR(uint256 _price) external view returns (uint256);

    /// @notice Returns (coll, principal, interest, pendingCollateral, pendingPrincipal, pendingInterest)
    /// @dev CRITICAL: `principal` ALREADY includes `pendingPrincipal` and `interest` ALREADY includes `pendingInterest`!
    function getEntireDebtAndColl(
        address _borrower
    )
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

    function getTroveStatus(address _borrower) external view returns (uint256);
}

/// @title IStabilityPool
/// @notice Mezo StabilityPool interface for MUSD liquidation absorption & BTC collateral gains
interface IStabilityPool {
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function withdrawCollateralGainToTrove(address _upperHint, address _lowerHint) external;
    function getDepositorCollateralGain(address _depositor) external view returns (uint256);
    function getCompoundedMUSDDeposit(address _depositor) external view returns (uint256);
    function getTotalMUSDDeposits() external view returns (uint256);
}

/// @title IMUSDSavingsRate
/// @notice Mezo sMUSD (MUSDSavingsRate) yield-bearing vault interface
interface IMUSDSavingsRate {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function claimYield() external returns (uint256);
    function claimableYield(address _account) external view returns (uint256);
    function yieldIndex() external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function musdToken() external view returns (address);
    function yieldToken() external view returns (address);
}

/// @title IHintHelpers
/// @notice Mezo HintHelpers for SortedTroves insertion & redemption hints
interface IHintHelpers {
    function getApproxHint(
        uint256 _CR,
        uint256 _numTrials,
        uint256 _inputRandomSeed
    ) external view returns (address hintAddress, uint256 diff, uint256 latestRandomSeed);

    function getRedemptionHints(
        uint256 _MUSDamount,
        uint256 _price,
        uint256 _maxIterations
    )
        external
        view
        returns (
            address firstRedemptionHint,
            uint256 partialRedemptionHintNICR,
            uint256 truncatedMUSDamount
        );

    function computeNominalCR(uint256 _coll, uint256 _debt) external pure returns (uint256);
    function computeCR(uint256 _coll, uint256 _debt, uint256 _price) external pure returns (uint256);
}

/// @title ISortedTroves
/// @notice Doubly-linked list of Troves sorted by NICR
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
    function getSize() external view returns (uint256);
}

/// @title IAutopayFactory
/// @notice Callback/config interface read by TroveVault clones
interface IAutopayFactory {
    function borrowerOperations() external view returns (address);
    function troveManager() external view returns (address);
    function stabilityPool() external view returns (address);
    function smusd() external view returns (address);
    function priceFeed() external view returns (address);
    function musd() external view returns (address);
    function protocolTreasury() external view returns (address);
}

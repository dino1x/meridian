// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

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

interface IMUSDSavingsRate {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function claimYield() external returns (uint256);
    function claimableYield(address _depositor) external view returns (uint256);
    function yieldIndex() external view returns (uint256);
    function musdToken() external view returns (address);
    function yieldToken() external view returns (address);
    function balanceOf(address _account) external view returns (uint256);
}

interface IStabilityPool {
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function withdrawCollateralGainToTrove(address _upperHint, address _lowerHint) external;
    function getDepositorCollateralGain(address _depositor) external view returns (uint256);
    function getCompoundedMUSDDeposit(address _depositor) external view returns (uint256);
}

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
    function maxBorrowingCapacity() external view returns (uint256);
}

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
    function redeemCollateral(
        uint256 _amount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations
    ) external;
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function getTroveStatus(address _borrower) external view returns (uint256);
}

interface IPriceFeed {
    function fetchPrice() external view returns (uint256);
}

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

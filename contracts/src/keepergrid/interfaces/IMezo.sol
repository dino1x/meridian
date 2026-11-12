// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMUSDSavingsRate is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimYield() external returns (uint256);
    function claimableYield(address account) external view returns (uint256);
}

interface IBorrowerOperations {
    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external;
    function minNetDebt() external view returns (uint256);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
}

interface ITroveManager {
    function MCR() external view returns (uint256);
    function CCR() external view returns (uint256);
    function checkRecoveryMode(uint256 _price) external view returns (bool);
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
    function liquidate(address _borrower) external;
    function liquidateTroves(uint256 _n) external;
    function redeemCollateral(
        uint256 _MUSDAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint256 _partialRedemptionHintNICR,
        uint256 _maxIterations
    ) external;
}

interface IHintHelpers {
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
}

interface ISortedTroves {
    function findInsertPosition(
        uint256 _NICR,
        address _prevId,
        address _nextId
    ) external view returns (address, address);
}

interface IPriceFeed {
    function fetchPrice() external returns (uint256);
}

interface IBoostVoter {
    function poke(uint256 _tokenId) external;
}

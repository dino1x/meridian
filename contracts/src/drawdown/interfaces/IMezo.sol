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
    function openTrove(
        uint256 _debtAmount,
        address _upperHint,
        address _lowerHint
    ) external payable;

    function withdrawMUSD(
        uint256 _amount,
        address _upperHint,
        address _lowerHint
    ) external;

    function addColl(address _upperHint, address _lowerHint) external payable;
    function minNetDebt() external view returns (uint256);
    function borrowingRate() external view returns (uint256);
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
}

interface IPriceFeed {
    function fetchPrice() external returns (uint256);
}

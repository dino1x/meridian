// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IMezo.sol";

/// @title bMUSDToken (Boosted MUSD)
/// @notice Yield-amplified ERC-20 token minted by ChickenBondManager when bonds Chicken In.
///         Backed by the Roost Reserve Bucket, while the Pending and Permanent Buckets direct
///         their sMUSD and StabilityPool yield into the Reserve Bucket, creating a monotonically
///         rising MUSD redemption floor per bMUSD.
contract bMUSDToken is IERC20 {
    string public constant name = "Roost Boosted MUSD";
    string public constant symbol = "bMUSD";
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    address public immutable bondManager;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error OnlyBondManager();
    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    modifier onlyBondManager() {
        if (msg.sender != bondManager) revert OnlyBondManager();
        _;
    }

    constructor(address _bondManager) {
        require(_bondManager != address(0), "Zero address");
        bondManager = _bondManager;
    }

    function mint(address to, uint256 amount) external onlyBondManager {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyBondManager {
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = currentAllowance - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[from];
        if (bal < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}

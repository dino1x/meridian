// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IMezo.sol";

interface IChronosVaultCallback {
    function onYTTransfer(uint256 seriesId, address from, address to) external;
}

abstract contract BaseChronosERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant override decimals = 18;
    uint256 public override totalSupply;
    address public immutable vault;
    uint256 public immutable seriesId;
    uint256 public immutable maturity;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error OnlyVault();
    error InsufficientBalance();
    error InsufficientAllowance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _vault,
        uint256 _seriesId,
        uint256 _maturity
    ) {
        require(_vault != address(0), "Zero address");
        name = _name;
        symbol = _symbol;
        vault = _vault;
        seriesId = _seriesId;
        maturity = _maturity;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _transfer(address from, address to, uint256 amount) internal {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        _beforeTokenTransfer(from, to, amount);
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function mint(address to, uint256 amount) external onlyVault {
        _beforeTokenTransfer(address(0), to, amount);
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        _beforeTokenTransfer(from, address(0), amount);
        unchecked {
            balanceOf[from] -= amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}

/// @title ChronosPT — Principal Token redeemable 1:1 for MUSD at maturity
contract ChronosPT is BaseChronosERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        address _vault,
        uint256 _seriesId,
        uint256 _maturity
    ) BaseChronosERC20(_name, _symbol, _vault, _seriesId, _maturity) {}
}

/// @title ChronosYT — Yield Token capturing 100% of sMUSD yield index growth & StabilityPool BTC gains until maturity
contract ChronosYT is BaseChronosERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        address _vault,
        uint256 _seriesId,
        uint256 _maturity
    ) BaseChronosERC20(_name, _symbol, _vault, _seriesId, _maturity) {}

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (from != address(0) && to != address(0)) {
            IChronosVaultCallback(vault).onYTTransfer(seriesId, from, to);
        }
    }
}

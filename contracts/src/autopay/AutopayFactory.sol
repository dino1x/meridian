// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAutopayFactory} from "./interfaces/IMezo.sol";
import {TroveVault} from "./TroveVault.sol";

/// @title AutopayFactory
/// @notice Deploys deterministic EIP-1167 minimal proxy clones of TroveVault for each Mezo borrower.
contract AutopayFactory is IAutopayFactory {
    address public immutable override borrowerOperations;
    address public immutable override troveManager;
    address public immutable override stabilityPool;
    address public immutable override smusd;
    address public immutable override priceFeed;
    address public immutable override musd;
    address public override protocolTreasury;

    address public immutable vaultImplementation;
    address[] public allVaults;
    mapping(address => address) public userVault;

    event VaultPlanted(address indexed owner, address indexed vault, uint256 reserveBps, uint256 lowerBandICR, uint256 upperBandICR);

    constructor(
        address _borrowerOperations,
        address _troveManager,
        address _stabilityPool,
        address _smusd,
        address _priceFeed,
        address _musd,
        address _protocolTreasury
    ) {
        require(_borrowerOperations != address(0), "Zero address");
        require(_troveManager != address(0), "Zero address");
        require(_stabilityPool != address(0), "Zero address");
        require(_smusd != address(0), "Zero address");
        require(_priceFeed != address(0), "Zero address");
        require(_musd != address(0), "Zero address");
        require(_protocolTreasury != address(0), "Zero address");

        borrowerOperations = _borrowerOperations;
        troveManager = _troveManager;
        stabilityPool = _stabilityPool;
        smusd = _smusd;
        priceFeed = _priceFeed;
        musd = _musd;
        protocolTreasury = _protocolTreasury;

        vaultImplementation = address(new TroveVault());
    }

    /// @notice Deploys an EIP-1167 minimal proxy clone of TroveVault and initializes it.
    function plantVault(
        uint256 reserveBps,
        uint256 lowerBandICR,
        uint256 upperBandICR
    ) external returns (address vault) {
        vault = _clone(vaultImplementation);
        userVault[msg.sender] = vault;
        allVaults.push(vault);
        // forge-lint: disable-next-line(reentrancy-events)
        emit VaultPlanted(msg.sender, vault, reserveBps, lowerBandICR, upperBandICR);
        TroveVault(payable(vault)).initialize(address(this), msg.sender, reserveBps, lowerBandICR, upperBandICR);
    }

    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    function _clone(address implementation) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "EIP1167: create failed");
    }
}

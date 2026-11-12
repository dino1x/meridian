// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {KeeperGrid} from "../src/keepergrid/KeeperGrid.sol";

contract DeployKeeperGrid is Script {
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address constant HINT_HELPERS = 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6;
    address constant SORTED_TROVES = 0x722E4D24FD6Ff8b0AC679450F3D91294607268fA;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;
    address constant BOOST_VOTER = 0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1;

    function run() external {
        vm.startBroadcast();
        KeeperGrid grid = new KeeperGrid(
            MUSD,
            SMUSD,
            BORROWER_OPERATIONS,
            TROVE_MANAGER,
            HINT_HELPERS,
            SORTED_TROVES,
            PRICE_FEED,
            BOOST_VOTER,
            msg.sender
        );
        console2.log("KeeperGrid:", address(grid));
        vm.stopBroadcast();
    }
}

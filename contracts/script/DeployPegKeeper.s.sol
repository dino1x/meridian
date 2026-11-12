// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PegKeeperVault} from "../src/pegkeeper/PegKeeperVault.sol";

contract DeployPegKeeper is Script {
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address constant HINT_HELPERS = 0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6;
    address constant SORTED_TROVES = 0x722E4D24FD6Ff8b0AC679450F3D91294607268fA;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;
    address constant TIGRIS_ROUTER = 0xD245BeC6836D85e159763a5D2BFcE7CBC3488e03;
    address constant BTC_PRECOMPILE = 0x7b7C000000000000000000000000000000000000;

    function run() external {
        vm.startBroadcast();
        PegKeeperVault vault = new PegKeeperVault(
            MUSD,
            SMUSD,
            TROVE_MANAGER,
            HINT_HELPERS,
            SORTED_TROVES,
            PRICE_FEED,
            TIGRIS_ROUTER,
            BTC_PRECOMPILE,
            msg.sender
        );
        console2.log("PegKeeperVault:", address(vault));
        vm.stopBroadcast();
    }
}

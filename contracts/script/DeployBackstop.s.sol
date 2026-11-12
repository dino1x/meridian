// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BackstopVault} from "../src/backstop/BackstopVault.sol";

contract DeployBackstop is Script {
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant STABILITY_POOL = 0x1CCA7E410eE41739792eA0A24e00349Dd247680e;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;

    function run() external {
        vm.startBroadcast();
        BackstopVault vault = new BackstopVault(
            MUSD,
            STABILITY_POOL,
            SMUSD,
            PRICE_FEED,
            TROVE_MANAGER,
            msg.sender
        );
        console2.log("BackstopVault:", address(vault));
        vm.stopBroadcast();
    }
}

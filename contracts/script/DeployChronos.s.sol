// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChronosTermVault} from "../src/chronos/ChronosTermVault.sol";
import {BatchRateAuction} from "../src/chronos/BatchRateAuction.sol";

contract DeployChronos is Script {
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant STABILITY_POOL = 0x1CCA7E410eE41739792eA0A24e00349Dd247680e;
    address constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;

    function run() external {
        vm.startBroadcast();
        ChronosTermVault vault = new ChronosTermVault(
            MUSD,
            SMUSD,
            STABILITY_POOL,
            BORROWER_OPERATIONS,
            TROVE_MANAGER,
            PRICE_FEED,
            msg.sender
        );
        BatchRateAuction auction = new BatchRateAuction(MUSD);
        console2.log("ChronosTermVault:", address(vault));
        console2.log("BatchRateAuction:", address(auction));
        vm.stopBroadcast();
    }
}

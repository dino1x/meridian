// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AutopayFactory} from "../src/autopay/AutopayFactory.sol";
import {MezoAddresses} from "../src/autopay/interfaces/IMezo.sol";

contract DeployAutopay is Script {
    function run() external {
        vm.startBroadcast();
        AutopayFactory factory = new AutopayFactory(
            MezoAddresses.BORROWER_OPERATIONS,
            MezoAddresses.TROVE_MANAGER,
            MezoAddresses.STABILITY_POOL,
            MezoAddresses.SMUSD,
            MezoAddresses.PRICE_FEED,
            MezoAddresses.MUSD_TOKEN,
            msg.sender
        );
        console2.log("AutopayFactory:", address(factory));
        console2.log("TroveVault Implementation:", factory.vaultImplementation());
        vm.stopBroadcast();
    }
}

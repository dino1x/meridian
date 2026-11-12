// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DrawdownDesk} from "../src/drawdown/DrawdownDesk.sol";

contract DeployDrawdown is Script {
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;

    function run() external {
        vm.startBroadcast();
        DrawdownDesk desk = new DrawdownDesk(
            MUSD,
            SMUSD,
            BORROWER_OPERATIONS,
            TROVE_MANAGER,
            PRICE_FEED,
            msg.sender
        );
        console2.log("DrawdownDesk:", address(desk));
        vm.stopBroadcast();
    }
}

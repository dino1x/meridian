// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RelayVault} from "../src/relay/RelayVault.sol";
import {BribeRadarLens} from "../src/relay/BribeRadarLens.sol";

contract DeployRelay is Script {
    address constant VEBTC = 0x38E35d92E6Bfc6787272A62345856B13eA12130a;
    address constant VEMEZO = 0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b;
    address constant POOLS_VOTER = 0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D;
    address constant BOOST_VOTER = 0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1;
    address constant TIGRIS_ROUTER = 0xD245BeC6836D85e159763a5D2BFcE7CBC3488e03;
    address constant MUSD = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant SMUSD = 0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16;
    address constant STABILITY_POOL = 0x1CCA7E410eE41739792eA0A24e00349Dd247680e;
    address constant BORROWER_OPERATIONS = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5;
    address constant TROVE_MANAGER = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0;
    address constant PRICE_FEED = 0x86bCF0841622a5dAC14A313a15f96A95421b9366;

    function run() external {
        vm.startBroadcast();
        RelayVault vault = new RelayVault(
            VEBTC,
            VEMEZO,
            POOLS_VOTER,
            BOOST_VOTER,
            TIGRIS_ROUTER,
            MUSD,
            SMUSD,
            STABILITY_POOL,
            BORROWER_OPERATIONS,
            TROVE_MANAGER,
            PRICE_FEED,
            msg.sender
        );
        BribeRadarLens lens = new BribeRadarLens(POOLS_VOTER, BOOST_VOTER, VEBTC, VEMEZO);
        console2.log("RelayVault:", address(vault));
        console2.log("BribeRadarLens:", address(lens));
        vm.stopBroadcast();
    }
}

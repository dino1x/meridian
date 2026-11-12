// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// @notice Verifies Meridian unified suite canonical contract registry invariants for Mezo Testnet (31611).
contract MeridianSuiteTest is Test {
    address internal constant ROOST_BOND_MANAGER = 0x528ADC9Ae5A430D0a53f711661F18A8C5831CaF6;
    address internal constant ROOST_BMUSD = 0x04dC85c45d6B68fBeF346F823dC05682415B3C9E;
    address internal constant ROOST_BOND_NFT = 0x09F2E2884b714aC142EF4aAA453d83D9D3749404;

    address internal constant RELAY_VAULT = 0x69c1f2EfBe79A1201CDaEE5a5F63024Ee374aF23;
    address internal constant BRIBE_RADAR_LENS = 0x83124D679e71420761b0cCeeaFc5735847db58B1;

    address internal constant CHRONOS_TERM_VAULT = 0x321C3673cCfDb5d5E259c86F4B2dB58Cc3a1eB64;
    address internal constant BATCH_RATE_AUCTION = 0xCcF397A784873406b56457643Cc5b08Fd89A86c4;

    address internal constant AUTOPAY_FACTORY = 0x0EAA0e96974CBD3169B060c7C121165D91820078;
    address internal constant TROVE_VAULT_IMPL = 0xeC4b9374F9e4f62004F840EfF20a048b689D08CC;

    address internal constant PEG_KEEPER_VAULT = 0x8F569515fe8FB05177db0f039EA89a480C220e36;
    address internal constant BACKSTOP_VAULT = 0x2FD13bf151587344C3505dD92439B68b9bf54642;

    address internal constant KEEPER_GRID = 0x61D0e6a90f7d0bCB75786E2a282f04Ff281F72C1;
    address internal constant DRAWDOWN_DESK = 0x0acaaD024c9d4729C6717B6429117d4aE66f9070;

    function test_MeridianSuiteRegistryDistinctNonZero() public pure {
        address[13] memory deployed = [
            ROOST_BOND_MANAGER,
            ROOST_BMUSD,
            ROOST_BOND_NFT,
            RELAY_VAULT,
            BRIBE_RADAR_LENS,
            CHRONOS_TERM_VAULT,
            BATCH_RATE_AUCTION,
            AUTOPAY_FACTORY,
            TROVE_VAULT_IMPL,
            PEG_KEEPER_VAULT,
            BACKSTOP_VAULT,
            KEEPER_GRID,
            DRAWDOWN_DESK
        ];

        for (uint256 i = 0; i < deployed.length; i++) {
            assertTrue(deployed[i] != address(0), "zero address");
            for (uint256 j = i + 1; j < deployed.length; j++) {
                assertTrue(deployed[i] != deployed[j], "duplicate address");
            }
        }
    }
}

# Meridian

Meridian is a set of eight MUSD and MEZO products on Mezo, built as Solidity contracts plus one web app. Every module plugs into Mezo's own core contracts (BorrowerOperations, TroveManager, StabilityPool, sMUSD, SortedTroves, HintHelpers, Voter and BoostVoter) instead of running a separate system beside them.

| Pillar | Module | What it does with MUSD / MEZO |
| :--- | :--- | :--- |
| Credit | **Autopay** | A per-user trove vault (EIP-1167 clone). Half its growth reserve sits in sMUSD and repays the trove's MUSD debt; the other half sits in the Stability Pool and compounds liquidation BTC back into the trove. |
| Credit | **Drawdown** | Payroll streamed per second from a corporate BTC trove. MUSD is borrowed with `withdrawMUSD` only when a contributor claims, with an sMUSD fallback in Recovery Mode. |
| Yield | **Roost** | Principal-protected bonds on MUSD. Bonds accrue bMUSD on a hyperbolic curve (α = 15 days); chicken out for 100% of principal, or chicken in for bMUSD. |
| Yield | **Chronos** | Splits sMUSD into fixed-maturity principal and yield tokens (30, 90, 180 days) and sets one fixed rate per tenor with a uniform-price batch auction. |
| Peg | **PegKeeper** | A pooled vault that parks MUSD in sMUSD at the peg and runs hinted `redeemCollateral` arbitrage when MUSD trades below $1 minus the redemption fee. |
| Peg | **Backstop** | A Stability Pool vault that sells seized BTC by Dutch auction (100% to 92% of the oracle over two hours) and re-deposits the MUSD proceeds. |
| Governance | **Relay** | A non-custodial operator for veBTC and veMEZO: votes each epoch, harvests whitelisted bribes and routes them into MUSD. |
| Governance | **KeeperGrid** | A keeper network for liquidations, redemptions, top-ups and gauge pokes. Keeper bonds earn in sMUSD; missed slots are slashed 10%. |

## What is real vs simulated

| Part | Status | Notes |
| :--- | :--- | :--- |
| Smart contracts (13) | **Deployed on Mezo Testnet** | Addresses below; bytecode confirmed on chain 31611. Not audited. |
| Contract tests | **Real, offline** | 85 Foundry unit and fuzz tests against local mocks of the Mezo core contracts. No RPC or API keys needed. |
| Mezo network data in the app | **Live reads** | Block height, BTC oracle price, Stability Pool deposits, sMUSD supply and yield index, MCR/CCR, trove count, Recovery Mode, borrowing and redemption rates, lowest-ICR trove, veBTC/veMEZO lock counts and BoostVoter gauges are read from `https://rpc.test.mezo.org`. Each read falls back independently; if the RPC is unreachable the header shows **Offline snapshot**. |
| Wallet connection | **Real, with a demo fallback** | Uses an injected EIP-1193 wallet and switches it to Mezo Testnet. Without a browser wallet it uses a read-only demo address and says so in the activity log. |
| On-chain actions in all eight modules | **Real transactions** | Each module has an "On Mezo Testnet" panel. With a browser wallet connected it approves MUSD only when needed, computes trove hints through Mezo's HintHelpers, sends the call, waits for confirmation, reads your position back and links the transaction in the explorer. Roost `createBond` / `chickenOut` / `chickenIn`; PegKeeper `deposit` / `withdraw`; Backstop `deposit`; KeeperGrid `postKeeperBond`; Chronos `mintPTAndYT`; Autopay `plantVault` / `openSelfPayingTrove` / `harvestAndStrengthen` / `rebalanceBand`; Drawdown `initializeCorporateTrove` / `createPayStream` (treasury admin only) and `claimPaySlip` (stream recipient); Relay ve `approve` + `registerFlightPlan`. |
| Sample sections of every module | **Simulated in the browser** | Shown below a "Simulation with sample positions" divider, using the contracts' fee and parameter values so each flow can be shown without a wallet. Nothing there sends a transaction. |
| Module header figures | **Live reads, with two exceptions** | Bonds issued and Roost buckets, vault assets and share prices, lots catalogued, active keepers and MUSD locked per Chronos series are read from the deployed contracts. Chronos fixed rates are sample auction fixings (no auction has cleared on-chain yet); the PegKeeper spot price is the simulated DEX slider. |
| DEX price in PegKeeper | **Simulated** | The MUSD spot price is a slider, so the arbitrage path can be shown at any discount. |

## Proof on Mezo Testnet

These transactions were sent from a testnet-only wallet, `0xeD5313eB8Ad9ebE8c50A455D7e323a5acb3F0742`, funded from the Mezo faucet.

| Step | Transaction |
| :--- | :--- |
| Borrow 1,800 MUSD on Mezo (open trove, 0.045 BTC) | [`0x005c41b6…b9be8f`](https://explorer.test.mezo.org/tx/0x005c41b6cef2c9e9955c9011cb59001c2b9df31e7a19ef3400208f888eb9be8f) |
| Roost: approve 200 MUSD | [`0x7967635f…12c71d`](https://explorer.test.mezo.org/tx/0x7967635fedda7fb4db5f310a8b5a720ce1fa08d939c5e724898013418912c71d) |
| Roost: `createBond` 200 MUSD (bond #1) | [`0x8025e55b…2a3ba1`](https://explorer.test.mezo.org/tx/0x8025e55b5dc7a8e139a551c4dba1c7d751a61853c081a7c73de1cc82542a3ba1) |
| PegKeeper: approve 200 MUSD | [`0x9dc3b505…9831e6`](https://explorer.test.mezo.org/tx/0x9dc3b50593bcde765411cebbc981e437ffea8d4ba8ebc82e255097a4ee9831e6) |
| PegKeeper: `deposit` 200 MUSD | [`0x86aa14ad…4e43f1`](https://explorer.test.mezo.org/tx/0x86aa14adaf248d2b558ee1b6a3394b663d0ee1533cfc509d1ecc51b91a4e43f1) |
| Backstop: approve 200 MUSD | [`0x59f546d8…d7023b`](https://explorer.test.mezo.org/tx/0x59f546d8d5e546fd4b16ba6abd21049e86477c1c577eeb79d39762fa92d7023b) |
| Backstop: `deposit` 200 MUSD | [`0xc659515b…cafb13`](https://explorer.test.mezo.org/tx/0xc659515b13ceff831458cde33ad32dab53c4ea951cab9e152eabae313dcafb13) |
| KeeperGrid: approve 500 MUSD | [`0x10de66a9…dda965`](https://explorer.test.mezo.org/tx/0x10de66a973f2e79256303d8eb506ef6af4deea5c279804cbb927cef0a7dda965) |
| KeeperGrid: `postKeeperBond` 500 MUSD | [`0x1b7d7ccb…e6670b`](https://explorer.test.mezo.org/tx/0x1b7d7ccb7c9d7cdb9e846a706cbe911eaf24b2c4b370748a74fd5ab56fe6670b) |
| Chronos: approve 200 MUSD | [`0x436e9c8e…51aafc`](https://explorer.test.mezo.org/tx/0x436e9c8efdc2d6448f87596f10110d13f2c6c9576e66bee1955c1180b051aafc) |
| Chronos: `mintPTAndYT` 200 MUSD into the 90-day series | [`0xf8d7f852…98d510`](https://explorer.test.mezo.org/tx/0xf8d7f85275afb1678d54cdf05fbab46c2c44148c4c93971b337e11807f98d510) |
| Autopay: `plantVault` (30% reserve, band 135%–220%) | [`0xa6087b48…00d35b`](https://explorer.test.mezo.org/tx/0xa6087b48075f6ec20dcb7b576a58f8747ab6b5688982e9c0965842cc2500d35b) |

How the remaining flows were checked:

- **Relay** `approve` + `registerFlightPlan` ran end to end in the app against a local fork of Mezo Testnet, acting as the owner of veBTC #1762.
- **Autopay** `openSelfPayingTrove` and **Drawdown** `initializeCorporateTrove` / `createPayStream` pass as `eth_call` dry runs on Mezo Testnet with the exact arguments the app sends. A real run needs about 0.04 test BTC more in the wallet; Drawdown setup must come from the treasury admin `0x7B71B6186af01bF1DA9B091306FB911453389BE9`.
- Trove-opening calls cannot run on a local fork because Mezo's price oracle is a chain precompile, which is why they were checked against the live chain.

## Deployed contracts (Mezo Testnet, chain 31611)

Explorer: https://explorer.test.mezo.org · RPC: https://rpc.test.mezo.org

| Module | Contract | Address |
| :--- | :--- | :--- |
| Autopay | `AutopayFactory` | [`0x0EAA0e96974CBD3169B060c7C121165D91820078`](https://explorer.test.mezo.org/address/0x0EAA0e96974CBD3169B060c7C121165D91820078) |
| Autopay | `TroveVault` (implementation) | [`0xeC4b9374F9e4f62004F840EfF20a048b689D08CC`](https://explorer.test.mezo.org/address/0xeC4b9374F9e4f62004F840EfF20a048b689D08CC) |
| Drawdown | `DrawdownDesk` | [`0x0acaaD024c9d4729C6717B6429117d4aE66f9070`](https://explorer.test.mezo.org/address/0x0acaaD024c9d4729C6717B6429117d4aE66f9070) |
| Roost | `ChickenBondManager` | [`0x528ADC9Ae5A430D0a53f711661F18A8C5831CaF6`](https://explorer.test.mezo.org/address/0x528ADC9Ae5A430D0a53f711661F18A8C5831CaF6) |
| Roost | `bMUSDToken` | [`0x04dC85c45d6B68fBeF346F823dC05682415B3C9E`](https://explorer.test.mezo.org/address/0x04dC85c45d6B68fBeF346F823dC05682415B3C9E) |
| Roost | `BondNFT` | [`0x09F2E2884b714aC142EF4aAA453d83D9D3749404`](https://explorer.test.mezo.org/address/0x09F2E2884b714aC142EF4aAA453d83D9D3749404) |
| Chronos | `ChronosTermVault` | [`0x321C3673cCfDb5d5E259c86F4B2dB58Cc3a1eB64`](https://explorer.test.mezo.org/address/0x321C3673cCfDb5d5E259c86F4B2dB58Cc3a1eB64) |
| Chronos | `BatchRateAuction` | [`0xCcF397A784873406b56457643Cc5b08Fd89A86c4`](https://explorer.test.mezo.org/address/0xCcF397A784873406b56457643Cc5b08Fd89A86c4) |
| PegKeeper | `PegKeeperVault` | [`0x8F569515fe8FB05177db0f039EA89a480C220e36`](https://explorer.test.mezo.org/address/0x8F569515fe8FB05177db0f039EA89a480C220e36) |
| Backstop | `BackstopVault` | [`0x2FD13bf151587344C3505dD92439B68b9bf54642`](https://explorer.test.mezo.org/address/0x2FD13bf151587344C3505dD92439B68b9bf54642) |
| Relay | `RelayVault` | [`0x69c1f2EfBe79A1201CDaEE5a5F63024Ee374aF23`](https://explorer.test.mezo.org/address/0x69c1f2EfBe79A1201CDaEE5a5F63024Ee374aF23) |
| Relay | `BribeRadarLens` | [`0x83124D679e71420761b0cCeeaFc5735847db58B1`](https://explorer.test.mezo.org/address/0x83124D679e71420761b0cCeeaFc5735847db58B1) |
| KeeperGrid | `KeeperGrid` | [`0x61D0e6a90f7d0bCB75786E2a282f04Ff281F72C1`](https://explorer.test.mezo.org/address/0x61D0e6a90f7d0bCB75786E2a282f04Ff281F72C1) |

Mezo core contracts used: MUSD `0x1189…c503`, sMUSD `0x6f46…8e16`, StabilityPool `0x1CCA…680e`, BorrowerOperations `0xCdF7…beE5`, TroveManager `0xE47c…6bb0`, PriceFeed `0x86bC…9366`, HintHelpers `0x4e4c…CBF6`, SortedTroves `0x722E…68fA`, TigrisRouter `0xD245…8e03`, Voter `0x263F…5F0D`, BoostVoter `0x21d7…Bfd1`, veBTC `0x38E3…130a`, veMEZO `0xaCE8…111b`.

## Repository layout

```
contracts/
  src/<module>/        Solidity sources, one folder per module
  test/                Foundry tests (one suite per module + a registry check)
  script/              Deploy<Module>.s.sol, one script per module
  lib/forge-std/       vendored test library
web/
  src/App.tsx          shell: navigation, live status, wallet, activity log
  src/ui/kit.tsx       shared design system components
  src/modules/         one view per module, plus the overview
  src/modules/onchain.tsx  live panels that send real transactions
  src/lib/             chain reads (meridianChain.ts), transactions (tx.ts), procedural sound
```

## Run it

Requirements: Node 20+, npm, and [Foundry](https://book.getfoundry.sh/getting-started/installation).

Contracts:

```bash
cd contracts
forge build
forge test
```

Web app:

```bash
cd web
npm ci
npm run dev
```

Production build:

```bash
cd web
npm run build
```

The app needs no API keys. It reads Mezo Testnet through the public RPC and shows an offline snapshot if that RPC is unreachable.

## Deploy a module

Each script deploys one module against the Mezo Testnet core addresses hard-coded in the script. Use a Foundry keystore account funded with test BTC from https://faucet.test.mezo.org:

```bash
cd contracts
forge script script/DeployRoost.s.sol --rpc-url https://rpc.test.mezo.org --account <keystore-name> --broadcast
```

Replace `DeployRoost` with `DeployAutopay`, `DeployDrawdown`, `DeployChronos`, `DeployPegKeeper`, `DeployBackstop`, `DeployRelay` or `DeployKeeperGrid`.

## Known limitations

- Drawdown's payroll trove and streams can only be created by the treasury admin set at deployment; other wallets can only claim streams that pay them.
- Relay needs a veBTC or veMEZO lock owned by the connected wallet.
- You need test BTC (https://faucet.test.mezo.org) and test MUSD (borrow at https://testnet.mezo.org) in your wallet for the on-chain panels.
- Contracts are unaudited and deployed on testnet only.

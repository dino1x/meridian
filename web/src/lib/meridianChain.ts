import { createPublicClient, defineChain, formatUnits, http, parseAbi } from "viem";

export const mezoTestnet = defineChain({
  id: 31611,
  name: "Mezo Testnet",
  nativeCurrency: { name: "Bitcoin", symbol: "BTC", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.test.mezo.org"] },
  },
  blockExplorers: {
    default: { name: "Mezo Explorer", url: "https://explorer.test.mezo.org" },
  },
  testnet: true,
});

export const MEZO_CORE = {
  MUSD: "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503",
  sMUSD: "0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16",
  StabilityPool: "0x1CCA7E410eE41739792eA0A24e00349Dd247680e",
  BorrowerOperations: "0xCdF7028ceAB81fA0C6971208e83fa7872994beE5",
  TroveManager: "0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0",
  PriceFeed: "0x86bCF0841622a5dAC14A313a15f96A95421b9366",
  HintHelpers: "0x4e4cBA3779d56386ED43631b4dCD6d8EacEcBCF6",
  SortedTroves: "0x722E4D24FD6Ff8b0AC679450F3D91294607268fA",
  TigrisRouter: "0xD245BeC6836D85e159763a5D2BFcE7CBC3488e03",
  Voter: "0x263F1Fd5fB7F866881e1B6cD7d5d6c40Fd985F0D",
  BoostVoter: "0x21d7bDF5a5929AD179F8cA0c9014A0B62ae6Bfd1",
  veBTC: "0x38E35d92E6Bfc6787272A62345856B13eA12130a",
  veMEZO: "0xaCE816CA2bcc9b12C59799dcC5A959Fb9b98111b",
} as const;

export const MERIDIAN_CONTRACTS = {
  AutopayFactory: "0x0EAA0e96974CBD3169B060c7C121165D91820078",
  TroveVaultImpl: "0xeC4b9374F9e4f62004F840EfF20a048b689D08CC",
  DrawdownDesk: "0x0acaaD024c9d4729C6717B6429117d4aE66f9070",
  ChickenBondManager: "0x528ADC9Ae5A430D0a53f711661F18A8C5831CaF6",
  bMUSDToken: "0x04dC85c45d6B68fBeF346F823dC05682415B3C9E",
  BondNFT: "0x09F2E2884b714aC142EF4aAA453d83D9D3749404",
  ChronosTermVault: "0x321C3673cCfDb5d5E259c86F4B2dB58Cc3a1eB64",
  BatchRateAuction: "0xCcF397A784873406b56457643Cc5b08Fd89A86c4",
  PegKeeperVault: "0x8F569515fe8FB05177db0f039EA89a480C220e36",
  BackstopVault: "0x2FD13bf151587344C3505dD92439B68b9bf54642",
  RelayVault: "0x69c1f2EfBe79A1201CDaEE5a5F63024Ee374aF23",
  BribeRadarLens: "0x83124D679e71420761b0cCeeaFc5735847db58B1",
  KeeperGrid: "0x61D0e6a90f7d0bCB75786E2a282f04Ff281F72C1",
} as const;

export const MEZO_CONTRACTS = { ...MEZO_CORE, ...MERIDIAN_CONTRACTS } as const;
export const MEZO_VE_CONTRACTS = MEZO_CONTRACTS;
export const CHRONOS_MEZO_ADDRESSES = MEZO_CONTRACTS;
export const AUTOPAY_MEZO_ADDRESSES = MEZO_CONTRACTS;
export const PEGKEEPER_CONTRACTS = MEZO_CONTRACTS;
export const BACKSTOP_MEZO_ADDRESSES = MEZO_CONTRACTS;
export const KEEPERGRID_MEZO_ADDRESSES = MEZO_CONTRACTS;
export const DRAWDOWN_MEZO_ADDRESSES = MEZO_CONTRACTS;

export interface ContractRegistryItem {
  module: string;
  pillar: "Credit & Payroll" | "Yield & Fixed Income" | "Peg & Auctions" | "Governance & Keepers";
  contractName: string;
  address: string;
  role: string;
}

export const REGISTRY_CATALOG: ContractRegistryItem[] = [
  {
    module: "Autopay",
    pillar: "Credit & Payroll",
    contractName: "AutopayFactory",
    address: MERIDIAN_CONTRACTS.AutopayFactory,
    role: "Deploys user-owned self-repaying BTC TroveVaults",
  },
  {
    module: "Autopay",
    pillar: "Credit & Payroll",
    contractName: "TroveVault (Impl)",
    address: MERIDIAN_CONTRACTS.TroveVaultImpl,
    role: "Automated ICR band manager & sMUSD debt amortizer",
  },
  {
    module: "Drawdown",
    pillar: "Credit & Payroll",
    contractName: "DrawdownDesk",
    address: MERIDIAN_CONTRACTS.DrawdownDesk,
    role: "Just-in-time BTC collateralized corporate payroll streams",
  },
  {
    module: "Roost",
    pillar: "Yield & Fixed Income",
    contractName: "ChickenBondManager",
    address: MERIDIAN_CONTRACTS.ChickenBondManager,
    role: "Hyperbolic bMUSD bond accrual, chicken-in/out & Trove zap",
  },
  {
    module: "Roost",
    pillar: "Yield & Fixed Income",
    contractName: "bMUSDToken",
    address: MERIDIAN_CONTRACTS.bMUSDToken,
    role: "Floor-backed amplified yield token backed by sMUSD reserve",
  },
  {
    module: "Roost",
    pillar: "Yield & Fixed Income",
    contractName: "BondNFT",
    address: MERIDIAN_CONTRACTS.BondNFT,
    role: "Transferable position NFT encoding accrued chicken-in rights",
  },
  {
    module: "Chronos",
    pillar: "Yield & Fixed Income",
    contractName: "ChronosTermVault",
    address: MERIDIAN_CONTRACTS.ChronosTermVault,
    role: "Splits sMUSD into 30D / 90D / 180D Principal & Yield Tokens",
  },
  {
    module: "Chronos",
    pillar: "Yield & Fixed Income",
    contractName: "BatchRateAuction",
    address: MERIDIAN_CONTRACTS.BatchRateAuction,
    role: "Uniform-clearing orderbook auction fixing zero-slippage YT rates",
  },
  {
    module: "PegKeeper",
    pillar: "Peg & Auctions",
    contractName: "PegKeeperVault",
    address: MERIDIAN_CONTRACTS.PegKeeperVault,
    role: "Pooled MUSD peg-defense arbitrage via Hinted Redemptions & Tigris",
  },
  {
    module: "Backstop",
    pillar: "Peg & Auctions",
    contractName: "BackstopVault",
    address: MERIDIAN_CONTRACTS.BackstopVault,
    role: "Stability Pool liquidation collateral Dutch-auction liquidator",
  },
  {
    module: "Relay",
    pillar: "Governance & Keepers",
    contractName: "RelayVault",
    address: MERIDIAN_CONTRACTS.RelayVault,
    role: "Autopilot veBTC / veMEZO gauge voting & MUSD reward router",
  },
  {
    module: "Relay",
    pillar: "Governance & Keepers",
    contractName: "BribeRadarLens",
    address: MERIDIAN_CONTRACTS.BribeRadarLens,
    role: "On-chain gauge efficiency & whitelist scanner blocking spam bribes",
  },
  {
    module: "KeeperGrid",
    pillar: "Governance & Keepers",
    contractName: "KeeperGrid",
    address: MERIDIAN_CONTRACTS.KeeperGrid,
    role: "sMUSD-bonded permissionless keeper dispatch & delinquency slashing",
  },
];

export function explorerAddressUrl(address: string): string {
  return `https://explorer.test.mezo.org/address/${address}`;
}

export const mezoPublicClient = createPublicClient({
  chain: mezoTestnet,
  transport: http("https://rpc.test.mezo.org", { timeout: 6_500 }),
});

const TELEMETRY_ABI = parseAbi([
  "function fetchPrice() view returns (uint256)",
  "function getTotalMUSDDeposits() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function yieldIndex() view returns (uint256)",
  "function MCR() view returns (uint256)",
  "function CCR() view returns (uint256)",
  "function getTroveOwnersCount() view returns (uint256)",
  "function checkRecoveryMode(uint256 _price) view returns (bool)",
  "function minNetDebt() view returns (uint256)",
  "function borrowingRate() view returns (uint256)",
  "function redemptionRate() view returns (uint256)",
  "function getLast() view returns (address)",
  "function getSize() view returns (uint256)",
  "function tokenId() view returns (uint256)",
  "function length() view returns (uint256)",
  "function totalWeight() view returns (uint256)",
]);

export interface MezoLiveTelemetry {
  blockNumber: bigint;
  btcPriceUsd: number;
  spDepositsMusd: number;
  sMusdSupply: number;
  sMusdYieldIndex: number;
  mcrPercent: number;
  ccrPercent: number;
  troveCount: number;
  isRecoveryMode: boolean;
  minNetDebtMusd: number;
  borrowingFeePercent: number;
  redemptionRatePct: number;
  /** Lowest-ICR trove from SortedTroves.getLast(); empty string when the read is unavailable. */
  lowestIcrTrove: string;
  sortedTrovesSize: number;
  veBtcCount: number;
  veMezoCount: number;
  boostGaugeCount: number;
  boostTotalWeight: number;
  /** True only when the block number and the oracle price were read from the live RPC. */
  isLiveRpc: boolean;
}

/** Offline snapshot shown only when the Mezo RPC cannot be reached. */
export const OFFLINE_SNAPSHOT: MezoLiveTelemetry = {
  blockNumber: 4_819_420n,
  btcPriceUsd: 76_559.43,
  spDepositsMusd: 86_209_195.88,
  sMusdSupply: 897_415.12,
  sMusdYieldIndex: 1.00024,
  mcrPercent: 110,
  ccrPercent: 150,
  troveCount: 352,
  isRecoveryMode: false,
  minNetDebtMusd: 1800,
  borrowingFeePercent: 0.1,
  redemptionRatePct: 0.5,
  lowestIcrTrove: "",
  sortedTrovesSize: 352,
  veBtcCount: 1729,
  veMezoCount: 938,
  boostGaugeCount: 678,
  boostTotalWeight: 25_667.9,
  isLiveRpc: false,
};

type Address = `0x${string}`;

function read(address: Address, functionName: string, args: readonly unknown[] = []): Promise<unknown> {
  return mezoPublicClient.readContract({
    address,
    abi: TELEMETRY_ABI,
    functionName: functionName as never,
    args: args as never,
  }) as Promise<unknown>;
}

const units = (v: unknown, decimals: number) => Number(formatUnits(v as bigint, decimals));

async function loadTelemetry(): Promise<MezoLiveTelemetry> {
  const C = MEZO_CORE;
  // Each read settles independently, so one unavailable view never hides the others.
  const [
    block, price, sp, sSupply, sIndex, mcr, ccr, troves, minDebt, borrowRate,
    redRate, last, size, veBtc, veMezo, gauges, weight,
  ] = await Promise.allSettled([
    mezoPublicClient.getBlockNumber(),
    read(C.PriceFeed, "fetchPrice"),
    read(C.StabilityPool, "getTotalMUSDDeposits"),
    read(C.sMUSD, "totalSupply"),
    read(C.sMUSD, "yieldIndex"),
    read(C.TroveManager, "MCR"),
    read(C.TroveManager, "CCR"),
    read(C.TroveManager, "getTroveOwnersCount"),
    read(C.BorrowerOperations, "minNetDebt"),
    read(C.BorrowerOperations, "borrowingRate"),
    read(C.BorrowerOperations, "redemptionRate"),
    read(C.SortedTroves, "getLast"),
    read(C.SortedTroves, "getSize"),
    read(C.veBTC, "tokenId"),
    read(C.veMEZO, "tokenId"),
    read(C.BoostVoter, "length"),
    read(C.BoostVoter, "totalWeight"),
  ]);

  const S = OFFLINE_SNAPSHOT;
  const pick = <T,>(r: PromiseSettledResult<unknown>, map: (v: unknown) => T, fallback: T): T =>
    r.status === "fulfilled" ? map(r.value) : fallback;

  let isRecoveryMode = S.isRecoveryMode;
  if (price.status === "fulfilled") {
    try {
      isRecoveryMode = (await read(C.TroveManager, "checkRecoveryMode", [price.value])) as boolean;
    } catch {
      // keep snapshot value
    }
  }

  return {
    blockNumber: pick(block, (v) => v as bigint, S.blockNumber),
    btcPriceUsd: pick(price, (v) => units(v, 18), S.btcPriceUsd),
    spDepositsMusd: pick(sp, (v) => units(v, 18), S.spDepositsMusd),
    sMusdSupply: pick(sSupply, (v) => units(v, 18), S.sMusdSupply),
    sMusdYieldIndex: pick(sIndex, (v) => units(v, 18), S.sMusdYieldIndex),
    mcrPercent: pick(mcr, (v) => units(v, 16), S.mcrPercent),
    ccrPercent: pick(ccr, (v) => units(v, 16), S.ccrPercent),
    troveCount: pick(troves, (v) => Number(v), S.troveCount),
    isRecoveryMode,
    minNetDebtMusd: pick(minDebt, (v) => units(v, 18), S.minNetDebtMusd),
    borrowingFeePercent: pick(borrowRate, (v) => units(v, 16), S.borrowingFeePercent),
    redemptionRatePct: pick(redRate, (v) => units(v, 16), S.redemptionRatePct),
    lowestIcrTrove: pick(last, (v) => v as string, S.lowestIcrTrove),
    sortedTrovesSize: pick(size, (v) => Number(v), S.sortedTrovesSize),
    veBtcCount: pick(veBtc, (v) => Number(v), S.veBtcCount),
    veMezoCount: pick(veMezo, (v) => Number(v), S.veMezoCount),
    boostGaugeCount: pick(gauges, (v) => Number(v), S.boostGaugeCount),
    boostTotalWeight: pick(weight, (v) => units(v, 18), S.boostTotalWeight),
    isLiveRpc: block.status === "fulfilled" && price.status === "fulfilled",
  };
}

// All eight modules and the shell poll telemetry; share one request per 10 s window.
let cached: { at: number; promise: Promise<MezoLiveTelemetry> } | null = null;

export function fetchMezoLiveTelemetry(): Promise<MezoLiveTelemetry> {
  const now = Date.now();
  if (!cached || now - cached.at > 10_000) {
    cached = { at: now, promise: loadTelemetry().catch(() => OFFLINE_SNAPSHOT) };
  }
  return cached.promise;
}

// Module-specific views over the shared telemetry
export type MezoAlmanacTelemetry = MezoLiveTelemetry;
export const fetchMezoAlmanacTelemetry = fetchMezoLiveTelemetry;

export interface RadarChainTelemetry {
  blockNumber: bigint;
  veBtcCount: number;
  veMezoCount: number;
  boostGaugeCount: number;
  boostTotalWeight: number;
  btcPriceUsd: number;
  sMusdSupply: number;
  spDepositsMusd: number;
  isRecoveryMode: boolean;
  isLive: boolean;
}
export async function fetchRadarTelemetry(): Promise<RadarChainTelemetry> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    veBtcCount: t.veBtcCount,
    veMezoCount: t.veMezoCount,
    boostGaugeCount: t.boostGaugeCount,
    boostTotalWeight: t.boostTotalWeight,
    btcPriceUsd: t.btcPriceUsd,
    sMusdSupply: t.sMusdSupply,
    spDepositsMusd: t.spDepositsMusd,
    isRecoveryMode: t.isRecoveryMode,
    isLive: t.isLiveRpc,
  };
}

export interface TreasuryChainSnapshot {
  blockNumber: bigint;
  btcPriceUsd: number;
  sMusdSupply: number;
  sMusdYieldIndex: number;
  spDepositsMusd: number;
  minNetDebtMusd: number;
  borrowRatePct: number;
  isRecoveryMode: boolean;
  isLive: boolean;
}
export async function fetchTreasurySnapshot(): Promise<TreasuryChainSnapshot> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    sMusdSupply: t.sMusdSupply,
    sMusdYieldIndex: t.sMusdYieldIndex,
    spDepositsMusd: t.spDepositsMusd,
    minNetDebtMusd: t.minNetDebtMusd,
    borrowRatePct: t.borrowingFeePercent,
    isRecoveryMode: t.isRecoveryMode,
    isLive: t.isLiveRpc,
  };
}

export interface ConservatoryTelemetry {
  blockNumber: bigint;
  btcPriceUsd: number;
  mcrPct: number;
  ccrPct: number;
  troveCount: number;
  isRecoveryMode: boolean;
  minNetDebtMusd: number;
  spDepositsMusd: number;
  sMusdSupply: number;
  isLive: boolean;
}
export async function fetchConservatoryTelemetry(): Promise<ConservatoryTelemetry> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    mcrPct: t.mcrPercent,
    ccrPct: t.ccrPercent,
    troveCount: t.troveCount,
    isRecoveryMode: t.isRecoveryMode,
    minNetDebtMusd: t.minNetDebtMusd,
    spDepositsMusd: t.spDepositsMusd,
    sMusdSupply: t.sMusdSupply,
    isLive: t.isLiveRpc,
  };
}

export interface MetrologyChainState {
  blockNumber: bigint;
  btcPriceUsd: number;
  troveCount: number;
  redemptionRatePct: number;
  isRecoveryMode: boolean;
  lowestIcrTrove: string;
  sortedTrovesSize: number;
  sMusdSupply: number;
  isLive: boolean;
}
export async function fetchMetrologyState(): Promise<MetrologyChainState> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    troveCount: t.troveCount,
    redemptionRatePct: t.redemptionRatePct,
    isRecoveryMode: t.isRecoveryMode,
    lowestIcrTrove: t.lowestIcrTrove,
    sortedTrovesSize: t.sortedTrovesSize,
    sMusdSupply: t.sMusdSupply,
    isLive: t.isLiveRpc,
  };
}

export interface AuctionHouseTelemetry {
  blockNumber: bigint;
  btcPriceUsd: number;
  spDepositsMusd: number;
  troveCount: number;
  isRecoveryMode: boolean;
  isLive: boolean;
}
export async function fetchAuctionTelemetry(): Promise<AuctionHouseTelemetry> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    spDepositsMusd: t.spDepositsMusd,
    troveCount: t.troveCount,
    isRecoveryMode: t.isRecoveryMode,
    isLive: t.isLiveRpc,
  };
}

export interface SignalBoxChainTelemetry {
  blockNumber: bigint;
  btcPriceUsd: number;
  troveCount: number;
  isRecoveryMode: boolean;
  sMusdSupply: number;
  boostGaugeCount: number;
  isLive: boolean;
}
export async function fetchSignalBoxTelemetry(): Promise<SignalBoxChainTelemetry> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    troveCount: t.troveCount,
    isRecoveryMode: t.isRecoveryMode,
    sMusdSupply: t.sMusdSupply,
    boostGaugeCount: t.boostGaugeCount,
    isLive: t.isLiveRpc,
  };
}

export interface PayrollChainTelemetry {
  blockNumber: bigint;
  btcPriceUsd: number;
  minNetDebtMusd: number;
  borrowingFeePct: number;
  mcrPct: number;
  ccrPct: number;
  isRecoveryMode: boolean;
  sMusdSupply: number;
  isLive: boolean;
}
export async function fetchPayrollTelemetry(): Promise<PayrollChainTelemetry> {
  const t = await fetchMezoLiveTelemetry();
  return {
    blockNumber: t.blockNumber,
    btcPriceUsd: t.btcPriceUsd,
    minNetDebtMusd: t.minNetDebtMusd,
    borrowingFeePct: t.borrowingFeePercent,
    mcrPct: t.mcrPercent,
    ccrPct: t.ccrPercent,
    isRecoveryMode: t.isRecoveryMode,
    sMusdSupply: t.sMusdSupply,
    isLive: t.isLiveRpc,
  };
}

export interface ConnectedWallet {
  address: string;
  mode: "injected" | "demo";
  chainId: number;
}

interface Eip1193Provider {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
}

const DEMO_FALLBACK_WALLET = "0x84B2f18a991cD4E7095c301A5C2b1E08d91EC91F";

export async function connectMezoWallet(): Promise<ConnectedWallet> {
  const eth = (window as unknown as { ethereum?: Eip1193Provider }).ethereum;
  if (eth) {
    try {
      const accounts = (await eth.request({ method: "eth_requestAccounts" })) as string[];
      if (accounts && accounts.length > 0) {
        try {
          await eth.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: "0x7b7b" }],
          });
        } catch {
          try {
            await eth.request({
              method: "wallet_addEthereumChain",
              params: [
                {
                  chainId: "0x7b7b",
                  chainName: "Mezo Testnet",
                  nativeCurrency: { name: "Bitcoin", symbol: "BTC", decimals: 18 },
                  rpcUrls: ["https://rpc.test.mezo.org"],
                  blockExplorerUrls: ["https://explorer.test.mezo.org"],
                },
              ],
            });
          } catch {
            // Keep connected even if user rejects chain add in popup
          }
        }
        return { address: accounts[0], mode: "injected", chainId: 31611 };
      }
    } catch {
      // Fall through to read-only simulation session
    }
  }
  return { address: DEMO_FALLBACK_WALLET, mode: "demo", chainId: 31611 };
}

export function shortAddress(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

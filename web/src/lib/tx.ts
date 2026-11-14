// Real Mezo Testnet transactions through the user's injected wallet (EIP-1193).
import { useCallback, useState } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  formatUnits,
  parseAbi,
  parseUnits,
  type Abi,
} from "viem";
import { MEZO_CORE, MERIDIAN_CONTRACTS, mezoPublicClient, mezoTestnet } from "./meridianChain";

type Address = `0x${string}`;
interface Eip1193 {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
}

export const ABI = {
  erc20: parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
  ]),
  roost: parseAbi([
    "function createBond(uint256 musdAmount) returns (uint256)",
    "function chickenOut(uint256 bondId)",
    "function chickenIn(uint256 bondId) returns (uint256)",
    "function nextBondId() view returns (uint256)",
    "function bonds(uint256) view returns (address owner, uint256 musdPrincipal, uint256 startTime, uint256 endTime, uint256 claimedBMUSD, uint8 status)",
    "function calcAccruedBMUSD(uint256 bondId) view returns (uint256)",
  ]),
  vault: parseAbi([
    "function deposit(uint256 musdAmount) returns (uint256)",
    "function withdraw(uint256 shares) returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function totalSupply() view returns (uint256)",
    "function totalAssets() view returns (uint256)",
  ]),
  keeperGrid: parseAbi([
    "function postKeeperBond(uint256 musdAmount)",
    "function keepers(address) view returns (address operator, uint256 bondedMUSD, uint256 jobsCompleted, uint256 totalTipEarnedMUSD, uint256 timesSlashed, bool active)",
  ]),
  autopayFactory: parseAbi([
    "function plantVault(uint256 reserveBps, uint256 lowerBandICR, uint256 upperBandICR) returns (address)",
    "function userVault(address) view returns (address)",
  ]),
  troveVault: parseAbi([
    "function openSelfPayingTrove(uint256 totalMUSD, uint256 maxFeePercentage, address upperHint, address lowerHint) payable",
    "function harvestAndStrengthen(address upperHint, address lowerHint) returns (uint256, uint256)",
    "function rebalanceBand(uint256 maxFeePercentage, address upperHint, address lowerHint) returns (bool, uint256)",
    "function reserveBps() view returns (uint256)",
    "function lowerBandICR() view returns (uint256)",
    "function upperBandICR() view returns (uint256)",
    "function growthRingCount() view returns (uint256)",
  ]),
  troveManager: parseAbi([
    "function getEntireDebtAndColl(address) view returns (uint256 coll, uint256 principal, uint256 interest, uint256 pendingColl, uint256 pendingPrincipal, uint256 pendingInterest)",
  ]),
  hints: parseAbi([
    "function getApproxHint(uint256 _CR, uint256 _numTrials, uint256 _inputRandomSeed) view returns (address hintAddress, uint256 diff, uint256 latestRandomSeed)",
    "function findInsertPosition(uint256 _NICR, address _prevId, address _nextId) view returns (address, address)",
  ]),
  drawdown: parseAbi([
    "function treasuryAdmin() view returns (address)",
    "function troveInitialized() view returns (bool)",
    "function nextStreamId() view returns (uint256)",
    "function streams(uint256) view returns (uint256 streamId, address employer, address recipient, uint256 ratePerSecond, uint256 startTime, uint256 stopTime, uint256 totalClaimedMUSD, bool autoRouteToSMUSD, bool active)",
    "function claimablePaySlip(uint256 streamId) view returns (uint256)",
    "function initializeCorporateTrove(uint256 initialSeedMUSD, uint256 maxFeePercentage, address upperHint, address lowerHint) payable",
    "function createPayStream(address recipient, uint256 ratePerSecond, uint256 durationSeconds, bool autoRouteToSMUSD) returns (uint256)",
    "function claimPaySlip(uint256 streamId, uint256 maxFeePercentage, address upperHint, address lowerHint) returns (uint256, uint256)",
  ]),
  relay: parseAbi([
    "function registerFlightPlan(uint8 kind, uint256 tokenId, uint8 route, bool autoExtendLock) returns (uint256)",
    "function updateFlightPlan(uint256 planId, uint8 route, bool autoExtendLock, bool active)",
    "function tokenToPlanId(address ve, uint256 tokenId) view returns (uint256)",
    "function flightPlans(uint256) view returns (address owner, uint8 kind, uint256 tokenId, uint8 route, bool autoExtendLock, bool active, uint256 totalMUSDCompounded, uint256 lastExecutedEpoch)",
  ]),
  ve: parseAbi([
    "function ownerOf(uint256 tokenId) view returns (address)",
    "function getApproved(uint256 tokenId) view returns (address)",
    "function approve(address to, uint256 tokenId)",
  ]),
  chronos: parseAbi([
    "function mintPTAndYT(uint256 seriesId, uint256 musdAmount)",
    "function series(uint256) view returns (uint256 seriesId, uint256 duration, uint256 maturity, address pt, address yt, uint256 totalPrincipalMUSD, uint256 accYieldPerYT, bool active)",
  ]),
} as const;

export const ADDR = {
  MUSD: MEZO_CORE.MUSD as Address,
  roost: MERIDIAN_CONTRACTS.ChickenBondManager as Address,
  pegKeeper: MERIDIAN_CONTRACTS.PegKeeperVault as Address,
  backstop: MERIDIAN_CONTRACTS.BackstopVault as Address,
  keeperGrid: MERIDIAN_CONTRACTS.KeeperGrid as Address,
  chronos: MERIDIAN_CONTRACTS.ChronosTermVault as Address,
  autopayFactory: MERIDIAN_CONTRACTS.AutopayFactory as Address,
  drawdown: MERIDIAN_CONTRACTS.DrawdownDesk as Address,
  relay: MERIDIAN_CONTRACTS.RelayVault as Address,
  troveManager: MEZO_CORE.TroveManager as Address,
  hintHelpers: MEZO_CORE.HintHelpers as Address,
  sortedTroves: MEZO_CORE.SortedTroves as Address,
  veBTC: MEZO_CORE.veBTC as Address,
  veMEZO: MEZO_CORE.veMEZO as Address,
};

export const EXPLORER_TX = (hash: string) => `https://explorer.test.mezo.org/tx/${hash}`;
export const toWad = (amount: number) => parseUnits(amount.toString(), 18);
export const fromWad = (v: bigint) => Number(formatUnits(v, 18));

function provider(): Eip1193 {
  const eth = (window as unknown as { ethereum?: Eip1193 }).ethereum;
  if (!eth) throw new Error("No browser wallet found. Install a wallet to send transactions.");
  return eth;
}

/** Reads go through the wallet's own provider so they see the same chain the wallet writes to. */
export function walletReader() {
  return createPublicClient({ chain: mezoTestnet, transport: custom(provider()) });
}

export async function read<T>(address: Address, abi: Abi, functionName: string, args: readonly unknown[] = []): Promise<T> {
  return (await walletReader().readContract({ address, abi, functionName: functionName as never, args: args as never })) as T;
}

async function write(account: Address, address: Address, abi: Abi, functionName: string, args: readonly unknown[], value?: bigint) {
  const wallet = createWalletClient({ chain: mezoTestnet, transport: custom(provider()), account });
  const hash = await wallet.writeContract({ address, abi, functionName: functionName as never, args: args as never, chain: mezoTestnet, value } as never);
  const receipt = await walletReader().waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`Transaction reverted (${hash.slice(0, 10)}…)`);
  return hash;
}

/** Approves exactly `amount` MUSD for `spender` when the current allowance is lower. */
async function ensureMusdAllowance(account: Address, spender: Address, amount: bigint, onStep: (s: string) => void) {
  const current = await read<bigint>(ADDR.MUSD, ABI.erc20, "allowance", [account, spender]);
  if (current >= amount) return;
  onStep("Approve MUSD in your wallet…");
  await write(account, ADDR.MUSD, ABI.erc20, "approve", [spender, amount]);
}

export async function musdBalance(account: Address) {
  return fromWad(await read<bigint>(ADDR.MUSD, ABI.erc20, "balanceOf", [account]));
}

/** Approve MUSD if needed, then call `functionName` on `target`. Returns the final tx hash. */
export async function sendWithMusd(
  account: Address,
  target: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[],
  musdAmount: bigint,
  onStep: (s: string) => void
) {
  const bal = await read<bigint>(ADDR.MUSD, ABI.erc20, "balanceOf", [account]);
  if (bal < musdAmount) {
    throw new Error(`Not enough MUSD: you have ${fromWad(bal).toFixed(2)}, this needs ${fromWad(musdAmount).toFixed(2)}. Borrow MUSD at testnet.mezo.org.`);
  }
  await ensureMusdAllowance(account, target, musdAmount, onStep);
  onStep("Confirm the transaction in your wallet…");
  return write(account, target, abi, functionName, args);
}

export async function send(account: Address, target: Address, abi: Abi, functionName: string, args: readonly unknown[], onStep: (s: string) => void) {
  onStep("Confirm the transaction in your wallet…");
  return write(account, target, abi, functionName, args);
}

/* ---------- React hook: one transaction status per panel ---------- */

export type TxState =
  | { kind: "idle" }
  | { kind: "pending"; step: string }
  | { kind: "done"; label: string; hash: string }
  | { kind: "error"; message: string };

export function useTx(onLog?: (msg: string) => void) {
  const [state, setState] = useState<TxState>({ kind: "idle" });
  const run = useCallback(
    async (label: string, action: (onStep: (s: string) => void) => Promise<string>) => {
      try {
        setState({ kind: "pending", step: "Preparing…" });
        const hash = await action((step) => setState({ kind: "pending", step }));
        setState({ kind: "done", label, hash });
        onLog?.(`${label} confirmed on Mezo Testnet: ${hash.slice(0, 10)}…`);
        return true;
      } catch (e) {
        const err = e as { shortMessage?: string; message?: string };
        const message = (err.shortMessage || err.message || "Transaction failed").split("\n")[0];
        setState({ kind: "error", message });
        onLog?.(`${label} failed: ${message}`);
        return false;
      }
    },
    [onLog]
  );
  return { state, run, busy: state.kind === "pending" };
}

/** Sends a call with native BTC attached (Mezo's gas token), e.g. to open a trove. */
export async function sendWithBtc(
  account: Address,
  target: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[],
  btcWei: bigint,
  onStep: (s: string) => void
) {
  const bal = await walletReader().getBalance({ address: account });
  if (bal < btcWei) {
    throw new Error(`Not enough BTC: you have ${fromWad(bal).toFixed(4)}, this needs ${fromWad(btcWei).toFixed(4)} plus gas. Use faucet.test.mezo.org.`);
  }
  onStep("Confirm the transaction in your wallet…");
  return write(account, target, abi, functionName, args, btcWei);
}

export async function btcBalance(account: Address) {
  return fromWad(await walletReader().getBalance({ address: account }));
}

/** Insert-position hints for a trove with the given collateral and total debt (both 18-decimal).
 *  Hints only save gas: Mezo re-checks them, so on a slow RPC we fall back to zero hints after 6 s. */
export async function troveHints(collWei: bigint, totalDebtWei: bigint): Promise<[Address, Address]> {
  const zero = "0x0000000000000000000000000000000000000000" as Address;
  if (totalDebtWei === 0n) return [zero, zero];
  const nicr = (collWei * 10n ** 20n) / totalDebtWei;
  const lookup = (async () => {
    const approx = (await mezoPublicClient.readContract({
      address: ADDR.hintHelpers, abi: ABI.hints, functionName: "getApproxHint", args: [nicr, 50n, BigInt(Date.now() % 1_000_000)],
    })) as readonly [Address, bigint, bigint];
    return (await mezoPublicClient.readContract({
      address: ADDR.sortedTroves, abi: ABI.hints, functionName: "findInsertPosition", args: [nicr, approx[0], approx[0]],
    })) as [Address, Address];
  })();
  const timeout = new Promise<[Address, Address]>((resolve) => setTimeout(() => resolve([zero, zero]), 6_000));
  return Promise.race([lookup.catch(() => [zero, zero] as [Address, Address]), timeout]);
}

/** Total trove debt Mezo records for a borrow: amount + 0.1% fee + 200 MUSD gas compensation. */
export const troveDebt = (musdWei: bigint) => musdWei + musdWei / 1000n + 200n * 10n ** 18n;

// Live panels: the parts of each module that send real transactions to the deployed Meridian contracts.
import { useCallback, useEffect, useState } from 'react';
import { MERIDIAN_CONTRACTS, MEZO_CORE, mezoPublicClient, type ConnectedWallet } from '../lib/meridianChain';
import { parseAbi } from 'viem';
import { ABI, ADDR, btcBalance, fromWad, musdBalance, read, send, sendWithBtc, sendWithMusd, toWad, troveDebt, troveHints, useTx } from '../lib/tx';
import { Button, Field, KeyValue, LiveNote, NumberInput, Panel, Row, Table, TxStatus, fmt } from '../ui/kit';

type Address = `0x${string}`;
interface LiveProps {
  wallet?: ConnectedWallet | null;
  onLogEvent?: (msg: string) => void;
}

/** Shared wiring: is a real wallet connected, its MUSD balance, and a refresh tick after each transaction. */
function useLive(wallet?: ConnectedWallet | null) {
  const live = wallet?.mode === 'injected';
  const account = (live ? wallet!.address : null) as Address | null;
  const [musd, setMusd] = useState<number | null>(null);
  const [tick, setTick] = useState(0);
  const refresh = useCallback(() => setTick((t) => t + 1), []);
  useEffect(() => {
    if (!account) {
      setMusd(null);
      return;
    }
    musdBalance(account).then(setMusd).catch(() => setMusd(null));
  }, [account, tick]);
  return { live, account, musd, tick, refresh };
}

/* ---------------- Roost: create, chicken out, chicken in ---------------- */

interface ChainBond {
  id: number;
  principal: number;
  start: number;
  status: number; // 1 active, 2 chickened in, 3 chickened out
  accrued: number;
}
const BOND_STATUS = ['—', 'Incubating', 'Chickened in', 'Chickened out'];

export function RoostLive({ wallet, onLogEvent }: LiveProps) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [amount, setAmount] = useState(100);
  const [bonds, setBonds] = useState<ChainBond[]>([]);

  useEffect(() => {
    if (!account) return setBonds([]);
    (async () => {
      const next = Number(await read<bigint>(ADDR.roost, ABI.roost, 'nextBondId'));
      const ids = Array.from({ length: Math.min(next - 1, 300) }, (_, i) => next - 1 - i);
      const rows = await Promise.all(
        ids.map(async (id) => {
          const b = await read<readonly [Address, bigint, bigint, bigint, bigint, number]>(ADDR.roost, ABI.roost, 'bonds', [BigInt(id)]);
          if (b[0].toLowerCase() !== account.toLowerCase()) return null;
          const accrued = b[5] === 1 ? fromWad(await read<bigint>(ADDR.roost, ABI.roost, 'calcAccruedBMUSD', [BigInt(id)])) : fromWad(b[4]);
          return { id, principal: fromWad(b[1]), start: Number(b[2]), status: b[5], accrued };
        })
      );
      setBonds(rows.filter((r): r is ChainBond => r !== null));
    })().catch(() => setBonds([]));
  }, [account, tick]);

  return (
    <Panel eyebrow="On Mezo Testnet" title="Your bonds" glow>
      <LiveNote live={live} address={account} musd={musd} />
      <div className="mt-5 grid gap-6 lg:grid-cols-12">
        <div className="space-y-4 lg:col-span-4">
          <Field label="Bond principal" hint="Minimum 100 MUSD. Your MUSD goes into sMUSD from day one.">
            <NumberInput value={amount} onChange={setAmount} step={50} min={100} suffix="MUSD" />
          </Field>
          <Button
            variant="primary"
            className="w-full"
            disabled={!live || tx.busy || amount < 100}
            onClick={async () => {
              if (await tx.run(`Bond of ${amount} MUSD`, (s) => sendWithMusd(account!, ADDR.roost, ABI.roost, 'createBond', [toWad(amount)], toWad(amount), s))) refresh();
            }}
          >
            Create bond
          </Button>
          <TxStatus state={tx.state} />
        </div>
        <div className="lg:col-span-8">
          {bonds.length === 0 ? (
            <div className="rounded-xl border border-dashed border-line px-5 py-8 text-center text-[14px] text-muted">
              {live ? 'No bonds from this wallet yet.' : 'Your on-chain bonds will appear here.'}
            </div>
          ) : (
            <div className="rounded-xl border border-line">
              <Table head={['Bond', 'Principal', 'Accrued bMUSD', '']} cols="1fr 110px 130px 210px">
                {bonds.map((b) => (
                  <Row key={b.id} cols="1fr 110px 130px 210px">
                    <span>
                      #{b.id}
                      <span className="ml-2 text-[12px] text-faint">{BOND_STATUS[b.status]}</span>
                    </span>
                    <span className="text-right font-mono">{fmt(b.principal, 2)}</span>
                    <span className="text-right font-mono text-ice">{b.accrued.toFixed(4)}</span>
                    <span className="flex justify-end gap-2">
                      {b.status === 1 && (
                        <>
                          <Button size="sm" disabled={tx.busy} onClick={async () => { if (await tx.run(`Chicken out of bond #${b.id}`, (s) => send(account!, ADDR.roost, ABI.roost, 'chickenOut', [BigInt(b.id)], s))) refresh(); }}>
                            Chicken out
                          </Button>
                          <Button size="sm" variant="primary" disabled={tx.busy} onClick={async () => { if (await tx.run(`Chicken in bond #${b.id}`, (s) => send(account!, ADDR.roost, ABI.roost, 'chickenIn', [BigInt(b.id)], s))) refresh(); }}>
                            Chicken in
                          </Button>
                        </>
                      )}
                    </span>
                  </Row>
                ))}
              </Table>
            </div>
          )}
        </div>
      </div>
    </Panel>
  );
}

/* ---------------- Vault deposits: PegKeeper (pkMUSD) and Backstop (bstMUSD) ---------------- */

export function VaultLive({
  wallet,
  onLogEvent,
  vault,
  shareSymbol,
  title,
  blurb,
  allowWithdraw,
}: LiveProps & { vault: Address; shareSymbol: string; title: string; blurb: string; allowWithdraw?: boolean }) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [amount, setAmount] = useState(100);
  const [pos, setPos] = useState<{ shares: number; value: number; tvl: number } | null>(null);

  useEffect(() => {
    (async () => {
      if (!account) return setPos(null);
      const [shares, supply, assets] = await Promise.all([
        read<bigint>(vault, ABI.vault, 'balanceOf', [account]),
        read<bigint>(vault, ABI.vault, 'totalSupply'),
        read<bigint>(vault, ABI.vault, 'totalAssets'),
      ]);
      const value = supply > 0n ? fromWad((shares * assets) / supply) : 0;
      setPos({ shares: fromWad(shares), value, tvl: fromWad(assets) });
    })().catch(() => setPos(null));
  }, [account, tick, vault]);

  return (
    <Panel eyebrow="On Mezo Testnet" title={title} glow>
      <LiveNote live={live} address={account} musd={musd} />
      <div className="mt-5 grid gap-6 md:grid-cols-12">
        <p className="text-[14px] leading-relaxed text-muted md:col-span-4">{blurb}</p>
        <div className="space-y-3 md:col-span-4">
          <Field label="Amount">
            <NumberInput value={amount} onChange={setAmount} step={50} min={1} suffix="MUSD" />
          </Field>
          <div className="flex gap-2">
            <Button
              variant="primary"
              className="flex-1"
              disabled={!live || tx.busy || amount <= 0}
              onClick={async () => {
                if (await tx.run(`Deposit of ${amount} MUSD`, (s) => sendWithMusd(account!, vault, ABI.vault, 'deposit', [toWad(amount)], toWad(amount), s))) refresh();
              }}
            >
              Deposit
            </Button>
            {allowWithdraw && (
              <Button
                className="flex-1"
                disabled={!live || tx.busy || !pos || pos.shares <= 0}
                onClick={async () => {
                  const shares = await read<bigint>(vault, ABI.vault, 'balanceOf', [account!]);
                  if (await tx.run(`Withdrawal of all ${shareSymbol}`, (s) => send(account!, vault, ABI.vault, 'withdraw', [shares], s))) refresh();
                }}
              >
                Withdraw all
              </Button>
            )}
          </div>
          <TxStatus state={tx.state} />
        </div>
        <div className="md:col-span-4">
          <KeyValue k={`Your ${shareSymbol}`} v={pos ? fmt(pos.shares, 4) : '—'} />
          <KeyValue k="Worth" v={pos ? `${fmt(pos.value, 2)} MUSD` : '—'} tone="ice" />
          <KeyValue k="Vault assets" v={pos ? `${fmt(pos.tvl, 2)} MUSD` : '—'} />
        </div>
      </div>
    </Panel>
  );
}

/* ---------------- KeeperGrid: post a keeper bond ---------------- */

export function KeeperGridLive({ wallet, onLogEvent }: LiveProps) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [amount, setAmount] = useState(500);
  const [node, setNode] = useState<{ bonded: number; jobs: number; slashed: number; active: boolean } | null>(null);

  useEffect(() => {
    if (!account) return setNode(null);
    read<readonly [Address, bigint, bigint, bigint, bigint, boolean]>(ADDR.keeperGrid, ABI.keeperGrid, 'keepers', [account])
      .then((k) => setNode({ bonded: fromWad(k[1]), jobs: Number(k[2]), slashed: Number(k[4]), active: k[5] }))
      .catch(() => setNode(null));
  }, [account, tick]);

  const needed = Math.max(0, 500 - (node?.bonded ?? 0));
  return (
    <Panel eyebrow="On Mezo Testnet" title="Your keeper bond" glow>
      <LiveNote live={live} address={account} musd={musd} />
      <div className="mt-5 grid gap-6 md:grid-cols-12">
        <div className="space-y-3 md:col-span-6">
          <Field label="Add to bond" hint={needed > 0 ? `Your bond must reach at least 500 MUSD (${fmt(needed)} more).` : 'Bond is above the 500 MUSD minimum.'}>
            <NumberInput value={amount} onChange={setAmount} step={100} min={1} suffix="MUSD" />
          </Field>
          <Button
            variant="primary"
            className="w-full"
            disabled={!live || tx.busy || amount <= 0 || amount < needed}
            onClick={async () => {
              if (await tx.run(`Keeper bond of ${amount} MUSD`, (s) => sendWithMusd(account!, ADDR.keeperGrid, ABI.keeperGrid, 'postKeeperBond', [toWad(amount)], toWad(amount), s))) refresh();
            }}
          >
            Post bond
          </Button>
          <TxStatus state={tx.state} />
        </div>
        <div className="md:col-span-6">
          <KeyValue k="Bonded" v={node ? `${fmt(node.bonded, 2)} MUSD` : '—'} tone="ice" />
          <KeyValue k="Status" v={node ? (node.active ? 'Active keeper' : 'Not registered') : '—'} />
          <KeyValue k="Jobs completed" v={node ? String(node.jobs) : '—'} />
          <KeyValue k="Times slashed" v={node ? String(node.slashed) : '—'} />
        </div>
      </div>
    </Panel>
  );
}

/* ---------------- Chronos: strip MUSD into PT + YT ---------------- */

export function ChronosLive({ wallet, onLogEvent, tenorCode, chainSeriesId }: LiveProps & { tenorCode: string; chainSeriesId: number }) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [amount, setAmount] = useState(100);
  const [bal, setBal] = useState<{ pt: number; yt: number; maturity: number } | null>(null);

  useEffect(() => {
    if (!account) return setBal(null);
    (async () => {
      const s = await read<readonly [bigint, bigint, bigint, Address, Address, bigint, bigint, boolean]>(ADDR.chronos, ABI.chronos, 'series', [BigInt(chainSeriesId)]);
      const [pt, yt] = await Promise.all([read<bigint>(s[3], ABI.erc20, 'balanceOf', [account]), read<bigint>(s[4], ABI.erc20, 'balanceOf', [account])]);
      setBal({ pt: fromWad(pt), yt: fromWad(yt), maturity: Number(s[2]) });
    })().catch(() => setBal(null));
  }, [account, tick, chainSeriesId]);

  return (
    <Panel eyebrow="On Mezo Testnet" title={`Strip MUSD into ${tenorCode} PT + YT`} glow>
      <LiveNote live={live} address={account} musd={musd} />
      <div className="mt-5 grid gap-6 md:grid-cols-12">
        <div className="space-y-3 md:col-span-6">
          <Field label="Amount" hint="You receive the same amount of principal tokens and yield tokens.">
            <NumberInput value={amount} onChange={setAmount} step={50} min={1} suffix="MUSD" />
          </Field>
          <Button
            variant="primary"
            className="w-full"
            disabled={!live || tx.busy || amount <= 0}
            onClick={async () => {
              if (await tx.run(`Strip of ${amount} MUSD (${tenorCode})`, (s) => sendWithMusd(account!, ADDR.chronos, ABI.chronos, 'mintPTAndYT', [BigInt(chainSeriesId), toWad(amount)], toWad(amount), s))) refresh();
            }}
          >
            Strip
          </Button>
          <TxStatus state={tx.state} />
        </div>
        <div className="md:col-span-6">
          <KeyValue k={`Your PT-MUSD · ${tenorCode}`} v={bal ? fmt(bal.pt, 4) : '—'} tone="ice" />
          <KeyValue k={`Your YT-MUSD · ${tenorCode}`} v={bal ? fmt(bal.yt, 4) : '—'} />
          <KeyValue k="Matures" v={bal ? new Date(bal.maturity * 1000).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'} />
        </div>
      </div>
    </Panel>
  );
}

/* ---------------- Protocol figures read from the deployed contracts (no wallet needed) ---------------- */

const PUBLIC_ABI = parseAbi([
  'function pendingBucketMUSD() view returns (uint256)',
  'function reserveBucketMUSD() view returns (uint256)',
  'function permanentBucketMUSD() view returns (uint256)',
  'function nextBondId() view returns (uint256)',
  'function redemptionPrice() view returns (uint256)',
  'function totalSupply() view returns (uint256)',
  'function totalAssets() view returns (uint256)',
  'function reportsLength() view returns (uint256)',
  'function nextLotId() view returns (uint256)',
  'function activeKeepersCount() view returns (uint256)',
  'function allVaultsLength() view returns (uint256)',
  'function troveInitialized() view returns (bool)',
  'function nextStreamId() view returns (uint256)',
  'function getEntireDebtAndColl(address) view returns (uint256, uint256, uint256, uint256, uint256, uint256)',
  'function series(uint256) view returns (uint256 seriesId, uint256 duration, uint256 maturity, address pt, address yt, uint256 totalPrincipalMUSD, uint256 accYieldPerYT, bool active)',
]);

async function pub<T>(address: string, functionName: string, args: readonly unknown[] = []): Promise<T | null> {
  try {
    return (await mezoPublicClient.readContract({ address: address as Address, abi: PUBLIC_ABI, functionName: functionName as never, args: args as never })) as T;
  } catch {
    return null;
  }
}
const w = (v: bigint | null) => (v == null ? null : fromWad(v));

export interface ProtocolStats {
  roost: { bonds: number | null; pending: number | null; reserve: number | null; permanent: number | null; bMusdSupply: number | null; redemptionPrice: number | null };
  pegKeeper: { assets: number | null; sharePrice: number | null; redemptions: number | null };
  backstop: { assets: number | null; sharePrice: number | null; lots: number | null };
  keeperGrid: { activeKeepers: number | null };
  chronos: { lockedBySeries: (number | null)[] };
  autopay: { vaults: number | null };
  drawdown: { initialized: boolean | null; streams: number | null; coll: number | null; debt: number | null };
}

async function loadStats(): Promise<ProtocolStats> {
  const M = MERIDIAN_CONTRACTS;
  const [pending, reserve, permanent, nextBond, redPrice, bSupply, pkA, pkS, pkR, bsA, bsS, nextLot, keepers, s1, s2, s3] = await Promise.all([
    pub<bigint>(M.ChickenBondManager, 'pendingBucketMUSD'),
    pub<bigint>(M.ChickenBondManager, 'reserveBucketMUSD'),
    pub<bigint>(M.ChickenBondManager, 'permanentBucketMUSD'),
    pub<bigint>(M.ChickenBondManager, 'nextBondId'),
    pub<bigint>(M.ChickenBondManager, 'redemptionPrice'),
    pub<bigint>(M.bMUSDToken, 'totalSupply'),
    pub<bigint>(M.PegKeeperVault, 'totalAssets'),
    pub<bigint>(M.PegKeeperVault, 'totalSupply'),
    pub<bigint>(M.PegKeeperVault, 'reportsLength'),
    pub<bigint>(M.BackstopVault, 'totalAssets'),
    pub<bigint>(M.BackstopVault, 'totalSupply'),
    pub<bigint>(M.BackstopVault, 'nextLotId'),
    pub<bigint>(M.KeeperGrid, 'activeKeepersCount'),
    ...[1, 2, 3].map((id) => pub<readonly unknown[]>(M.ChronosTermVault, 'series', [BigInt(id)])),
  ]);
  const [vaults, ddInit, ddNext, ddTrove] = await Promise.all([
    pub<bigint>(M.AutopayFactory, 'allVaultsLength'),
    pub<boolean>(M.DrawdownDesk, 'troveInitialized'),
    pub<bigint>(M.DrawdownDesk, 'nextStreamId'),
    pub<readonly bigint[]>(MEZO_CORE.TroveManager, 'getEntireDebtAndColl', [M.DrawdownDesk]),
  ]);
  const price = (a: bigint | null, s: bigint | null) => (a != null && s != null && s > 0n ? Number((a * 10n ** 18n) / s) / 1e18 : s === 0n ? 1 : null);
  return {
    roost: {
      bonds: nextBond == null ? null : Number(nextBond) - 1,
      pending: w(pending),
      reserve: w(reserve),
      permanent: w(permanent),
      bMusdSupply: w(bSupply),
      redemptionPrice: w(redPrice),
    },
    pegKeeper: { assets: w(pkA), sharePrice: price(pkA, pkS), redemptions: pkR == null ? null : Number(pkR) },
    backstop: { assets: w(bsA), sharePrice: price(bsA, bsS), lots: nextLot == null ? null : Number(nextLot) - 1 },
    keeperGrid: { activeKeepers: keepers == null ? null : Number(keepers) },
    chronos: { lockedBySeries: [s1, s2, s3].map((s) => (s ? fromWad(s[5] as bigint) : null)) },
    autopay: { vaults: vaults == null ? null : Number(vaults) },
    drawdown: {
      initialized: ddInit,
      streams: ddNext == null ? null : Number(ddNext) - 1,
      coll: ddTrove ? fromWad(ddTrove[0]) : null,
      debt: ddTrove ? fromWad(ddTrove[1] + ddTrove[2]) : null,
    },
  };
}

/** Live protocol figures for module headers, refreshed every 20 s. */
export function useProtocolStats() {
  const [stats, setStats] = useState<ProtocolStats | null>(null);
  useEffect(() => {
    let alive = true;
    const load = () => loadStats().then((s) => alive && setStats(s)).catch(() => {});
    load();
    const id = window.setInterval(load, 20_000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, []);
  return stats;
}

/** Formats a live figure, or a dash while it loads or if the read failed. */
export const live = (v: number | null | undefined, d = 0, suffix = '') => (v == null ? '—' : `${fmt(v, d)}${suffix}`);

/* ---------------- Autopay: plant a vault, open its self-paying trove, harvest, rebalance ---------------- */

const ZERO = '0x0000000000000000000000000000000000000000';

export function AutopayLive({ wallet, onLogEvent }: LiveProps) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [btc, setBtc] = useState<number | null>(null);
  const [vault, setVault] = useState<Address | null>(null);
  const [trove, setTrove] = useState<{ coll: number; debt: number; rings: number; lower: number; upper: number } | null>(null);
  const [reservePct, setReservePct] = useState(30);
  const [collBtc, setCollBtc] = useState(0.04);
  const [borrow, setBorrow] = useState(1800);

  useEffect(() => {
    if (!account) {
      setVault(null);
      setTrove(null);
      setBtc(null);
      return;
    }
    (async () => {
      setBtc(await btcBalance(account));
      const v = await read<Address>(ADDR.autopayFactory, ABI.autopayFactory, 'userVault', [account]);
      if (v === ZERO) return setVault(null);
      setVault(v);
      const [t, rings, lo, up] = await Promise.all([
        read<readonly bigint[]>(ADDR.troveManager, ABI.troveManager, 'getEntireDebtAndColl', [v]),
        read<bigint>(v, ABI.troveVault, 'growthRingCount'),
        read<bigint>(v, ABI.troveVault, 'lowerBandICR'),
        read<bigint>(v, ABI.troveVault, 'upperBandICR'),
      ]);
      setTrove({ coll: fromWad(t[0]), debt: fromWad(t[1] + t[2]), rings: Number(rings), lower: fromWad(lo) * 100, upper: fromWad(up) * 100 });
    })().catch(() => {});
  }, [account, tick]);

  const hintsForVault = async () => {
    const t = await read<readonly bigint[]>(ADDR.troveManager, ABI.troveManager, 'getEntireDebtAndColl', [vault!]);
    return troveHints(t[0], t[1] + t[2]);
  };

  return (
    <Panel eyebrow="On Mezo Testnet" title="Your Autopay vault" glow>
      <LiveNote live={live} address={account} musd={musd} />
      {live && btc != null && <div className="mt-1 font-mono text-[12px] text-faint">BTC balance {btc.toFixed(5)}</div>}
      {!vault ? (
        <div className="mt-5 grid gap-6 md:grid-cols-12">
          <p className="text-[14px] leading-relaxed text-muted md:col-span-4">
            Step 1 plants your own vault. Step 2 opens its trove: it borrows MUSD against your BTC, sends you the spendable part and puts the reserve into sMUSD and the Stability Pool.
          </p>
          <div className="space-y-3 md:col-span-4">
            <Field label="Growth reserve" hint="Share of borrowed MUSD kept in sMUSD + Stability Pool">
              <NumberInput value={reservePct} onChange={setReservePct} step={5} min={5} suffix="%" />
            </Field>
            <Button
              variant="primary"
              className="w-full"
              disabled={!live || tx.busy || reservePct <= 0 || reservePct > 80}
              onClick={async () => {
                if (await tx.run('Autopay vault', (s) => send(account!, ADDR.autopayFactory, ABI.autopayFactory, 'plantVault', [BigInt(reservePct * 100), 135n * 10n ** 16n, 220n * 10n ** 16n], s))) refresh();
              }}
            >
              1 · Plant vault (band 135%–220%)
            </Button>
            <TxStatus state={tx.state} />
          </div>
          <div className="md:col-span-4 text-[13px] text-faint">Step 2 appears here once the vault exists.</div>
        </div>
      ) : (
        <div className="mt-5 grid gap-6 md:grid-cols-12">
          <div className="md:col-span-4">
            <KeyValue k="Vault" v={`${vault.slice(0, 6)}…${vault.slice(-4)}`} />
            <KeyValue k="Collateral" v={trove ? `${trove.coll.toFixed(4)} BTC` : '—'} />
            <KeyValue k="Debt" v={trove ? `${fmt(trove.debt, 2)} MUSD` : '—'} tone="ice" />
            <KeyValue k="Band" v={trove ? `${trove.lower.toFixed(0)}% – ${trove.upper.toFixed(0)}%` : '—'} />
            <KeyValue k="Growth rings" v={trove ? String(trove.rings) : '—'} />
          </div>
          {trove && trove.debt === 0 ? (
            <div className="space-y-3 md:col-span-8">
              <div className="grid grid-cols-2 gap-3">
                <Field label="BTC collateral">
                  <NumberInput value={collBtc} onChange={setCollBtc} step="0.005" min={0} suffix="BTC" />
                </Field>
                <Field label="Borrow" hint="Minimum 1,800 MUSD">
                  <NumberInput value={borrow} onChange={setBorrow} step={100} min={1800} suffix="MUSD" />
                </Field>
              </div>
              <Button
                variant="primary"
                className="w-full"
                disabled={!live || tx.busy || borrow < 1800 || collBtc <= 0}
                onClick={async () => {
                  const coll = toWad(collBtc);
                  const debt = toWad(borrow);
                  if (await tx.run(`Self-paying trove (${borrow} MUSD)`, async (s) => { s('Finding trove position…'); const [up, lo] = await troveHints(coll, troveDebt(debt)); return sendWithBtc(account!, vault, ABI.troveVault, 'openSelfPayingTrove', [debt, 0n, up, lo], coll, s); })) refresh();
                }}
              >
                2 · Open self-paying trove
              </Button>
              <TxStatus state={tx.state} />
            </div>
          ) : (
            <div className="space-y-3 md:col-span-8">
              <p className="text-[14px] text-muted">Anyone can harvest: sMUSD yield repays the debt and Stability Pool BTC gains are added as collateral. Rebalancing acts only when the ratio leaves the band.</p>
              <div className="flex flex-wrap gap-2">
                <Button
                  variant="primary"
                  disabled={!live || tx.busy}
                  onClick={async () => {
                    if (await tx.run('Harvest & compound', async (s) => { s('Finding trove position…'); const [up, lo] = await hintsForVault(); return send(account!, vault, ABI.troveVault, 'harvestAndStrengthen', [up, lo], s); })) refresh();
                  }}
                >
                  Harvest & compound
                </Button>
                <Button
                  disabled={!live || tx.busy}
                  onClick={async () => {
                    if (await tx.run('Band rebalance', async (s) => { s('Finding trove position…'); const [up, lo] = await hintsForVault(); return send(account!, vault, ABI.troveVault, 'rebalanceBand', [0n, up, lo], s); })) refresh();
                  }}
                >
                  Rebalance band
                </Button>
              </div>
              <TxStatus state={tx.state} />
            </div>
          )}
        </div>
      )}
    </Panel>
  );
}

/* ---------------- Drawdown: admin opens the payroll trove and streams; recipients claim ---------------- */

interface ChainStream {
  id: number;
  employer: string;
  recipient: string;
  perMonth: number;
  claimed: number;
  claimable: number;
  active: boolean;
}

export function DrawdownLive({ wallet, onLogEvent }: LiveProps) {
  const { live, account, musd, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [desk, setDesk] = useState<{ admin: string; initialized: boolean; coll: number; debt: number } | null>(null);
  const [streams, setStreams] = useState<ChainStream[]>([]);
  const [seedBtc, setSeedBtc] = useState(0.04);
  const [seedMusd, setSeedMusd] = useState(1800);
  const [recipient, setRecipient] = useState('');
  const [monthly, setMonthly] = useState(300);
  const [days, setDays] = useState(30);

  useEffect(() => {
    (async () => {
      const [admin, initialized, next, t] = await Promise.all([
        pub<string>(ADDR.drawdown, 'treasuryAdmin'),
        pub<boolean>(ADDR.drawdown, 'troveInitialized'),
        pub<bigint>(ADDR.drawdown, 'nextStreamId'),
        mezoPublicClient.readContract({ address: ADDR.troveManager, abi: ABI.troveManager, functionName: 'getEntireDebtAndColl', args: [ADDR.drawdown] }).catch(() => null),
      ]);
      setDesk({ admin: admin ?? '', initialized: !!initialized, coll: t ? fromWad(t[0]) : 0, debt: t ? fromWad(t[1] + t[2]) : 0 });
      const n = next == null ? 0 : Number(next) - 1;
      const rows = await Promise.all(
        Array.from({ length: Math.min(n, 100) }, async (_, i) => {
          const id = n - i;
          const s = (await mezoPublicClient.readContract({ address: ADDR.drawdown, abi: ABI.drawdown, functionName: 'streams', args: [BigInt(id)] })) as readonly [bigint, Address, Address, bigint, bigint, bigint, bigint, boolean, boolean];
          const claimable = (await mezoPublicClient.readContract({ address: ADDR.drawdown, abi: ABI.drawdown, functionName: 'claimablePaySlip', args: [BigInt(id)] })) as bigint;
          return { id, employer: s[1], recipient: s[2], perMonth: fromWad(s[3] * 2_592_000n), claimed: fromWad(s[6]), claimable: fromWad(claimable), active: s[8] };
        })
      );
      setStreams(rows);
    })().catch(() => {});
  }, [tick]);

  const isAdmin = !!account && !!desk && desk.admin.toLowerCase() === account.toLowerCase();
  const mine = streams.filter((s) => account && (s.recipient.toLowerCase() === account.toLowerCase() || s.employer.toLowerCase() === account.toLowerCase()));

  return (
    <Panel eyebrow="On Mezo Testnet" title="Payroll desk" glow>
      <LiveNote live={live} address={account} musd={musd} />
      <div className="mt-5 grid gap-6 md:grid-cols-12">
        <div className="md:col-span-4">
          <KeyValue k="Desk trove" v={desk ? (desk.initialized ? 'Open' : 'Not opened yet') : '—'} tone={desk?.initialized ? 'pos' : undefined} />
          <KeyValue k="Collateral" v={desk ? `${desk.coll.toFixed(4)} BTC` : '—'} />
          <KeyValue k="Drawn debt" v={desk ? `${fmt(desk.debt, 2)} MUSD` : '—'} />
          <KeyValue k="Streams" v={String(streams.length)} />
          <KeyValue k="Treasury admin" v={desk?.admin ? `${desk.admin.slice(0, 6)}…${desk.admin.slice(-4)}` : '—'} />
        </div>

        <div className="space-y-3 md:col-span-8">
          {isAdmin && !desk?.initialized && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <Field label="BTC collateral"><NumberInput value={seedBtc} onChange={setSeedBtc} step="0.005" suffix="BTC" /></Field>
                <Field label="Seed buffer" hint="Minimum 1,800 MUSD, parked in sMUSD"><NumberInput value={seedMusd} onChange={setSeedMusd} step={100} suffix="MUSD" /></Field>
              </div>
              <Button
                variant="primary"
                className="w-full"
                disabled={!live || tx.busy || seedMusd < 1800}
                onClick={async () => {
                  const coll = toWad(seedBtc);
                  if (await tx.run('Payroll trove', async (s) => { s('Finding trove position…'); const [up, lo] = await troveHints(coll, troveDebt(toWad(seedMusd))); return sendWithBtc(account!, ADDR.drawdown, ABI.drawdown, 'initializeCorporateTrove', [toWad(seedMusd), 0n, up, lo], coll, s); })) refresh();
                }}
              >
                Open the payroll trove
              </Button>
            </>
          )}
          {isAdmin && desk?.initialized && (
            <>
              <Field label="Recipient address"><input className="field" value={recipient} placeholder="0x…" onChange={(e) => setRecipient(e.target.value.trim())} /></Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Salary"><NumberInput value={monthly} onChange={setMonthly} step={50} suffix="MUSD/MO" /></Field>
                <Field label="Duration"><NumberInput value={days} onChange={setDays} step={1} min={1} suffix="DAYS" /></Field>
              </div>
              <Button
                variant="primary"
                className="w-full"
                disabled={!live || tx.busy || !/^0x[0-9a-fA-F]{40}$/.test(recipient) || monthly <= 0 || days <= 0}
                onClick={async () => {
                  const rate = toWad(monthly) / 2_592_000n;
                  if (await tx.run('Pay stream', (s) => send(account!, ADDR.drawdown, ABI.drawdown, 'createPayStream', [recipient as Address, rate, BigInt(days * 86400), false], s))) refresh();
                }}
              >
                Create pay stream
              </Button>
            </>
          )}
          {!isAdmin && (
            <p className="text-[14px] leading-relaxed text-muted">
              Only the treasury admin can open the payroll trove and create streams. If a stream pays your address it appears below, and you can claim it: the desk borrows exactly the vested MUSD at that moment.
            </p>
          )}
          {mine.length > 0 && (
            <div className="rounded-xl border border-line">
              <Table head={['Stream', 'Salary / month', 'Claimable', '']} cols="1fr 120px 110px 100px">
                {mine.map((s) => (
                  <Row key={s.id} cols="1fr 120px 110px 100px">
                    <span>#{s.id} <span className="text-[12px] text-faint">to {s.recipient.slice(0, 6)}…</span></span>
                    <span className="text-right font-mono">{fmt(s.perMonth, 2)}</span>
                    <span className="text-right font-mono text-ice">{s.claimable.toFixed(4)}</span>
                    <span className="flex justify-end">
                      {account && s.recipient.toLowerCase() === account.toLowerCase() && (
                        <Button size="sm" variant="primary" disabled={!live || tx.busy || s.claimable <= 0}
                          onClick={async () => {
                            if (await tx.run(`Pay slip #${s.id}`, async (st) => {
                              st('Finding trove position…');
                              const t = await read<readonly bigint[]>(ADDR.troveManager, ABI.troveManager, 'getEntireDebtAndColl', [ADDR.drawdown]);
                              const [up, lo] = await troveHints(t[0], t[1] + t[2] + toWad(s.claimable));
                              return send(account!, ADDR.drawdown, ABI.drawdown, 'claimPaySlip', [BigInt(s.id), 0n, up, lo], st);
                            })) refresh();
                          }}>
                          Claim
                        </Button>
                      )}
                    </span>
                  </Row>
                ))}
              </Table>
            </div>
          )}
          <TxStatus state={tx.state} />
        </div>
      </div>
    </Panel>
  );
}

/* ---------------- Relay: approve the vault on your veBTC / veMEZO lock and register a plan ---------------- */

const ROUTES = ['Compound into sMUSD', 'Deposit to Stability Pool', 'Repay my trove debt'];

export function RelayLive({ wallet, onLogEvent }: LiveProps) {
  const { live, account, tick, refresh } = useLive(wallet);
  const tx = useTx(onLogEvent);
  const [kind, setKind] = useState<0 | 1>(0);
  const [tokenId, setTokenId] = useState(0);
  const [route, setRoute] = useState<0 | 1 | 2>(0);
  const [check, setCheck] = useState<{ owner: string | null; approved: boolean; planId: number; plan: { route: number; active: boolean; compounded: number } | null } | null>(null);

  const ve = kind === 0 ? ADDR.veBTC : ADDR.veMEZO;
  useEffect(() => {
    if (!account || tokenId <= 0) return setCheck(null);
    (async () => {
      const owner = await read<Address>(ve, ABI.ve, 'ownerOf', [BigInt(tokenId)]).catch(() => null);
      const approvedTo = await read<Address>(ve, ABI.ve, 'getApproved', [BigInt(tokenId)]).catch(() => ZERO);
      const planId = Number(await read<bigint>(ADDR.relay, ABI.relay, 'tokenToPlanId', [ve, BigInt(tokenId)]));
      let plan = null;
      if (planId > 0) {
        const p = await read<readonly [Address, number, bigint, number, boolean, boolean, bigint, bigint]>(ADDR.relay, ABI.relay, 'flightPlans', [BigInt(planId)]);
        plan = { route: p[3], active: p[5], compounded: fromWad(p[6]) };
      }
      setCheck({ owner, approved: approvedTo.toLowerCase() === ADDR.relay.toLowerCase(), planId, plan });
    })().catch(() => setCheck(null));
  }, [account, tokenId, kind, tick, ve]);

  const ownsIt = !!check?.owner && !!account && check.owner.toLowerCase() === account.toLowerCase();
  const name = kind === 0 ? 'veBTC' : 'veMEZO';

  return (
    <Panel eyebrow="On Mezo Testnet" title="Relay your lock" glow>
      <LiveNote live={live} address={account} />
      <div className="mt-5 grid gap-6 md:grid-cols-12">
        <div className="space-y-3 md:col-span-5">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Lock type">
              <select className="field" value={kind} onChange={(e) => setKind(Number(e.target.value) as 0 | 1)}>
                <option value={0}>veBTC</option>
                <option value={1}>veMEZO</option>
              </select>
            </Field>
            <Field label="Token ID"><NumberInput value={tokenId} onChange={setTokenId} min={0} /></Field>
          </div>
          <Field label="Send rewards to">
            <select className="field" value={route} onChange={(e) => setRoute(Number(e.target.value) as 0 | 1 | 2)}>
              {ROUTES.map((r, i) => <option key={r} value={i}>{r}</option>)}
            </select>
          </Field>
        </div>
        <div className="space-y-3 md:col-span-7">
          <div className="text-[14px] text-muted">
            {!live
              ? `Connect the wallet that holds your ${name} lock.`
              : tokenId <= 0
                ? `Enter the token ID of a ${name} lock you own (create one at testnet.mezo.org).`
                : check == null
                  ? 'Checking the lock…'
                  : !ownsIt
                    ? `${name} #${tokenId} is not owned by this wallet.`
                    : check.plan
                      ? `${name} #${tokenId} is registered as plan #${check.planId} (${ROUTES[check.plan.route]}, ${check.plan.active ? 'active' : 'paused'}). ${fmt(check.plan.compounded, 2)} MUSD compounded so far.`
                      : `${name} #${tokenId} is yours. ${check.approved ? 'RelayVault is approved; register the plan.' : 'Approve RelayVault as operator, then register.'}`}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={!live || tx.busy || !ownsIt || !!check?.approved}
              onClick={async () => { if (await tx.run(`Operator approval on ${name} #${tokenId}`, (s) => send(account!, ve, ABI.ve, 'approve', [ADDR.relay, BigInt(tokenId)], s))) refresh(); }}
            >
              1 · Approve RelayVault
            </Button>
            <Button
              variant="primary"
              disabled={!live || tx.busy || !ownsIt || !check?.approved}
              onClick={async () => { if (await tx.run(`Relay plan for ${name} #${tokenId}`, (s) => send(account!, ADDR.relay, ABI.relay, 'registerFlightPlan', [kind, BigInt(tokenId), route, true], s))) refresh(); }}
            >
              2 · {check?.plan ? 'Update plan' : 'Register plan'}
            </Button>
          </div>
          <p className="text-[12px] text-faint">Your lock never leaves your wallet. Revoke the approval any time from the ve contract.</p>
          <TxStatus state={tx.state} />
        </div>
      </div>
    </Panel>
  );
}

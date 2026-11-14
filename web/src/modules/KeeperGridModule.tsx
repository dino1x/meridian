import React, { useEffect, useRef, useState } from 'react';
import { Button, EXPLORER, Field, NumberInput, PageHeader, Panel, Row, Segmented, StatusPill, Table, fmt , SimDivider } from '../ui/kit';
import { KeeperGridLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  ArrowUpRight,
  Radio,
  ShieldCheck,
  Sliders,
  Zap,
} from 'lucide-react';
import {
  fetchSignalBoxTelemetry,
  KEEPERGRID_MEZO_ADDRESSES,
  SignalBoxChainTelemetry,
} from '../lib/meridianChain';
import { signalAudio } from '../lib/signalBoxAudio';

type JobModuleType =
  | 'BATCH_LIQUIDATION'
  | 'HINTED_REDEMPTION'
  | 'TROVE_TOPUP'
  | 'GAUGE_EPOCH_POKE';

interface DispatchJob {
  jobId: number;
  module: JobModuleType;
  targetContract: string;
  assignedKeeper: string;
  slotDeadlineDeltaBlocks: number; // Negative = delinquent (eligible for 10% bond slash!)
  bountyMusd: number;
  status: 'SLOT_ACTIVE' | 'DELINQUENT_SLASHABLE' | 'CLEARED';
}

interface KeeperNode {
  id: string;
  operator: string;
  bondedSMusd: number;
  accruedSMusdYield: number;
  jobsExecuted: number;
  slashedCount: number;
}

export function KeeperGridModule({ onLogEvent, walletAddress = null, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<SignalBoxChainTelemetry>({
    blockNumber: 4_813_120n,
    btcPriceUsd: 76559.43,
    troveCount: 352,
    isRecoveryMode: false,
    sMusdSupply: 897415.12,
    boostGaugeCount: 678,
    isLive: false,
  });

  const [newBondMusd, setNewBondMusd] = useState<number>(3000);
  const [protocolDispatchTreasury, setProtocolDispatchTreasury] = useState<number>(1_420.8);

  const [keepers, setKeepers] = useState<KeeperNode[]>([
    {
      id: 'KPR-01',
      operator: '0x7A10...91B2 (Primary)',
      bondedSMusd: 5000,
      accruedSMusdYield: 84.2,
      jobsExecuted: 42,
      slashedCount: 0,
    },
    {
      id: 'KPR-02',
      operator: '0x4E82...C019 (Delinquent)',
      bondedSMusd: 2500,
      accruedSMusdYield: 31.4,
      jobsExecuted: 18,
      slashedCount: 0,
    },
    {
      id: 'KPR-03',
      operator: '0x99F1...82E4 (Fallback)',
      bondedSMusd: 4200,
      accruedSMusdYield: 69.8,
      jobsExecuted: 37,
      slashedCount: 0,
    },
  ]);

  const [jobs, setJobs] = useState<DispatchJob[]>([
    {
      jobId: 401,
      module: 'TROVE_TOPUP',
      targetContract: 'TroveManager (CCR 150% Guard)',
      assignedKeeper: 'KPR-01',
      slotDeadlineDeltaBlocks: 6,
      bountyMusd: 85.0,
      status: 'SLOT_ACTIVE',
    },
    {
      jobId: 402,
      module: 'BATCH_LIQUIDATION',
      targetContract: 'TroveManager.batchLiquidateTroves',
      assignedKeeper: 'KPR-02',
      slotDeadlineDeltaBlocks: -4,
      bountyMusd: 140.0,
      status: 'DELINQUENT_SLASHABLE',
    },
    {
      jobId: 403,
      module: 'HINTED_REDEMPTION',
      targetContract: 'HintHelpers + SortedTroves',
      assignedKeeper: 'KPR-03',
      slotDeadlineDeltaBlocks: 8,
      bountyMusd: 95.0,
      status: 'SLOT_ACTIVE',
    },
    {
      jobId: 404,
      module: 'GAUGE_EPOCH_POKE',
      targetContract: 'BoostVoter + Voter (678 Gauges)',
      assignedKeeper: 'KPR-01',
      slotDeadlineDeltaBlocks: -2,
      bountyMusd: 65.0,
      status: 'DELINQUENT_SLASHABLE',
    },
  ]);

  // 60fps Signal Box Clock & Productive sMUSD Yield Ticker via useRef
  const signalClockRef = useRef<HTMLSpanElement | null>(null);
  const liveBondYieldRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    fetchSignalBoxTelemetry().then(setTelemetry);
    const id = setInterval(() => {
      fetchSignalBoxTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let rafId: number;
    const start = performance.now();

    const tick = (now: number) => {
      if (signalClockRef.current) {
        const d = new Date();
        const cs = String(Math.floor(d.getMilliseconds() / 10)).padStart(2, '0');
        signalClockRef.current.textContent = `${d.toISOString().slice(11, 19)}.${cs} UTC`;
      }
      if (liveBondYieldRef.current) {
        const extra = ((now - start) / 1000) * 0.0085;
        liveBondYieldRef.current.textContent = `+${(185.4 + extra).toFixed(4)} sMUSD`;
      }
      rafId = requestAnimationFrame(tick);
    };

    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, []);

  const handleRegisterKeeperBond = () => {
    signalAudio.splitFlapClatter();
    if (newBondMusd < 500) return; // KeeperGrid.MIN_KEEPER_BOND
    const nextIdx = keepers.length + 1;
    setKeepers([
      ...keepers,
      {
        id: `KPR-0${nextIdx}`,
        operator: walletAddress ?? '0x3a8d...c51f (Active)',
        bondedSMusd: newBondMusd,
        accruedSMusdYield: 0,
        jobsExecuted: 0,
        slashedCount: 0,
      },
    ]);
    onLogEvent?.(`Registered Keeper Node KPR-0${nextIdx} bonded with ${newBondMusd} sMUSD.`);
  };

  const handleDispatchJob = (job: DispatchJob) => {
    if (job.status === 'CLEARED') return;
    const isSlashing = job.status === 'DELINQUENT_SLASHABLE';
    signalAudio.throwInterlockLever(isSlashing);

    const protocolFee = job.bountyMusd * 0.05; // KeeperGrid.PROTOCOL_FEE_BPS = 500
    setProtocolDispatchTreasury((t) => t + protocolFee);

    if (isSlashing) {
      // Slash 10% of delinquent keeper's sMUSD bond and award to fallback executor
      setKeepers((prev) =>
        prev.map((k) => {
          if (k.id === job.assignedKeeper) {
            const slashAmt = k.bondedSMusd * 0.1;
            return {
              ...k,
              bondedSMusd: k.bondedSMusd - slashAmt,
              slashedCount: k.slashedCount + 1,
            };
          }
          if (k.id === 'KPR-03') {
            return {
              ...k,
              bondedSMusd: k.bondedSMusd + 250,
              jobsExecuted: k.jobsExecuted + 1,
            };
          }
          return k;
        })
      );
      onLogEvent?.(`DELINQUENT SLASH: Keeper ${job.assignedKeeper} missed slot. 10% bond slashed and awarded to KPR-03.`);
    } else {
      setKeepers((prev) =>
        prev.map((k) =>
          k.id === job.assignedKeeper ? { ...k, jobsExecuted: k.jobsExecuted + 1 } : k
        )
      );
      onLogEvent?.(`Dispatched Job #${job.jobId} (${job.module}): executed by ${job.assignedKeeper}.`);
    }

    setJobs((prev) =>
      prev.map((j) => (j.jobId === job.jobId ? { ...j, status: 'CLEARED' } : j))
    );
  };

  const [dock, setDock] = useState<'ALL' | JobModuleType>('ALL');
  const moduleMeta: Record<JobModuleType, { label: string; icon: React.ReactNode; blurb: string }> = {
    BATCH_LIQUIDATION: { label: 'Liquidate', icon: <Zap className="w-4 h-4" />, blurb: 'TroveManager.batchLiquidateTroves' },
    HINTED_REDEMPTION: { label: 'Redeem', icon: <Sliders className="w-4 h-4" />, blurb: 'HintHelpers + SortedTroves' },
    TROVE_TOPUP: { label: 'Top-up', icon: <ShieldCheck className="w-4 h-4" />, blurb: 'Recovery-aware trove top-up' },
    GAUGE_EPOCH_POKE: { label: 'Epoch Poke', icon: <Radio className="w-4 h-4" />, blurb: 'BoostVoter epoch rollover' },
  };
  const shownJobs = jobs.filter((j) => dock === 'ALL' || j.module === dock);
  const overdue = jobs.filter((j) => j.status === 'DELINQUENT_SLASHABLE').length;
  const totalBonded = keepers.reduce((a, k) => a + k.bondedSMusd, 0);

  const statusMeta = {
    SLOT_ACTIVE: { tone: 'ice' as const, label: 'On slot' },
    DELINQUENT_SLASHABLE: { tone: 'neg' as const, label: 'Overdue' },
    CLEARED: { tone: 'pos' as const, label: 'Cleared' },
  };

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="08"
        pillar="Governance"
        title="Keepers that keep Mezo running"
        description="Keepers bond MUSD into sMUSD, so standing by earns yield. Miss your slot and the fallback keeper who runs the job takes 10% of your bond."
        actions={
          <StatusPill tone={overdue ? 'warn' : 'pos'}>
            {overdue ? `${overdue} slot${overdue > 1 ? 's' : ''} overdue` : 'All keepers on slot'}
          </StatusPill>
        }
        stats={[
          { label: 'Active keepers', value: live(chainStats?.keeperGrid.activeKeepers), sub: 'Bonded in KeeperGrid, on-chain', tone: 'ice' },
          { label: 'Troves watched', value: fmt(telemetry.troveCount), sub: 'Mezo TroveManager, live' },
          { label: 'Gauges to poke', value: fmt(telemetry.boostGaugeCount), sub: 'BoostVoter, live' },
          { label: 'Minimum bond', value: '500 MUSD', sub: '15 min slots · 10% slash · 5% fee' },
        ]}
      />

      <KeeperGridLive wallet={wallet} onLogEvent={onLogEvent} />

      <SimDivider />

      <Panel
        eyebrow="Dispatch board"
        title="Open maintenance jobs"
        glow
        right={
          <>
            <Segmented
              value={dock}
              onChange={(v) => {
                signalAudio.splitFlapClatter();
                setDock(v);
              }}
              options={[
                { value: 'ALL' as const, label: 'All' },
                ...(Object.keys(moduleMeta) as JobModuleType[]).map((m) => ({ value: m, label: moduleMeta[m].label })),
              ]}
            />
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                signalAudio.splitFlapClatter();
                setJobs((prev) => prev.map((j) => ({ ...j, status: j.slotDeadlineDeltaBlocks < 0 ? 'DELINQUENT_SLASHABLE' : 'SLOT_ACTIVE' })));
              }}
            >
              Reset
            </Button>
          </>
        }
      >
        <div className="grid gap-4 md:grid-cols-2">
          {shownJobs.map((job) => {
            const meta = moduleMeta[job.module];
            const st = statusMeta[job.status];
            return (
              <div key={job.jobId} className="rounded-xl border border-line bg-raised p-5">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-line text-muted">{meta.icon}</div>
                    <div>
                      <div className="text-[15px]">
                        {meta.label} <span className="font-mono text-[12px] text-faint">#{job.jobId}</span>
                      </div>
                      <div className="text-[12px] text-muted">{job.targetContract}</div>
                    </div>
                  </div>
                  <StatusPill tone={st.tone}>{st.label}</StatusPill>
                </div>
                <div className="mt-4 flex items-center justify-between font-mono text-[12px] text-muted">
                  <span>
                    {job.assignedKeeper} · {job.slotDeadlineDeltaBlocks > 0 ? `${job.slotDeadlineDeltaBlocks} blocks left` : `${Math.abs(job.slotDeadlineDeltaBlocks)} blocks overdue`}
                  </span>
                  <span className="text-fg">+{job.bountyMusd.toFixed(1)} MUSD</span>
                </div>
                <div className="mt-4 flex items-center justify-between border-t border-line pt-4">
                  <span className="text-[12px] text-faint">
                    {job.status === 'DELINQUENT_SLASHABLE' ? 'Fallback earns a 10% bond slash' : job.status === 'CLEARED' ? 'Executed' : 'Standard bounty'}
                  </span>
                  {job.status !== 'CLEARED' && (
                    <Button size="sm" variant={job.status === 'DELINQUENT_SLASHABLE' ? 'danger' : 'primary'} onClick={() => handleDispatchJob(job)}>
                      {job.status === 'DELINQUENT_SLASHABLE' ? 'Slash & execute' : 'Execute'}
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
          {shownJobs.length === 0 && <div className="text-[14px] text-muted">No jobs in this module.</div>}
        </div>
      </Panel>

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-5" eyebrow="Bond" title="Bonds that earn while they wait">
          <p className="text-[14px] leading-relaxed text-muted">
            Your bond sits in Mezo's sMUSD savings rate. Slot windows are 15 minutes; a missed slot can be executed by any fallback keeper for a 10% slash.
          </p>
          <div className="mt-5 flex items-end gap-3">
            <div className="flex-1">
              <Field label="Bond" hint="Minimum 500 MUSD">
                <NumberInput value={newBondMusd} onChange={setNewBondMusd} step={500} min={500} suffix="MUSD" />
              </Field>
            </div>
            <Button variant="primary" className="mb-6" onClick={handleRegisterKeeperBond}>Bond into sMUSD</Button>
          </div>
        </Panel>

        <Panel className="lg:col-span-7" eyebrow="Keepers" title={`${keepers.length} bonded`} flush right={<span className="font-mono text-[12px] text-muted">{fmt(totalBonded)} sMUSD total</span>}>
          <Table head={['Keeper', 'Bond', 'Jobs', 'Slashed']} cols="1fr 120px 70px 80px">
            {keepers.map((k) => (
              <Row key={k.id} cols="1fr 120px 70px 80px">
                <span className="flex min-w-0 items-center gap-3">
                  <span className={`h-2 w-2 shrink-0 rounded-full ${k.slashedCount ? 'bg-neg' : 'bg-pos'}`} />
                  <span className="min-w-0">
                    <span className="block">{k.id}</span>
                    <span className="block truncate font-mono text-[11px] text-faint">{k.operator}</span>
                  </span>
                </span>
                <span className="text-right font-mono">
                  {fmt(k.bondedSMusd)}
                  <span className="block text-[11px] text-ice">+{k.accruedSMusdYield}</span>
                </span>
                <span className="text-right font-mono">{k.jobsExecuted}</span>
                <span className={`text-right font-mono ${k.slashedCount ? 'text-neg' : 'text-faint'}`}>{k.slashedCount}</span>
              </Row>
            ))}
          </Table>
        </Panel>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 px-1 font-mono text-[12px] text-faint">
        <span ref={signalClockRef}>—</span>
        <span>Sample dispatch treasury ${protocolDispatchTreasury.toFixed(2)}</span>
        <a href={EXPLORER} target="_blank" rel="noreferrer" className="flex items-center gap-1 hover:text-fg">
          sMUSD {KEEPERGRID_MEZO_ADDRESSES.sMUSD.slice(0, 8)}… <ArrowUpRight className="h-3 w-3" />
        </a>
      </div>
    </div>
  );
}

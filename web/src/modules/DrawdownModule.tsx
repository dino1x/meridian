import { useEffect, useRef, useState } from 'react';
import { Button, EXPLORER, PageHeader, Panel, StatusPill, Steps , SimDivider } from '../ui/kit';
import { DrawdownLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  ArrowUpRight,
  Printer,
  ShieldAlert,
} from 'lucide-react';
import {
  DRAWDOWN_MEZO_ADDRESSES,
  fetchPayrollTelemetry,
  PayrollChainTelemetry,
} from '../lib/meridianChain';
import { printerAudio } from '../lib/thermalPrinterAudio';

interface PayrollStream {
  streamId: number;
  recipientName: string;
  role: string;
  wallet: string;
  monthlyRateMusd: number;
  baseAccruedMusd: number;
  totalClaimedMusd: number;
}

interface ThermalReceipt {
  receiptNo: string;
  recipientName: string;
  grossMusd: number;
  netMusd: number;
  feeMusd: number;
  source: 'JIT_TROVE_WITHDRAW_MUSD' | 'SMUSD_RECOVERY_BUFFER';
  timestamp: string;
}

export function DrawdownModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<PayrollChainTelemetry>({
    blockNumber: 4_813_160n,
    btcPriceUsd: 76559.43,
    minNetDebtMusd: 1800,
    borrowingFeePct: 0.1,
    mcrPct: 110,
    ccrPct: 150,
    isRecoveryMode: false,
    sMusdSupply: 897415.12,
    isLive: false,
  });

  const [simulateRecoveryMode, setSimulateRecoveryMode] = useState(false);

  const [corporateBtcColl] = useState<number>(1.25);
  const [drawnMusdDebt, setDrawnMusdDebt] = useState<number>(3600);
  const [emergencySMusdBuffer, setEmergencySMusdBuffer] = useState<number>(6400);
  const [protocolRevenueMusd, setProtocolRevenueMusd] = useState<number>(412.5);

  const [streams, setStreams] = useState<PayrollStream[]>([
    {
      streamId: 1,
      recipientName: 'Soren Lindqvist',
      role: 'Core Protocol Engineer',
      wallet: '0xDE01...84A2',
      monthlyRateMusd: 9000,
      baseAccruedMusd: 1420.5,
      totalClaimedMusd: 4500,
    },
    {
      streamId: 2,
      recipientName: 'Astrid Solberg',
      role: 'Zero-Knowledge Auditor',
      wallet: '0x91B4...22F1',
      monthlyRateMusd: 10500,
      baseAccruedMusd: 980.25,
      totalClaimedMusd: 5250,
    },
    {
      streamId: 3,
      recipientName: 'Maja Holm',
      role: 'Product Design Lead',
      wallet: '0x44C2...71E0',
      monthlyRateMusd: 7800,
      baseAccruedMusd: 615.8,
      totalClaimedMusd: 3900,
    },
  ]);

  const [receipts, setReceipts] = useState<ThermalReceipt[]>([
    {
      receiptNo: 'RCP-31611-042',
      recipientName: 'Soren Lindqvist',
      grossMusd: 2250.0,
      netMusd: 2244.38,
      feeMusd: 5.62,
      source: 'JIT_TROVE_WITHDRAW_MUSD',
      timestamp: '2026-11-02 18:10:04 UTC',
    },
    {
      receiptNo: 'RCP-31611-041',
      recipientName: 'Astrid Solberg',
      grossMusd: 1850.0,
      netMusd: 1845.38,
      feeMusd: 4.62,
      source: 'SMUSD_RECOVERY_BUFFER',
      timestamp: '2026-11-01 09:45:12 UTC',
    },
  ]);

  // 60fps DOM refs for per-second ticking pay slips (Zero React state re-renders!)
  const slip1Ref = useRef<HTMLDivElement | null>(null);
  const slip2Ref = useRef<HTMLDivElement | null>(null);
  const slip3Ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    fetchPayrollTelemetry().then(setTelemetry);
    const id = setInterval(() => {
      fetchPayrollTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let rafId: number;
    const start = performance.now();

    const tick = (now: number) => {
      const elapsedSec = (now - start) / 1000;
      const refs = [slip1Ref, slip2Ref, slip3Ref];
      streams.forEach((st, idx) => {
        const ratePerSec = st.monthlyRateMusd / (30 * 86400);
        const liveVal = st.baseAccruedMusd + elapsedSec * ratePerSec * 120; // 120x demo speed
        const el = refs[idx]?.current;
        if (el) {
          el.textContent = `${liveVal.toFixed(4)} MUSD`;
        }
      });
      rafId = requestAnimationFrame(tick);
    };

    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, [streams]);

  const effectiveRecovery = telemetry.isRecoveryMode || simulateRecoveryMode;
  const corpCollateralUsd = corporateBtcColl * telemetry.btcPriceUsd;
  const entireDebtMusd = drawnMusdDebt + 200; // +200 MUSD gas compensation
  const corpIcrPct = entireDebtMusd > 0 ? (corpCollateralUsd / entireDebtMusd) * 100 : 0;

  const handleClaimAndPrintPayslip = (stream: PayrollStream) => {
    printerAudio.printReceiptFeed();
    const claimGross = stream.baseAccruedMusd;
    if (claimGross <= 0) return;

    const fee = claimGross * 0.005; // DrawdownDesk.CLEARING_FEE_BPS = 50 (0.50%)
    const netPay = claimGross - fee;

    // Check if Normal Mode & post-withdrawal ICR >= 150% CCR -> JIT Trove Drawdown; else sMUSD Buffer!
    const projectedIcr =
      (corpCollateralUsd / (entireDebtMusd + claimGross)) * 100;
    const useJitTrove = !effectiveRecovery && projectedIcr >= telemetry.ccrPct;

    if (useJitTrove) {
      setDrawnMusdDebt((d) => d + claimGross);
    } else {
      setEmergencySMusdBuffer((b) => Math.max(0, b - claimGross));
    }

    setProtocolRevenueMusd((r) => r + fee);
    setStreams((prev) =>
      prev.map((s) =>
        s.streamId === stream.streamId
          ? {
              ...s,
              baseAccruedMusd: 125.0,
              totalClaimedMusd: Number((s.totalClaimedMusd + netPay).toFixed(2)),
            }
          : s
      )
    );

    const nowStr = new Date().toISOString().slice(0, 19).replace('T', ' ') + ' UTC';
    setReceipts((prev) => [
      {
        receiptNo: `RCP-31611-0${43 + prev.length}`,
        recipientName: stream.recipientName,
        grossMusd: Number(claimGross.toFixed(2)),
        netMusd: Number(netPay.toFixed(2)),
        feeMusd: Number(fee.toFixed(2)),
        source: useJitTrove ? 'JIT_TROVE_WITHDRAW_MUSD' : 'SMUSD_RECOVERY_BUFFER',
        timestamp: nowStr,
      },
      ...prev,
    ]);
    onLogEvent?.(`Payslip printed for ${stream.recipientName}: ${claimGross.toFixed(2)} MUSD claimed via ${useJitTrove ? "JIT Trove" : "sMUSD Buffer"}.`);
  };

  const [activeStep, setActiveStep] = useState<number>(1);
  const usd = (n: number, d = 0) => n.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
  const monthlyPayroll = streams.reduce((a, s) => a + s.monthlyRateMusd, 0);
  const totalPaid = streams.reduce((a, s) => a + s.totalClaimedMusd, 0);
  const slipRefs = [slip1Ref, slip2Ref, slip3Ref];

  const steps = [
    {
      title: 'Lock BTC, borrow nothing yet',
      body: `The treasury opens a high-ICR trove with ${corporateBtcColl} BTC. A seed buffer sits in sMUSD and earns yield. There is no idle debt for salaries that haven't vested.`,
    },
    {
      title: 'Salaries stream every second',
      body: `${streams.length} contributors accrue ${usd(monthlyPayroll)} MUSD a month between them. Nothing is minted until someone claims.`,
    },
    {
      title: 'Claim triggers a just-in-time draw',
      body: 'On claim, DrawdownDesk calls withdrawMUSD for exactly the vested amount, takes a 0.50% fee and prints a receipt.',
    },
    {
      title: 'Recovery Mode falls back to sMUSD',
      body: 'If Mezo is in Recovery Mode, or the draw would push ICR below 150%, the claim is paid from the sMUSD buffer instead.',
    },
  ];

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="02"
        pillar="Credit"
        title="Payroll that borrows only on payday"
        description="Salaries stream from a BTC-backed treasury every second. MUSD is drawn from the trove only at the moment someone claims."
        actions={
          <Button
            variant={effectiveRecovery ? 'danger' : 'secondary'}
            onClick={() => {
              printerAudio.keyClick();
              setSimulateRecoveryMode(!simulateRecoveryMode);
              setActiveStep(3);
            }}
          >
            <ShieldAlert className="h-4 w-4" />
            {effectiveRecovery ? 'Recovery Mode on' : 'Simulate Recovery Mode'}
          </Button>
        }
        stats={[
          { label: 'Payroll trove', value: chainStats?.drawdown.initialized == null ? '—' : chainStats.drawdown.initialized ? 'Open' : 'Not opened', sub: 'DrawdownDesk, on-chain', tone: chainStats?.drawdown.initialized ? 'pos' : 'default' },
          { label: 'Desk collateral', value: live(chainStats?.drawdown.coll, 4, ' BTC'), sub: 'on-chain' },
          { label: 'Drawn debt', value: live(chainStats?.drawdown.debt, 2), sub: 'MUSD, on-chain', tone: 'ice' },
          { label: 'Pay streams', value: live(chainStats?.drawdown.streams), sub: 'on-chain' },
        ]}
      />

      <DrawdownLive wallet={wallet} onLogEvent={onLogEvent} />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-4" eyebrow="How it works" title="One claim at a time">
          <Steps steps={steps} active={activeStep} onSelect={setActiveStep} />
          <div className="mt-5">
            <StatusPill tone={effectiveRecovery ? 'warn' : 'pos'}>
              {effectiveRecovery ? 'Paying from the sMUSD buffer' : 'Paying by just-in-time withdrawMUSD'}
            </StatusPill>
          </div>
        </Panel>

        <Panel
          className="lg:col-span-8"
          eyebrow="Streams"
          title={`${streams.length} contributors`}
          flush
          glow
          right={<span className="font-mono text-[12px] text-muted">{usd(monthlyPayroll)} MUSD / month</span>}
        >
          <div className="divide-y divide-line">
            {streams.map((st, idx) => (
              <div key={st.streamId} className="flex flex-wrap items-center justify-between gap-4 px-6 py-4">
                <div className="flex min-w-0 items-center gap-3">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-line bg-raised font-mono text-[12px] text-copper">
                    {st.recipientName.split(' ').map((p) => p[0]).join('')}
                  </div>
                  <div className="min-w-0">
                    <div className="truncate text-[15px]">{st.recipientName}</div>
                    <div className="truncate text-[12px] text-muted">
                      {st.role} · {usd(st.monthlyRateMusd)} MUSD / month
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <div className="text-right">
                    <div ref={slipRefs[idx]} className="font-mono text-[15px] text-ice">
                      {st.baseAccruedMusd.toFixed(4)} MUSD
                    </div>
                    <div className="text-[11px] text-faint">vested, not yet borrowed</div>
                  </div>
                  <Button size="sm" variant="primary" onClick={() => handleClaimAndPrintPayslip(st)}>
                    <Printer className="h-3.5 w-3.5" /> Claim
                  </Button>
                </div>
              </div>
            ))}
          </div>
          <div className="border-t border-line px-6 py-3 text-[12px] text-faint">
            Sample treasury: trove ratio {corpIcrPct.toFixed(0)}% · sMUSD buffer {usd(emergencySMusdBuffer)} · {usd(totalPaid)} MUSD paid out, with no idle debt held for unclaimed salaries.
          </div>
        </Panel>
      </div>

      <Panel eyebrow="Receipts" title="Every claim prints a receipt" right={<span className="font-mono text-[12px] text-muted">Fees {usd(protocolRevenueMusd, 2)} MUSD</span>}>
        <div className="flex gap-5 overflow-x-auto pb-2">
          {receipts.map((r) => (
            <div key={r.receiptNo} className="receipt rise w-[250px] shrink-0 bg-paper px-5 pb-9 pt-5 font-mono text-[12px] text-ink">
              <div className="text-center">
                <div className="text-[12px] tracking-[0.25em]">DRAWDOWN</div>
                <div className="mt-1 text-[10px] text-ink/50">{r.timestamp}</div>
              </div>
              <div className="my-3 border-t border-dashed border-ink/25" />
              <ReceiptLine k="No." v={r.receiptNo} />
              <ReceiptLine k="Payee" v={r.recipientName} />
              <ReceiptLine k="Gross" v={r.grossMusd.toFixed(2)} />
              <ReceiptLine k="Fee 0.50%" v={`−${r.feeMusd.toFixed(2)}`} />
              <div className="my-3 border-t border-dashed border-ink/25" />
              <div className="flex justify-between text-[14px]">
                <span>NET</span>
                <span>{r.netMusd.toFixed(2)}</span>
              </div>
              <div className="mt-3 text-center text-[10px] tracking-wider text-ink/55">
                {r.source === 'JIT_TROVE_WITHDRAW_MUSD' ? 'PAID VIA withdrawMUSD' : 'PAID FROM sMUSD BUFFER'}
              </div>
            </div>
          ))}
        </div>
        <a href={EXPLORER} target="_blank" rel="noreferrer" className="mt-4 inline-flex items-center gap-1 font-mono text-[12px] text-muted hover:text-fg">
          BorrowerOperations {DRAWDOWN_MEZO_ADDRESSES.BorrowerOperations.slice(0, 10)}… <ArrowUpRight className="h-3.5 w-3.5" />
        </a>
      </Panel>
    </div>
  );
}

function ReceiptLine({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between py-0.5">
      <span className="text-ink/55">{k}</span>
      <span className="ml-3 truncate">{v}</span>
    </div>
  );
}

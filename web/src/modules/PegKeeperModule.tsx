import { useEffect, useRef, useState } from 'react';
import { fmt, Button, EXPLORER, Field, KeyValue, MeterRow, NumberInput, PageHeader, Panel, Slider, StatusPill, Toggle , SimDivider } from '../ui/kit';
import { VaultLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import { ADDR } from '../lib/tx';
import {
  ArrowUpRight,
  Cpu,
  Gauge,
  Zap,
} from 'lucide-react';
import {
  fetchMetrologyState,
  MetrologyChainState,
  PEGKEEPER_CONTRACTS,
} from '../lib/meridianChain';
import { metrologyAudio } from '../lib/metrologyAudio';

interface CalibrationReport {
  serial: string;
  musdRedeemed: number;
  btcSeized: number;
  grossSwappedMusd: number;
  netArbitrageProfitMusd: number;
  firstRedemptionHint: string;
  partialNICR: string;
}

export function PegKeeperModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [chain, setChain] = useState<MetrologyChainState>({
    blockNumber: 4_813_050n,
    btcPriceUsd: 76559.43,
    troveCount: 352,
    redemptionRatePct: 0.5,
    isRecoveryMode: false,
    lowestIcrTrove: '',
    sortedTrovesSize: 352,
    sMusdSupply: 897415.12,
    isLive: false,
  });

  const [simulatedMusdDexPrice, setSimulatedMusdDexPrice] = useState<number>(0.984);
  const [simulateRecoveryBlock, setSimulateRecoveryBlock] = useState<boolean>(false);
  const [redeemBatchMusd, setRedeemBatchMusd] = useState<number>(12000);
  const [vaultIdleSMusd, setVaultIdleSMusd] = useState<number>(148_500);
  const [vaultSharePrice, setVaultSharePrice] = useState<number>(1.0412);
  const [protocolFeeTreasury, setProtocolFeeTreasury] = useState<number>(1_842.6);

  const [reports, setReports] = useState<CalibrationReport[]>([
    {
      serial: 'CAL-31611-089',
      musdRedeemed: 15000,
      btcSeized: 0.1959,
      grossSwappedMusd: 15292.4,
      netArbitrageProfitMusd: 263.16,
      firstRedemptionHint: '0x5B38...ddC4',
      partialNICR: '1148291048291048291',
    },
    {
      serial: 'CAL-31611-088',
      musdRedeemed: 10000,
      btcSeized: 0.1306,
      grossSwappedMusd: 10184.0,
      netArbitrageProfitMusd: 165.6,
      firstRedemptionHint: '0x71C9...9A21',
      partialNICR: '1162049182049182049',
    },
  ]);

  // 60fps Canvas Oscilloscope & DOM Ref Readouts (Zero React state re-renders)
  const scopeCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const freqReadoutRef = useRef<HTMLSpanElement | null>(null);

  useEffect(() => {
    fetchMetrologyState().then(setChain);
    const id = setInterval(() => {
      fetchMetrologyState().then(setChain);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let rafId: number;
    const renderScope = (now: number) => {
      if (freqReadoutRef.current) {
        const jitter = Math.sin(now * 0.005) * 0.00012;
        const livePeg = simulatedMusdDexPrice + jitter;
        freqReadoutRef.current.textContent = `$${livePeg.toFixed(5)}`;
      }

      const canvas = scopeCanvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          const w = canvas.width;
          const h = canvas.height;
          ctx.clearRect(0, 0, w, h);

          // Graticule grid
          ctx.strokeStyle = 'rgba(255, 255, 255, 0.045)';
          ctx.lineWidth = 1;
          for (let x = 0; x < w; x += 40) {
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
          }
          for (let y = 0; y < h; y += 35) {
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
          }

          // $1.0000 Reference Center Line
          const centerY = h * 0.42;
          ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
          ctx.setLineDash([6, 4]);
          ctx.beginPath();
          ctx.moveTo(0, centerY);
          ctx.lineTo(w, centerY);
          ctx.stroke();
          ctx.setLineDash([]);

          // Live MUSD Peg Waveform
          const pegOffsetPx = (1.0 - simulatedMusdDexPrice) * 2600;
          ctx.strokeStyle = simulatedMusdDexPrice < 0.995 ? '#E59A38' : '#9FC2FF';
          ctx.lineWidth = 2.2;
          ctx.beginPath();
          for (let x = 0; x < w; x += 3) {
            const wave =
              Math.sin(x * 0.035 + now * 0.006) * 6 +
              Math.cos(x * 0.09 - now * 0.004) * 3;
            const y = Math.min(h - 12, Math.max(12, centerY + pegOffsetPx + wave));
            if (x === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
          }
          ctx.stroke();
        }
      }

      rafId = requestAnimationFrame(renderScope);
    };

    rafId = requestAnimationFrame(renderScope);
    return () => cancelAnimationFrame(rafId);
  }, [simulatedMusdDexPrice]);

  const effectiveRecovery = chain.isRecoveryMode || simulateRecoveryBlock;
  const discountPct = (1 - simulatedMusdDexPrice) * 100;
  const netSpreadPct = discountPct - chain.redemptionRatePct;
  const isArbProfitable = !effectiveRecovery && netSpreadPct > 0.1;

  const handleExecuteHintedRedemption = () => {
    metrologyAudio.calibrationSweep();
    if (!isArbProfitable) return;
    const btcSeized = redeemBatchMusd / chain.btcPriceUsd;
    const grossMusdOut = redeemBatchMusd * (1 + netSpreadPct / 100);
    const grossProfit = grossMusdOut - redeemBatchMusd;
    const perfFee = grossProfit * 0.1; // 10% protocol performance fee
    const keeperTip = grossProfit * 0.02;
    const netProfit = grossProfit - perfFee - keeperTip;

    setVaultIdleSMusd((v) => v + netProfit);
    setVaultSharePrice((p) => Number((p + netProfit / 200000).toFixed(4)));
    setProtocolFeeTreasury((t) => t + perfFee);
    setSimulatedMusdDexPrice((p) => Math.min(1.0, Number((p + 0.004).toFixed(4))));

    setReports((prev) => [
      {
        serial: `CAL-31611-0${90 + prev.length}`,
        musdRedeemed: redeemBatchMusd,
        btcSeized: Number(btcSeized.toFixed(4)),
        grossSwappedMusd: Number(grossMusdOut.toFixed(2)),
        netArbitrageProfitMusd: Number(netProfit.toFixed(2)),
        firstRedemptionHint: chain.lowestIcrTrove ? `${chain.lowestIcrTrove.slice(0, 6)}...${chain.lowestIcrTrove.slice(-4)}` : 'unavailable',
        partialNICR: '1139402819402819402',
      },
      ...prev,
    ]);
    onLogEvent?.(`Hinted redemption executed: ${redeemBatchMusd} MUSD redeemed, +${netProfit.toFixed(2)} MUSD net arb profit.`);
  };

  const devBps = (simulatedMusdDexPrice - 1) * 10000;
  const grossProfitPreview = Math.max(0, redeemBatchMusd * (netSpreadPct / 100));
  const breakdown = [
    { k: 'Discount to $1.00', v: discountPct, note: 'Tigris DEX spot vs redemption parity' },
    { k: 'Redemption fee', v: -chain.redemptionRatePct, note: 'TroveManager base rate' },
    { k: 'Protocol fee', v: -Math.max(0, netSpreadPct) * 0.1, note: '10% of net spread' },
    { k: 'Keeper bounty', v: -Math.max(0, netSpreadPct) * 0.02, note: '2% of net spread' },
  ];
  const netToDepositors = Math.max(0, netSpreadPct) * 0.88;
  const maxBar = Math.max(0.5, ...breakdown.map((b) => Math.abs(b.v)));

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="05"
        pillar="Peg"
        title="Holding MUSD to a dollar"
        description="Idle MUSD earns in sMUSD. When MUSD trades below $1 minus the redemption fee, the vault redeems against the lowest-ratio troves and keeps the spread."
        actions={
          <Button variant="primary" disabled={!isArbProfitable} onClick={handleExecuteHintedRedemption}>
            <Zap className="h-4 w-4" />
            {effectiveRecovery ? 'Locked in Recovery Mode' : isArbProfitable ? 'Redeem & swap' : 'At parity'}
          </Button>
        }
        stats={[
          { label: 'MUSD spot', value: <span ref={freqReadoutRef}>—</span>, sub: 'Simulated DEX price (slider)', tone: 'ice' },
          { label: 'Distance from peg', value: `${devBps > 0 ? '+' : ''}${devBps.toFixed(0)} bps`, sub: 'From the simulated price', tone: devBps < -50 ? 'warn' : 'default' },
          { label: 'Vault assets', value: live(chainStats?.pegKeeper.assets, 2), sub: 'MUSD in PegKeeperVault, on-chain' },
          { label: 'Share price', value: live(chainStats?.pegKeeper.sharePrice, 4), sub: `MUSD per pkMUSD · ${live(chainStats?.pegKeeper.redemptions)} redemptions run` },
        ]}
      />

      <VaultLive wallet={wallet} onLogEvent={onLogEvent} vault={ADDR.pegKeeper} shareSymbol="pkMUSD" title="Your PegKeeper position" blurb="Deposit MUSD into the PegKeeper vault for pkMUSD. Idle MUSD earns in sMUSD; redemption spread is added to the vault when MUSD trades below the peg." allowWithdraw />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel
          className="lg:col-span-7"
          eyebrow="Peg monitor"
          title="MUSD against $1.0000"
          glow
          right={
            <StatusPill tone={isArbProfitable ? 'pos' : effectiveRecovery ? 'warn' : 'muted'}>
              {isArbProfitable ? 'Arbitrage open' : effectiveRecovery ? 'Locked: Recovery Mode' : 'At parity'}
            </StatusPill>
          }
        >
          <canvas ref={scopeCanvasRef} width={620} height={240} className="h-auto w-full" />
          <div className="mt-5">
            <Slider
              label="Simulated spot price"
              valueLabel={`$${simulatedMusdDexPrice.toFixed(3)}`}
              min={0.965}
              max={1.005}
              step={0.001}
              value={simulatedMusdDexPrice}
              onChange={(v) => {
                metrologyAudio.rotaryDetent();
                setSimulatedMusdDexPrice(v);
              }}
              ends={['$0.965', '$1.005']}
            />
          </div>
        </Panel>

        <Panel className="lg:col-span-5" eyebrow="Spread" title="Where the spread goes">
          <div className="text-[13px] text-muted">pkMUSD net to depositors</div>
          <div className="mt-1 text-[40px] leading-none tracking-tight text-ice">{netToDepositors.toFixed(2)}%</div>
          <div className="mt-6 space-y-5">
            {breakdown.map((b) => (
              <MeterRow
                key={b.k}
                label={b.k}
                value={`${b.v > 0 ? '+' : ''}${b.v.toFixed(2)}%`}
                fraction={Math.abs(b.v) / maxBar}
                note={b.note}
                tone={b.v < 0 ? 'muted' : 'ice'}
              />
            ))}
          </div>
          <p className="mt-5 text-[12px] text-faint">Fees apply only to positive net arbitrage. At parity the vault simply earns the sMUSD rate.</p>
        </Panel>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <Panel eyebrow="01" title="Hints first" right={<Cpu className="h-4 w-4 text-faint" />}>
          <KeyValue k="Lowest-ratio trove" v={chain.lowestIcrTrove ? `${chain.lowestIcrTrove.slice(0, 8)}…${chain.lowestIcrTrove.slice(-4)}` : 'Unavailable offline'} />
          <KeyValue k="Sorted troves" v={fmt(chain.sortedTrovesSize)} />
          <KeyValue k="Redemption fee" v={`${chain.redemptionRatePct.toFixed(2)}%`} />
          <KeyValue k="Max iterations" v="35" />
          <p className="mt-4 text-[13px] leading-relaxed text-muted">
            Redemption and insert hints are computed off-chain, so each redemption is one bounded-gas call.
          </p>
        </Panel>

        <Panel eyebrow="02" title="Redeem below the peg" right={<Gauge className="h-4 w-4 text-faint" />}>
          <Field label="Batch size" hint={`Estimated gross profit ${grossProfitPreview.toFixed(2)} MUSD`}>
            <NumberInput value={redeemBatchMusd} onChange={setRedeemBatchMusd} step={1000} suffix="MUSD" />
          </Field>
          <div className="mt-5 space-y-3">
            <Button variant="primary" className="w-full" disabled={!isArbProfitable} onClick={handleExecuteHintedRedemption}>
              <Zap className="h-4 w-4" />
              {effectiveRecovery ? 'Locked in Recovery Mode' : isArbProfitable ? 'Redeem & swap' : 'At parity: earning in sMUSD'}
            </Button>
            <Toggle
              label="Simulate Recovery Mode lockout"
              on={simulateRecoveryBlock}
              onChange={(v) => {
                metrologyAudio.rotaryDetent();
                setSimulateRecoveryBlock(v);
              }}
            />
          </div>
          <p className="mt-4 text-[13px] leading-relaxed text-muted">MUSD is redeemed for $1.00 of BTC, then swapped back to MUSD on Tigris.</p>
        </Panel>

        <Panel eyebrow="03" title="Redemption history" right={<span className="font-mono text-[12px] text-muted">Treasury ${protocolFeeTreasury.toFixed(2)}</span>}>
          <div className="mb-3 font-mono text-[12px] text-faint">Sample vault: {fmt(vaultIdleSMusd)} sMUSD idle · share price {vaultSharePrice.toFixed(4)}</div>
          <div className="space-y-2.5">
            {reports.slice(0, 4).map((r) => (
              <div key={r.serial} className="rounded-xl border border-line bg-raised px-4 py-3">
                <div className="flex justify-between font-mono text-[13px]">
                  <span className="text-muted">{r.serial}</span>
                  <span className="text-pos">+{r.netArbitrageProfitMusd.toFixed(2)}</span>
                </div>
                <div className="mt-1 flex justify-between text-[12px] text-faint">
                  <span>{r.musdRedeemed.toLocaleString()} MUSD redeemed</span>
                  <span>{r.btcSeized} BTC</span>
                </div>
              </div>
            ))}
          </div>
        </Panel>
      </div>

      <div className="px-1 font-mono text-[12px] text-faint">
        <a href={EXPLORER} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 hover:text-fg">
          TroveManager {PEGKEEPER_CONTRACTS.TroveManager.slice(0, 8)}… <ArrowUpRight className="h-3 w-3" />
        </a>
      </div>
    </div>
  );
}

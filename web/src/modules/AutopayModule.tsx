import { useEffect, useRef, useState } from 'react';
import { StatusPill, Button, Callout, EXPLORER, KeyValue, PageHeader, Panel, Row, Slider, Stat, Table , SimDivider } from '../ui/kit';
import { AutopayLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  ArrowUpRight,
  ShieldAlert,
  Sparkles,
} from 'lucide-react';
import {
  AUTOPAY_MEZO_ADDRESSES,
  ConservatoryTelemetry,
  fetchConservatoryTelemetry,
} from '../lib/meridianChain';
import { greenhouseAudio } from '../lib/greenhouseAudio';

interface GrowthRingEpoch {
  ringNumber: number;
  label: string;
  sMusdDebtRepaid: number;
  spBtcGainCompounded: number;
  resultingIcrPct: number;
}

export function AutopayModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<ConservatoryTelemetry>({
    blockNumber: 4_813_012n,
    btcPriceUsd: 76559.43,
    mcrPct: 110,
    ccrPct: 150,
    troveCount: 352,
    isRecoveryMode: false,
    minNetDebtMusd: 1800,
    spDepositsMusd: 86209195.88,
    sMusdSupply: 897415.12,
    isLive: false,
  });

  const [simulateRecoveryShock, setSimulateRecoveryShock] = useState(false);

  // Specimen Trove state
  const [btcCollateral, setBtcCollateral] = useState<number>(0.18);
  const [musdPrincipalDebt, setMusdPrincipalDebt] = useState<number>(5800);
  const [pendingInterestMusd] = useState<number>(42.5);
  const [reserveBps, setReserveBps] = useState<number>(2500);
  const [lowerBandPct] = useState<number>(135);
  const [upperBandPct, setUpperBandPct] = useState<number>(220);
  const [sMusdReserveBalance, setSMusdReserveBalance] = useState<number>(950);
  const [spReserveBalance] = useState<number>(500);
  const [protocolRevenueMusd, setProtocolRevenueMusd] = useState<number>(128.4);

  const [rings, setRings] = useState<GrowthRingEpoch[]>([
    {
      ringNumber: 1,
      label: 'Seedling Initialization (EIP-1167 Vault)',
      sMusdDebtRepaid: 0,
      spBtcGainCompounded: 0,
      resultingIcrPct: 224.8,
    },
    {
      ringNumber: 2,
      label: 'Epoch #14 Harvest & SP Compound',
      sMusdDebtRepaid: 112.4,
      spBtcGainCompounded: 0.0042,
      resultingIcrPct: 233.6,
    },
    {
      ringNumber: 3,
      label: 'Epoch #15 Harvest & SP Compound',
      sMusdDebtRepaid: 128.9,
      spBtcGainCompounded: 0.0051,
      resultingIcrPct: 244.1,
    },
  ]);

  // 60fps DOM ref for live self-amortizing debt counter (zero React re-renders!)
  const liveDebtDecayRef = useRef<HTMLDivElement | null>(null);
  const conservatoryClockRef = useRef<HTMLSpanElement | null>(null);

  useEffect(() => {
    fetchConservatoryTelemetry().then(setTelemetry);
    const id = setInterval(() => {
      fetchConservatoryTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let rafId: number;
    const start = performance.now();

    const tick = (now: number) => {
      const elapsedSec = (now - start) / 1000;
      const liveDebt = Math.max(1800, musdPrincipalDebt + pendingInterestMusd - elapsedSec * 0.032);
      if (liveDebtDecayRef.current) {
        liveDebtDecayRef.current.textContent = `${liveDebt.toFixed(4)} MUSD`;
      }
      if (conservatoryClockRef.current) {
        const d = new Date();
        conservatoryClockRef.current.textContent = `${d.toISOString().slice(11, 19)} UTC`;
      }
      rafId = requestAnimationFrame(tick);
    };

    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, [musdPrincipalDebt, pendingInterestMusd]);

  const effectiveBtcPrice = simulateRecoveryShock
    ? telemetry.btcPriceUsd * 0.68
    : telemetry.btcPriceUsd;
  const effectiveRecovery = telemetry.isRecoveryMode || simulateRecoveryShock;
  const effectiveLowerThresholdPct = Math.max(
    lowerBandPct,
    effectiveRecovery ? telemetry.ccrPct : telemetry.mcrPct
  );

  // NOTE: getEntireDebtAndColl already includes pendingInterest + 200 MUSD gas compensation; we never double-count!
  const entireDebtMusd = musdPrincipalDebt + pendingInterestMusd + 200;
  const collateralUsd = btcCollateral * effectiveBtcPrice;
  const currentIcrPct = entireDebtMusd > 0 ? (collateralUsd / entireDebtMusd) * 100 : 0;

  const handleHarvestAndStrengthen = () => {
    greenhouseAudio.harvestRingChime();
    const sMusdYield = 145.0;
    const btcGain = 0.0065;
    const protocolFee = sMusdYield * 0.01;
    const keeperTip = sMusdYield * 0.005;
    const netRepay = sMusdYield - protocolFee - keeperTip;

    const nextDebt = Math.max(telemetry.minNetDebtMusd, musdPrincipalDebt - netRepay);
    const nextBtc = Number((btcCollateral + btcGain).toFixed(4));
    const nextIcr = ((nextBtc * effectiveBtcPrice) / (nextDebt + pendingInterestMusd + 200)) * 100;

    setMusdPrincipalDebt(nextDebt);
    setBtcCollateral(nextBtc);
    setProtocolRevenueMusd((r) => r + protocolFee);
    setRings((prev) => [
      ...prev,
      {
        ringNumber: prev.length + 1,
        label: `Epoch #${13 + prev.length} sMUSD + SP Ring`,
        sMusdDebtRepaid: Number(netRepay.toFixed(2)),
        spBtcGainCompounded: btcGain,
        resultingIcrPct: Number(nextIcr.toFixed(1)),
      },
    ]);
    onLogEvent?.(`Autopay harvested: ${netRepay.toFixed(2)} MUSD debt repaid, +${btcGain} BTC compounded.`);
  };

  const handleRebalanceTrellisBand = () => {
    greenhouseAudio.dropletPulse();
    if (currentIcrPct < effectiveLowerThresholdPct) {
      // Defensive debt repayment from sMUSD reserve
      const repayFromReserve = Math.min(sMusdReserveBalance, 600);
      setSMusdReserveBalance((s) => s - repayFromReserve);
      setMusdPrincipalDebt((d) => Math.max(telemetry.minNetDebtMusd, d - repayFromReserve));
      onLogEvent?.(`Defensive rebalance: repaid ${repayFromReserve} MUSD from sMUSD reserve.`);
    } else if (currentIcrPct > upperBandPct && !effectiveRecovery) {
      // Skim excess capacity into sMUSD reserve
      const skimMusd = 350;
      setMusdPrincipalDebt((d) => d + skimMusd);
      setSMusdReserveBalance((s) => s + skimMusd);
      onLogEvent?.(`Skimmed excess capacity: +${skimMusd} MUSD into growth reserve.`);
    }
  };

  const plainDebtMusd = musdPrincipalDebt + pendingInterestMusd + rings.reduce((a, r) => a + r.sMusdDebtRepaid, 0);
  const totalRepaid = rings.reduce((a, r) => a + r.sMusdDebtRepaid, 0);
  const totalBtcCompounded = rings.reduce((a, r) => a + r.spBtcGainCompounded, 0);
  const underFloor = currentIcrPct < effectiveLowerThresholdPct;
  const fmt = (n: number, d = 2) => n.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="01"
        pillar="Credit"
        title="Debt that pays itself down"
        description="Each BTC trove gets its own vault. sMUSD yield repays the MUSD debt, and Stability Pool gains compound back into the collateral."
        actions={
          <>
            <Button variant="primary" onClick={handleHarvestAndStrengthen}>
              <Sparkles className="h-4 w-4" /> Harvest & compound
            </Button>
            <Button onClick={handleRebalanceTrellisBand}>Rebalance band</Button>
          </>
        }
        stats={[
          { label: 'Vaults planted', value: live(chainStats?.autopay.vaults), sub: 'AutopayFactory, on-chain', tone: 'ice' },
          { label: 'BTC price', value: `$${fmt(telemetry.btcPriceUsd, 0)}`, sub: telemetry.isLive ? 'Mezo oracle, live' : 'Offline snapshot' },
          { label: 'Open troves', value: String(telemetry.troveCount), sub: 'Mezo TroveManager, live' },
          { label: 'Ratio floors', value: `${telemetry.mcrPct.toFixed(0)}% / ${telemetry.ccrPct.toFixed(0)}%`, sub: telemetry.isRecoveryMode ? 'Recovery Mode (CCR applies)' : 'MCR / CCR · Normal Mode' },
        ]}
      />

      <AutopayLive wallet={wallet} onLogEvent={onLogEvent} />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-5" eyebrow="Comparison · sample trove" title="Your vault vs a plain trove" right={<StatusPill tone={underFloor ? 'neg' : 'pos'}>{underFloor ? 'Below floor' : `In band · ${currentIcrPct.toFixed(0)}%`}</StatusPill>}>
          <Table head={['', 'Autopay', 'Plain']} cols="1fr 110px 110px">
            {[
              ['Debt', fmt(entireDebtMusd, 0), fmt(plainDebtMusd + 200, 0)],
              ['Collateral', btcCollateral.toFixed(4), (btcCollateral - totalBtcCompounded).toFixed(4)],
              [
                'Collateral ratio',
                `${currentIcrPct.toFixed(1)}%`,
                `${((((btcCollateral - totalBtcCompounded) * effectiveBtcPrice) / (plainDebtMusd + 200)) * 100).toFixed(1)}%`,
              ],
            ].map(([k, a, b]) => (
              <Row key={k} cols="1fr 110px 110px">
                <span className="text-muted">{k}</span>
                <span className="text-right font-mono text-copper">{a}</span>
                <span className="text-right font-mono text-muted">{b}</span>
              </Row>
            ))}
          </Table>
          <div className="mt-6 grid grid-cols-2 gap-4">
            <Stat label="Repaid from sMUSD" value={`−${fmt(totalRepaid)}`} sub="MUSD" tone="ice" />
            <Stat label="BTC compounded" value={`+${totalBtcCompounded.toFixed(4)}`} sub="from the Stability Pool" tone="ice" />
          </div>
        </Panel>

        <Panel className="lg:col-span-7" eyebrow="Growth rings" title={`${rings.length} harvests so far`} glow>
          <div className="grid items-center gap-6 md:grid-cols-[1fr_200px]">
            <svg viewBox="0 0 320 320" className="mx-auto w-full max-w-[320px]">
              <circle cx="160" cy="160" r="150" fill="none" stroke="#3DD68C" strokeOpacity="0.5" strokeDasharray="4 5" />
              {[...rings].reverse().map((ring, idx) => {
                const r = 50 + (rings.length - idx) * 16;
                const tones = ['#E59A38', '#9FC2FF', '#ECEEF1'];
                return (
                  <circle
                    key={ring.ringNumber}
                    cx="160"
                    cy="160"
                    r={Math.min(140, r)}
                    fill={tones[(rings.length - idx) % 3]}
                    fillOpacity={0.14 + ((rings.length - idx) % 3) * 0.06}
                    stroke={tones[(rings.length - idx) % 3]}
                    strokeOpacity="0.6"
                  />
                );
              })}
              <circle cx="160" cy="160" r="62" fill="none" stroke="#F2555A" strokeWidth="2" strokeDasharray="4 4" />
              <circle cx="160" cy="160" r="46" fill="#111317" stroke="rgba(255,255,255,0.12)" />
              <text x="160" y="157" textAnchor="middle" fontSize="14" fill="#ECEEF1" fontFamily="Geist Mono, monospace">
                {btcCollateral.toFixed(3)}
              </text>
              <text x="160" y="174" textAnchor="middle" fontSize="10" fill="#8A9099" fontFamily="Geist Mono, monospace">
                BTC · {currentIcrPct.toFixed(0)}%
              </text>
            </svg>
            <div className="space-y-3 text-[13px] text-muted">
              <Legend swatch="bg-copper/40 border border-copper" label="Harvest rings" />
              <Legend swatch="border-2 border-dashed border-neg" label={`Floor ${effectiveLowerThresholdPct}%`} />
              <Legend swatch="border border-dashed border-pos" label={`Ceiling ${upperBandPct}%`} />
              <p className="pt-2 leading-relaxed">Each harvest adds a ring. The ring chart grows outward from the starting collateral.</p>
            </div>
          </div>
        </Panel>
      </div>

      <Panel eyebrow="History" title="Harvests" flush right={<span className="font-mono text-[12px] text-muted">Fees collected {fmt(protocolRevenueMusd)} MUSD</span>}>
        <Table head={['Epoch', 'Debt repaid', 'BTC added', 'Ratio']} cols="1fr 130px 110px 90px">
          {[...rings].reverse().slice(0, 6).map((r) => (
            <Row key={r.ringNumber} cols="1fr 130px 110px 90px">
              <span className="flex items-center gap-3 truncate">
                <span className="font-mono text-[11px] text-faint">{String(r.ringNumber).padStart(2, '0')}</span>
                {r.label}
              </span>
              <span className="text-right font-mono text-ice">{r.sMusdDebtRepaid ? `−${fmt(r.sMusdDebtRepaid)}` : '—'}</span>
              <span className="text-right font-mono">{r.spBtcGainCompounded ? `+${r.spBtcGainCompounded}` : '—'}</span>
              <span className="text-right font-mono">{r.resultingIcrPct}%</span>
            </Row>
          ))}
        </Table>
        <div className="border-t border-line px-6 py-3 text-[12px] text-faint">Each harvest takes a 1% protocol fee and a 0.5% keeper tip.</div>
      </Panel>

      <Panel eyebrow="Rebalancer" title="Set a band. The vault holds it.">
        <div className="grid gap-8 lg:grid-cols-12">
          <div className="space-y-6 lg:col-span-7">
            <Callout
              tone={effectiveRecovery ? 'warn' : 'pos'}
              title={effectiveRecovery ? 'Recovery Mode: floor raised to the 150% CCR' : `Normal Mode: floor at ${effectiveLowerThresholdPct}%, above the 110% MCR`}
              action={
                <Button
                  size="sm"
                  onClick={() => {
                    greenhouseAudio.dropletPulse();
                    setSimulateRecoveryShock(!simulateRecoveryShock);
                  }}
                >
                  <ShieldAlert className="h-3.5 w-3.5" />
                  {simulateRecoveryShock ? 'Restore BTC price' : 'Simulate −32% BTC'}
                </Button>
              }
            >
              Below the floor the vault repays debt from its sMUSD reserve. Above the ceiling it mints MUSD into the reserve.
            </Callout>
            <div className="grid gap-6 sm:grid-cols-2">
              <Slider
                label="Growth reserve"
                valueLabel={`${reserveBps / 100}%`}
                min={1000}
                max={5000}
                step={500}
                value={reserveBps}
                onChange={setReserveBps}
                ends={[`sMUSD ${sMusdReserveBalance}`, `SP ${spReserveBalance}`]}
              />
              <Slider
                label="Ceiling ratio"
                valueLabel={`${upperBandPct}%`}
                min={170}
                max={280}
                step={5}
                value={upperBandPct}
                onChange={setUpperBandPct}
                ends={[`Floor ${effectiveLowerThresholdPct}%`, `Ceiling ${upperBandPct}%`]}
              />
            </div>
          </div>
          <div className="lg:col-span-5">
            <div className="label">Debt breakdown</div>
            <div className="mt-2">
              <KeyValue k="Principal" v={`${fmt(musdPrincipalDebt)} MUSD`} />
              <KeyValue k="Pending interest" v={`${fmt(pendingInterestMusd)} MUSD`} />
              <KeyValue k="Total (incl. 200 gas comp.)" v={`${fmt(entireDebtMusd)} MUSD`} strong tone="copper" />
            </div>
            <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
              <Button variant="primary" onClick={handleRebalanceTrellisBand}>Rebalance now</Button>
              <a href={EXPLORER} target="_blank" rel="noreferrer" className="flex items-center gap-1 font-mono text-[12px] text-muted hover:text-fg">
                BorrowerOperations {AUTOPAY_MEZO_ADDRESSES.BorrowerOperations.slice(0, 8)}… <ArrowUpRight className="h-3.5 w-3.5" />
              </a>
            </div>
          </div>
        </div>
      </Panel>
    </div>
  );
}

function Legend({ swatch, label }: { swatch: string; label: string }) {
  return (
    <div className="flex items-center gap-2.5">
      <span className={`inline-block h-3 w-3 rounded-full ${swatch}`} />
      {label}
    </div>
  );
}

import React, { useEffect, useRef, useState } from 'react';
import { Button, Field, KeyValue, MeterRow, NumberInput, PageHeader, Panel, Row, Segmented, Slider, StatusPill, Table, Toggle , SimDivider } from '../ui/kit';
import { RoostLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  BookOpen,
  Feather,
  ShieldCheck,
  Stamp,
  Zap,
  RefreshCw,
} from 'lucide-react';
import {
  fetchMezoAlmanacTelemetry,
  MEZO_CONTRACTS,
  MezoAlmanacTelemetry,
  OFFLINE_SNAPSHOT,
} from '../lib/meridianChain';
import { pressAudio } from '../lib/pressAudio';

interface BondPosition {
  id: number;
  principalMusd: number;
  elapsedDays: number;
  status: 'INCUBATING' | 'CHICKENED_IN' | 'CHICKENED_OUT';
  settledBMusd?: number;
  viaTroveZap?: boolean;
  btcCollateral?: number;
}

export function RoostModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<MezoAlmanacTelemetry>(OFFLINE_SNAPSHOT);

  const [activeTab, setActiveTab] = useState<'BOND' | 'ZAP' | 'BUCKETS'>('BOND');
  const [simulateRecoveryMode, setSimulateRecoveryMode] = useState(false);

  // Bond & Trove Zap inputs
  const [bondPrincipal, setBondPrincipal] = useState<number>(5000);
  const [zapBtcAmount, setZapBtcAmount] = useState<number>(0.15);
  const [zapMusdDebt, setZapMusdDebt] = useState<number>(6000);
  const [simulatedDayCursor, setSimulatedDayCursor] = useState<number>(18);

  // System Buckets (Pending, Reserve, Permanent)
  const [buckets, setBuckets] = useState({
    pendingMusd: 142_500,
    reserveMusd: 318_400,
    permanentMusd: 94_200,
    bMusdSupply: 279_298,
    protocolFeeTreasury: 3_184,
  });

  const [bonds, setBonds] = useState<BondPosition[]>([
    {
      id: 101,
      principalMusd: 5000,
      elapsedDays: 18,
      status: 'INCUBATING',
      viaTroveZap: false,
    },
    {
      id: 98,
      principalMusd: 8500,
      elapsedDays: 34,
      status: 'CHICKENED_IN',
      settledBMusd: 5412.18,
      viaTroveZap: true,
      btcCollateral: 0.22,
    },
  ]);

  const [selectedBondId, setSelectedBondId] = useState<number>(101);

  // High-frequency 60fps DOM refs (Zero React state re-renders!)
  const liveAccrualRef = useRef<HTMLDivElement | null>(null);
  const liveMarketValueRef = useRef<HTMLSpanElement | null>(null);
  const pressTimecodeRef = useRef<HTMLSpanElement | null>(null);

  const ALPHA_DAYS = 15; // Hyperbolic half-accrual parameter (15 days)
  const redemptionPrice = buckets.bMusdSupply > 0 ? buckets.reserveMusd / buckets.bMusdSupply : 1.14;
  const marketMultiplier = 1.32; // bMUSD trades at a yield amplification premium above redemption price
  const bMusdMarketPrice = redemptionPrice * marketMultiplier;
  const breakEvenDays = ALPHA_DAYS / (marketMultiplier - 1); // ~46.8 days or scaled by cap

  const selectedBond = bonds.find((b) => b.id === selectedBondId) || bonds[0];

  const calcAccruedBMusd = (principal: number, days: number) => {
    const capBMusd = principal / redemptionPrice;
    return (capBMusd * days) / (days + ALPHA_DAYS);
  };

  useEffect(() => {
    fetchMezoAlmanacTelemetry().then(setTelemetry);
    const interval = setInterval(() => {
      fetchMezoAlmanacTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(interval);
  }, []);

  // 60fps RAF loop updating DOM textContent directly via useRef
  useEffect(() => {
    let rafId: number;
    const startMs = performance.now();

    const tick = (now: number) => {
      const subDayFraction = ((now - startMs) / 1000) * 0.0025;
      const effectiveDays =
        selectedBond.status === 'INCUBATING'
          ? simulatedDayCursor + subDayFraction
          : selectedBond.elapsedDays;

      const accrued = calcAccruedBMusd(selectedBond.principalMusd, effectiveDays);
      const marketVal = accrued * bMusdMarketPrice;

      if (liveAccrualRef.current) {
        liveAccrualRef.current.textContent = `${accrued.toLocaleString('en-US', {
          minimumFractionDigits: 4,
          maximumFractionDigits: 4,
        })} bMUSD`;
      }
      if (liveMarketValueRef.current) {
        liveMarketValueRef.current.textContent = `${marketVal.toLocaleString('en-US', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })} MUSD`;
      }
      if (pressTimecodeRef.current) {
        const d = new Date();
        const ms = String(d.getMilliseconds()).padStart(3, '0').slice(0, 2);
        pressTimecodeRef.current.textContent = `${d.toISOString().slice(0, 10)} ${d.toTimeString().slice(0, 8)}.${ms}`;
      }
      rafId = requestAnimationFrame(tick);
    };

    rafId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafId);
  }, [selectedBond, simulatedDayCursor, redemptionPrice, bMusdMarketPrice]);

  const handleMintBond = () => {
    pressAudio.typeClack();
    if (bondPrincipal < 100) return;
    const newId = Math.max(...bonds.map((b) => b.id), 100) + 1;
    const newBond: BondPosition = {
      id: newId,
      principalMusd: bondPrincipal,
      elapsedDays: 1,
      status: 'INCUBATING',
      viaTroveZap: false,
    };
    setBonds([newBond, ...bonds]);
    setSelectedBondId(newId);
    setSimulatedDayCursor(1);
    setBuckets((prev) => ({
      ...prev,
      pendingMusd: prev.pendingMusd + bondPrincipal,
    }));
    onLogEvent?.(`Created Roost Bond #${newId} with ${bondPrincipal} MUSD principal.`);
  };

  const effectiveRecovery = telemetry.isRecoveryMode || simulateRecoveryMode;
  const requiredIcrPercent = effectiveRecovery ? telemetry.ccrPercent : telemetry.mcrPercent;
  const zapCollateralUsd = zapBtcAmount * telemetry.btcPriceUsd;
  const zapTotalDebt = zapMusdDebt + 200; // + 200 MUSD Gas Compensation
  const zapIcrPercent = zapTotalDebt > 0 ? (zapCollateralUsd / zapTotalDebt) * 100 : 0;
  const isZapValid =
    zapMusdDebt >= telemetry.minNetDebtMusd && zapIcrPercent >= requiredIcrPercent;

  const handleZapTroveToBond = () => {
    pressAudio.rubberStamp(true);
    if (!isZapValid) return;
    const newId = Math.max(...bonds.map((b) => b.id), 100) + 1;
    const newBond: BondPosition = {
      id: newId,
      principalMusd: zapMusdDebt,
      elapsedDays: 1,
      status: 'INCUBATING',
      viaTroveZap: true,
      btcCollateral: zapBtcAmount,
    };
    setBonds([newBond, ...bonds]);
    setSelectedBondId(newId);
    setSimulatedDayCursor(1);
    setActiveTab('BOND');
    setBuckets((prev) => ({
      ...prev,
      pendingMusd: prev.pendingMusd + zapMusdDebt,
    }));
    onLogEvent?.(`Zapped Trove into Roost Bond #${newId}: minted ${zapMusdDebt} MUSD against ${zapBtcAmount} BTC.`);
  };

  const handleChickenIn = (bond: BondPosition) => {
    if (bond.status !== 'INCUBATING') return;
    pressAudio.rubberStamp(true);
    const days = bond.id === selectedBond.id ? simulatedDayCursor : bond.elapsedDays;
    const accrued = calcAccruedBMusd(bond.principalMusd, days);
    const fee = bond.principalMusd * 0.01;
    const netPrincipal = bond.principalMusd - fee;
    const toReserve = (netPrincipal * days) / (days + ALPHA_DAYS);
    const toPermanent = netPrincipal - toReserve;

    setBonds((prev) =>
      prev.map((b) =>
        b.id === bond.id
          ? { ...b, elapsedDays: days, status: 'CHICKENED_IN', settledBMusd: accrued }
          : b
      )
    );
    setBuckets((prev) => ({
      pendingMusd: Math.max(0, prev.pendingMusd - bond.principalMusd),
      reserveMusd: prev.reserveMusd + toReserve,
      permanentMusd: prev.permanentMusd + toPermanent,
      bMusdSupply: prev.bMusdSupply + accrued,
      protocolFeeTreasury: prev.protocolFeeTreasury + fee,
    }));
    onLogEvent?.(`Chickened IN on Bond #${bond.id}: claimed ${accrued.toFixed(2)} bMUSD at Day ${days}.`);
  };

  const handleChickenOut = (bond: BondPosition) => {
    if (bond.status !== 'INCUBATING') return;
    pressAudio.rubberStamp(false);
    const days = bond.id === selectedBond.id ? simulatedDayCursor : bond.elapsedDays;
    setBonds((prev) =>
      prev.map((b) =>
        b.id === bond.id ? { ...b, elapsedDays: days, status: 'CHICKENED_OUT' } : b
      )
    );
    setBuckets((prev) => ({
      ...prev,
      pendingMusd: Math.max(0, prev.pendingMusd - bond.principalMusd),
      reserveMusd: prev.reserveMusd + bond.principalMusd * 0.008, // Foregone yield stays in Reserve!
    }));
    onLogEvent?.(`Chickened OUT on Bond #${bond.id}: refunded ${bond.principalMusd} MUSD principal with zero loss.`);
  };

  // Generate SVG points for the Hyperbolic Accrual Curve (0 to 90 days)
  const curvePoints: string[] = [];
  for (let d = 0; d <= 90; d += 2) {
    const x = 48 + (d / 90) * 510;
    const frac = d / (d + ALPHA_DAYS);
    const y = 210 - frac * 170;
    curvePoints.push(`${x.toFixed(1)},${y.toFixed(1)}`);
  }
  const activeDays =
    selectedBond.status === 'INCUBATING' ? simulatedDayCursor : selectedBond.elapsedDays;
  const cursorX = 48 + (Math.min(90, activeDays) / 90) * 510;
  const cursorY = 210 - (activeDays / (activeDays + ALPHA_DAYS)) * 170;

  const fmt = (n: number, d = 0) => n.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
  const isIncubating = selectedBond.status === 'INCUBATING';
  const pastBreakEven = activeDays >= breakEvenDays;
  const beX = 48 + (Math.min(90, breakEvenDays) / 90) * 510;
  const bucketTotal = buckets.pendingMusd + buckets.reserveMusd + buckets.permanentMusd;

  const statusLabel = (s: BondPosition['status']) => (s === 'INCUBATING' ? 'Incubating' : s === 'CHICKENED_IN' ? 'Chickened in' : 'Chickened out');
  const statusTone = (s: BondPosition['status']) => (s === 'INCUBATING' ? 'copper' : s === 'CHICKENED_IN' ? 'pos' : 'muted') as 'copper' | 'pos' | 'muted';

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="03"
        pillar="Yield"
        title="Bonds that keep your MUSD safe"
        description="Bond MUSD and accrue bMUSD over time. Chicken out whenever you like and get all your principal back, or chicken in once it pays more."
        actions={
          <>
            <Button variant="primary" onClick={() => { pressAudio.typeClack(); setActiveTab('BUCKETS'); }}>
              <Feather className="h-4 w-4" /> New bond
            </Button>
            <Button onClick={() => { pressAudio.typeClack(); setActiveTab('ZAP'); }}>Bond from a trove</Button>
          </>
        }
        stats={[
          { label: 'Bonds issued', value: live(chainStats?.roost.bonds), sub: 'ChickenBondManager, on-chain' },
          { label: 'Pending bucket', value: live(chainStats?.roost.pending, 2), sub: 'MUSD in incubating bonds', tone: 'ice' },
          { label: 'Reserve bucket', value: live(chainStats?.roost.reserve, 2), sub: 'MUSD backing bMUSD' },
          { label: 'bMUSD supply', value: live(chainStats?.roost.bMusdSupply, 2), sub: chainStats?.roost.redemptionPrice != null ? `Redeems at ${chainStats.roost.redemptionPrice.toFixed(4)} MUSD` : 'No bMUSD minted yet' },
        ]}
      />

      <RoostLive wallet={wallet} onLogEvent={onLogEvent} />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-7" eyebrow="Accrual" title="Wait, then chicken in" glow>
          <p className="text-[14px] text-muted">
            bMUSD accrues on a hyperbolic curve with α = {ALPHA_DAYS} days. After about day {breakEvenDays.toFixed(0)} chickening in is worth more than the principal.
          </p>
          <svg viewBox="0 0 580 240" className="mt-5 w-full">
            <line x1="48" y1="210" x2="560" y2="210" stroke="rgba(255,255,255,0.15)" />
            <line x1="48" y1="40" x2="48" y2="210" stroke="rgba(255,255,255,0.15)" />
            <rect x={beX} y="40" width={560 - beX} height="170" fill="#3DD68C" fillOpacity="0.07" />
            <line x1={beX} y1="40" x2={beX} y2="210" stroke="#3DD68C" strokeOpacity="0.6" strokeDasharray="4 4" />
            <text x={beX + 8} y="54" fontSize="11" fill="#3DD68C" fontFamily="Geist Mono, monospace">
              break-even · day {breakEvenDays.toFixed(0)}
            </text>
            <polyline points={curvePoints.join(' ')} fill="none" stroke="#9FC2FF" strokeWidth="2.5" />
            <circle cx={cursorX} cy={cursorY} r="7" fill="#E59A38" stroke="#0A0B0D" strokeWidth="2" />
            {[0, 30, 60, 90].map((d) => (
              <text key={d} x={48 + (d / 90) * 510} y="228" textAnchor="middle" fontSize="11" fill="#5C626B" fontFamily="Geist Mono, monospace">
                {d}d
              </text>
            ))}
          </svg>
          {isIncubating && (
            <div className="mt-4">
              <Slider label="Bond age" valueLabel={`Day ${simulatedDayCursor}`} min={1} max={90} value={simulatedDayCursor} onChange={setSimulatedDayCursor} />
            </div>
          )}
        </Panel>

        <Panel
          className="lg:col-span-5"
          title={activeTab === 'BOND' ? `Bond #${selectedBond.id}` : activeTab === 'BUCKETS' ? 'New bond' : 'Bond from a trove'}
          right={
            <Segmented
              value={activeTab}
              onChange={(v) => { pressAudio.typeClack(); setActiveTab(v); }}
              options={[
                { value: 'BOND' as const, label: 'Your bond' },
                { value: 'BUCKETS' as const, label: 'New' },
                { value: 'ZAP' as const, label: 'Zap' },
              ]}
            />
          }
        >
          {activeTab === 'BOND' && (
            <div>
              <div className="flex items-center justify-between">
                <span className="label">Accrued so far</span>
                <StatusPill tone={statusTone(selectedBond.status)}>{statusLabel(selectedBond.status)}</StatusPill>
              </div>
              <div className="mt-2 text-[34px] leading-tight tracking-tight text-ice">
                {fmt(calcAccruedBMusd(selectedBond.principalMusd, activeDays), 2)} bMUSD
              </div>
              <div className="text-[14px] text-muted">
                ≈ <span ref={liveMarketValueRef}>—</span> at market
              </div>
              <div className="mt-5">
                <KeyValue k="Principal" v={`${fmt(selectedBond.principalMusd)} MUSD`} />
                <KeyValue k="Age" v={`${activeDays} days${pastBreakEven ? ' · past break-even' : ''}`} />
                <KeyValue k="Source" v={selectedBond.viaTroveZap ? `Trove zap · ${selectedBond.btcCollateral} BTC` : 'Direct deposit'} />
              </div>
              {isIncubating ? (
                <div className="mt-6 grid grid-cols-2 gap-3">
                  <Button onClick={() => handleChickenOut(selectedBond)}>
                    <RefreshCw className="h-4 w-4" /> Chicken out
                  </Button>
                  <Button variant="primary" onClick={() => handleChickenIn(selectedBond)}>
                    <Stamp className="h-4 w-4" /> Chicken in
                  </Button>
                </div>
              ) : (
                <div className="mt-6 flex items-center gap-2 text-[14px] text-muted">
                  <ShieldCheck className="h-4 w-4 text-pos" />
                  {selectedBond.status === 'CHICKENED_IN' ? `Settled ${fmt(selectedBond.settledBMusd ?? 0, 2)} bMUSD.` : 'Principal returned in full.'}
                </div>
              )}
            </div>
          )}

          {activeTab === 'BUCKETS' && (
            <div className="space-y-5">
              <p className="text-[14px] text-muted">Deposit MUSD. It earns in sMUSD from day one and you receive a BondNFT certificate. Minimum 100 MUSD.</p>
              <Field label="Principal">
                <NumberInput value={bondPrincipal} onChange={setBondPrincipal} step={500} suffix="MUSD" />
              </Field>
              <Button variant="primary" className="w-full" onClick={() => { handleMintBond(); setActiveTab('BOND'); }}>
                Mint bond
              </Button>
            </div>
          )}

          {activeTab === 'ZAP' && (
            <div className="space-y-5">
              <p className="text-[14px] text-muted">Open a trove and bond the minted MUSD in one transaction.</p>
              <div className="grid grid-cols-2 gap-3">
                <Field label="BTC">
                  <NumberInput value={zapBtcAmount} onChange={setZapBtcAmount} step="0.01" />
                </Field>
                <Field label="MUSD debt">
                  <NumberInput value={zapMusdDebt} onChange={setZapMusdDebt} step={100} />
                </Field>
              </div>
              <div>
                <KeyValue k="Collateral ratio" v={`${zapIcrPercent.toFixed(1)}% (needs ${requiredIcrPercent}%)`} tone={isZapValid ? 'pos' : 'neg'} />
                <KeyValue k="Minimum debt" v={`${telemetry.minNetDebtMusd} MUSD`} />
              </div>
              <Toggle
                label="Simulate Recovery Mode (150% CCR)"
                on={simulateRecoveryMode}
                onChange={(v) => { pressAudio.typeClack(); setSimulateRecoveryMode(v); }}
              />
              <Button variant="primary" className="w-full" disabled={!isZapValid} onClick={handleZapTroveToBond}>
                <Zap className="h-4 w-4" /> Zap trove into bond
              </Button>
            </div>
          )}
        </Panel>
      </div>

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-5" eyebrow="BondNFT" title="Certificate">
          <Certificate
            id={selectedBond.id}
            principal={selectedBond.principalMusd}
            days={activeDays}
            status={statusLabel(selectedBond.status)}
            zap={!!selectedBond.viaTroveZap}
            accrualRef={liveAccrualRef}
          />
        </Panel>
        <Panel className="lg:col-span-7" eyebrow="Reserves" title="Three buckets back every bMUSD">
          <div className="space-y-6">
            <MeterRow label="Pending · incubating bonds, withdrawable by chickening out" value={`${fmt(buckets.pendingMusd)} MUSD`} fraction={buckets.pendingMusd / bucketTotal} tone="copper" />
            <MeterRow label={`Reserve · backs redemptions at ${redemptionPrice.toFixed(4)}`} value={`${fmt(buckets.reserveMusd)} MUSD`} fraction={buckets.reserveMusd / bucketTotal} tone="ice" />
            <MeterRow label="Permanent · protocol-owned, never withdrawn" value={`${fmt(buckets.permanentMusd)} MUSD`} fraction={buckets.permanentMusd / bucketTotal} tone="pos" />
          </div>
        </Panel>
      </div>

      <Panel eyebrow="Portfolio" title="Your bonds" flush right={<span className="flex items-center gap-1.5 font-mono text-[12px] text-muted"><BookOpen className="h-3.5 w-3.5" /> {bonds.length}</span>}>
        <Table head={['Bond', 'Principal', 'Age', 'Status']} cols="1fr 130px 90px 140px">
          {bonds.map((b) => (
            <Row
              key={b.id}
              cols="1fr 130px 90px 140px"
              active={b.id === selectedBondId}
              onClick={() => {
                pressAudio.typeClack();
                setSelectedBondId(b.id);
                if (b.status === 'INCUBATING') setSimulatedDayCursor(b.elapsedDays);
                setActiveTab('BOND');
              }}
            >
              <span>
                Bond #{b.id}
                <span className="ml-2 text-[12px] text-faint">{b.viaTroveZap ? `trove zap · ${b.btcCollateral} BTC` : 'direct'}</span>
              </span>
              <span className="text-right font-mono">{fmt(b.principalMusd)}</span>
              <span className="text-right font-mono">{b.id === selectedBond.id ? activeDays : b.elapsedDays}d</span>
              <span className="text-right">
                <StatusPill tone={statusTone(b.status)}>{statusLabel(b.status)}</StatusPill>
              </span>
            </Row>
          ))}
        </Table>
        <div className="border-t border-line px-6 py-3 font-mono text-[12px] text-faint">
          ChickenBondManager {MEZO_CONTRACTS.ChickenBondManager.slice(0, 10)}…
        </div>
      </Panel>
    </div>
  );
}

/* BondNFT certificate: the one paper object in Roost, with a slow guilloche rosette */
function Certificate({
  id,
  principal,
  days,
  status,
  zap,
  accrualRef,
}: {
  id: number;
  principal: number;
  days: number;
  status: string;
  zap: boolean;
  accrualRef: React.MutableRefObject<HTMLDivElement | null>;
}) {
  const petals = Array.from({ length: 36 });
  return (
    <div className="relative aspect-[1.45] w-full overflow-hidden rounded-lg bg-paper text-ink">
      <svg viewBox="0 0 500 345" className="absolute inset-0 h-full w-full" aria-hidden>
        <rect x="12" y="12" width="476" height="321" fill="none" stroke="#16171B" strokeOpacity="0.5" />
        <g className="spin-slow" style={{ transformOrigin: '380px 172px' }}>
          {petals.map((_, i) => (
            <ellipse key={i} cx="380" cy="172" rx="92" ry="34" fill="none" stroke="#E59A38" strokeOpacity="0.55" strokeWidth="0.6" transform={`rotate(${i * 5} 380 172)`} />
          ))}
          {petals.map((_, i) => (
            <ellipse key={`b${i}`} cx="380" cy="172" rx="56" ry="20" fill="none" stroke="#16171B" strokeOpacity="0.3" strokeWidth="0.5" transform={`rotate(${i * 5 + 2.5} 380 172)`} />
          ))}
        </g>
        <circle cx="380" cy="172" r="22" fill="#F4F1EA" stroke="#16171B" strokeOpacity="0.6" />
        <text x="380" y="177" textAnchor="middle" fontFamily="Geist Mono, monospace" fontSize="13" fill="#16171B">
          #{id}
        </text>
      </svg>
      <div className="relative flex h-full flex-col justify-between p-7">
        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-ink/60">Roost · bond certificate</div>
          <div className="mt-3 text-[28px] leading-none tracking-tight">{principal.toLocaleString()} MUSD</div>
          <div className="mt-1 text-[12px] text-ink/60">
            {zap ? 'Minted from a BTC trove' : 'Direct deposit'} · day {days}
          </div>
        </div>
        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-ink/60">Accruing</div>
          <div ref={accrualRef} className="font-mono text-[17px]">—</div>
          <div className="mt-2 inline-flex rounded-full border border-ink/30 px-2.5 py-0.5 text-[11px]">{status}</div>
        </div>
      </div>
    </div>
  );
}

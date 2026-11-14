import { useEffect, useRef, useState } from 'react';
import { Button, Callout, EXPLORER, Field, KeyValue, NumberInput, PageHeader, Panel, Row, Segmented, Table, Toggle, fmt , SimDivider } from '../ui/kit';
import { RelayLive } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  Zap,
  ArrowUpRight,
} from 'lucide-react';
import {
  fetchRadarTelemetry,
  MEZO_VE_CONTRACTS,
  RadarChainTelemetry,
} from '../lib/meridianChain';
import { radarAudio } from '../lib/radarAudio';

type YieldRoute = 'COMPOUND_SMUSD' | 'PROVIDE_STABILITY_POOL' | 'REPAY_TROVE_DEBT';

interface GaugeTarget {
  id: string;
  callsign: string;
  voterType: 'Voter (veBTC)' | 'BoostVoter (veMEZO)';
  address: string;
  angleRad: number;
  distanceNorm: number; // 0.25 to 0.88
  bribeMusdValue: number;
  totalVotes: number;
  bribePer1kVotes: number;
  whitelistedBribeToken: string;
  selectedWeight: number;
}

interface RegisteredFlightPlan {
  regId: number;
  nftType: 'veBTC' | 'veMEZO';
  tokenId: number;
  votingPower: number;
  route: YieldRoute;
  autoMaxLock: boolean;
  lastEpochHarvestMusd: number;
  status: 'LOCKED_ON_RADAR' | 'SWEPT_THIS_EPOCH';
}

export function RelayModule({ onLogEvent, walletAddress = null, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<RadarChainTelemetry>({
    blockNumber: 4_812_945n,
    veBtcCount: 1729,
    veMezoCount: 938,
    boostGaugeCount: 678,
    boostTotalWeight: 25667.9,
    btcPriceUsd: 76559.43,
    sMusdSupply: 897415.12,
    spDepositsMusd: 86209195.88,
    isRecoveryMode: false,
    isLive: false,
  });

  const [selectedNftType, setSelectedNftType] = useState<'veBTC' | 'veMEZO'>('veBTC');
  const [inputTokenId, setInputTokenId] = useState<number>(412);
  const [selectedRoute, setSelectedRoute] = useState<YieldRoute>('REPAY_TROVE_DEBT');
  const [autoMaxLock, setAutoMaxLock] = useState<boolean>(true);
  const [whitelistGuardTest, setWhitelistGuardTest] = useState<'PASS' | 'BLOCKED_ROGUE_TOKEN'>('PASS');

  const [gauges, setGauges] = useState<GaugeTarget[]>([
    {
      id: 'g1',
      callsign: 'G-MUSD-BTC',
      voterType: 'Voter (veBTC)',
      address: '0x9A31...4F10',
      angleRad: 0.72,
      distanceNorm: 0.48,
      bribeMusdValue: 18450,
      totalVotes: 310,
      bribePer1kVotes: 59.51,
      whitelistedBribeToken: 'MUSD (Verified)',
      selectedWeight: 45,
    },
    {
      id: 'g2',
      callsign: 'G-SMUSD-VAULT',
      voterType: 'Voter (veBTC)',
      address: '0x6f46...7A8e',
      angleRad: 2.15,
      distanceNorm: 0.64,
      bribeMusdValue: 14200,
      totalVotes: 265,
      bribePer1kVotes: 53.58,
      whitelistedBribeToken: 'MUSD + BTC (Verified)',
      selectedWeight: 35,
    },
    {
      id: 'g3',
      callsign: 'G-BOOST-MEZO',
      voterType: 'BoostVoter (veMEZO)',
      address: '0x21d7...Bfd1',
      angleRad: 3.84,
      distanceNorm: 0.56,
      bribeMusdValue: 11800,
      totalVotes: 290,
      bribePer1kVotes: 40.68,
      whitelistedBribeToken: 'MEZO -> MUSD (Tigris)',
      selectedWeight: 20,
    },
    {
      id: 'g4',
      callsign: 'G-SP-LIQ-04',
      voterType: 'Voter (veBTC)',
      address: '0x1CCA...680e',
      angleRad: 5.18,
      distanceNorm: 0.74,
      bribeMusdValue: 6400,
      totalVotes: 240,
      bribePer1kVotes: 26.66,
      whitelistedBribeToken: 'MUSD (Verified)',
      selectedWeight: 0,
    },
    {
      id: 'g5',
      callsign: 'G-TIGRIS-CL',
      voterType: 'BoostVoter (veMEZO)',
      address: '0xD245...8e03',
      angleRad: 1.38,
      distanceNorm: 0.81,
      bribeMusdValue: 9100,
      totalVotes: 390,
      bribePer1kVotes: 23.33,
      whitelistedBribeToken: 'MUSD (Verified)',
      selectedWeight: 0,
    },
  ]);

  const [flightPlans, setFlightPlans] = useState<RegisteredFlightPlan[]>([
    {
      regId: 1,
      nftType: 'veBTC',
      tokenId: 1042,
      votingPower: 1.85,
      route: 'REPAY_TROVE_DEBT',
      autoMaxLock: true,
      lastEpochHarvestMusd: 342.8,
      status: 'LOCKED_ON_RADAR',
    },
    {
      regId: 2,
      nftType: 'veMEZO',
      tokenId: 619,
      votingPower: 48500,
      route: 'COMPOUND_SMUSD',
      autoMaxLock: true,
      lastEpochHarvestMusd: 219.4,
      status: 'LOCKED_ON_RADAR',
    },
  ]);

  const [selectedGaugeId, setSelectedGaugeId] = useState<string>('g1');
  const [troveDebtRemaining, setTroveDebtRemaining] = useState<number>(4820.0);
  const [compoundedSMusd, setCompoundedSMusd] = useState<number>(1940.5);
  const [spCompounded, setSpCompounded] = useState<number>(1120.0);
  const [protocolFeeTreasury, setProtocolFeeTreasury] = useState<number>(184.25);

  // 60fps Canvas & DOM refs (Zero React state re-renders!)
  const radarCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const squawkClockRef = useRef<HTMLSpanElement | null>(null);
  const sweepAzimuthRef = useRef<HTMLSpanElement | null>(null);

  useEffect(() => {
    fetchRadarTelemetry().then(setTelemetry);
    const id = setInterval(() => {
      fetchRadarTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  // 60fps Canvas 2D Air-Traffic Radar Scope + DOM Ref Telemetry
  useEffect(() => {
    let rafId: number;
    let sweepAngle = 0;

    const renderRadar = (now: number) => {
      sweepAngle = (now * 0.0014) % (Math.PI * 2);

      if (sweepAzimuthRef.current) {
        const deg = Math.floor((sweepAngle * 180) / Math.PI)
          .toString()
          .padStart(3, '0');
        sweepAzimuthRef.current.textContent = `${deg}°`;
      }

      if (squawkClockRef.current) {
        // Countdown to next Thursday 00:00 UTC epoch flip
        // Mezo vote epochs flip weekly at Thursday 00:00 UTC (Unix epoch began on a Thursday).
        const WEEK = 7 * 86_400;
        const nowSec = Math.floor(Date.now() / 1000);
        const secRemaining = WEEK - (nowSec % WEEK);
        const hrs = Math.floor(secRemaining / 3600)
          .toString()
          .padStart(2, '0');
        const mins = Math.floor((secRemaining % 3600) / 60)
          .toString()
          .padStart(2, '0');
        const secs = (secRemaining % 60).toString().padStart(2, '0');
        squawkClockRef.current.textContent = `${hrs}:${mins}:${secs}`;
      }

      const canvas = radarCanvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          const w = canvas.width;
          const h = canvas.height;
          const cx = w / 2;
          const cy = h / 2;
          const maxR = Math.min(cx, cy) - 24;

          ctx.clearRect(0, 0, w, h);

          // Deep phosphor scope background
          ctx.fillStyle = 'rgba(0,0,0,0)';
          ctx.fillRect(0, 0, w, h);

          // Concentric range rings
          [0.25, 0.5, 0.75, 1.0].forEach((frac) => {
            ctx.beginPath();
            ctx.arc(cx, cy, maxR * frac, 0, Math.PI * 2);
            ctx.strokeStyle = 'rgba(140, 170, 255, 0.16)';
            ctx.lineWidth = frac === 1.0 ? 1.8 : 1;
            ctx.stroke();
          });

          // Crosshair axes
          ctx.beginPath();
          ctx.moveTo(cx - maxR, cy);
          ctx.lineTo(cx + maxR, cy);
          ctx.moveTo(cx, cy - maxR);
          ctx.lineTo(cx, cy + maxR);
          ctx.strokeStyle = 'rgba(140, 170, 255, 0.09)';
          ctx.lineWidth = 1;
          ctx.stroke();

          // Rotating radar phosphor sweep sector
          const grad = ctx.createConicGradient(sweepAngle - 0.55, cx, cy);
          grad.addColorStop(0, 'rgba(159, 194, 255, 0)');
          grad.addColorStop(0.08, 'rgba(159, 194, 255, 0.38)');
          grad.addColorStop(0.09, 'rgba(159, 194, 255, 0)');
          ctx.fillStyle = grad;
          ctx.beginPath();
          ctx.arc(cx, cy, maxR, 0, Math.PI * 2);
          ctx.fill();

          // Leading sweep arm line
          ctx.beginPath();
          ctx.moveTo(cx, cy);
          ctx.lineTo(cx + Math.cos(sweepAngle) * maxR, cy + Math.sin(sweepAngle) * maxR);
          ctx.strokeStyle = '#9FC2FF';
          ctx.lineWidth = 2;
          ctx.stroke();

          // Plot Mezo Voter & BoostVoter Gauge Blips
          gauges.forEach((g) => {
            const gx = cx + Math.cos(g.angleRad) * (maxR * g.distanceNorm);
            const gy = cy + Math.sin(g.angleRad) * (maxR * g.distanceNorm);

            // Cyan flight-path vector if weight > 0
            if (g.selectedWeight > 0) {
              ctx.beginPath();
              ctx.moveTo(cx, cy);
              ctx.lineTo(gx, gy);
              ctx.strokeStyle = 'rgba(255, 255, 255, 0.45)';
              ctx.setLineDash([4, 4]);
              ctx.lineWidth = 1.5;
              ctx.stroke();
              ctx.setLineDash([]);
            }

            // Target blip halo
            const isSelected = g.id === selectedGaugeId;
            const blipRadius = 5 + (g.bribePer1kVotes / 60) * 6;
            ctx.beginPath();
            ctx.arc(gx, gy, blipRadius + 4, 0, Math.PI * 2);
            ctx.strokeStyle = isSelected ? '#E59A38' : 'rgba(127, 162, 255, 0.5)';
            ctx.lineWidth = isSelected ? 2 : 1;
            ctx.stroke();

            // Target core
            ctx.beginPath();
            ctx.arc(gx, gy, blipRadius, 0, Math.PI * 2);
            ctx.fillStyle = g.selectedWeight > 0 ? '#E59A38' : '#9FC2FF';
            ctx.fill();

            // Callsign transponder tag
            ctx.font = '500 11px Inter, sans-serif';
            ctx.fillStyle = isSelected ? '#E59A38' : '#9FC2FF';
            ctx.fillText(`${g.callsign} [${g.selectedWeight}%]`, gx + 12, gy - 4);
            ctx.fillStyle = 'rgba(255, 255, 255, 0.55)';
            ctx.fillText(`$${g.bribePer1kVotes.toFixed(1)}/1kV`, gx + 12, gy + 10);
          });

          // Central Approach Control Tower (veBTC / veMEZO Operator)
          ctx.beginPath();
          ctx.arc(cx, cy, 7, 0, Math.PI * 2);
          ctx.fillStyle = 'rgba(255, 255, 255, 0.55)';
          ctx.fill();
        }
      }

      rafId = requestAnimationFrame(renderRadar);
    };

    rafId = requestAnimationFrame(renderRadar);
    return () => cancelAnimationFrame(rafId);
  }, [gauges, selectedGaugeId]);

  const handleAutoOptimizeVectors = () => {
    radarAudio.sonarPing(1480);
    // Sort by bribePer1kVotes and allocate 50% / 35% / 15% to top 3 gauges
    const sorted = [...gauges].sort((a, b) => b.bribePer1kVotes - a.bribePer1kVotes);
    const weightsMap: Record<string, number> = {
      [sorted[0].id]: 50,
      [sorted[1].id]: 35,
      [sorted[2].id]: 15,
    };
    setGauges((prev) =>
      prev.map((g) => ({
        ...g,
        selectedWeight: weightsMap[g.id] ?? 0,
      }))
    );
    onLogEvent?.("Relay vectors auto-optimized: 50% / 35% / 15% top yield allocation.");
  };

  const handleRegisterNonCustodialNft = () => {
    radarAudio.cockpitToggle();
    const newPlan: RegisteredFlightPlan = {
      regId: flightPlans.length + 1,
      nftType: selectedNftType,
      tokenId: inputTokenId,
      votingPower: selectedNftType === 'veBTC' ? 1.42 : 32000,
      route: selectedRoute,
      autoMaxLock,
      lastEpochHarvestMusd: 0,
      status: 'LOCKED_ON_RADAR',
    };
    setFlightPlans([newPlan, ...flightPlans]);
    setInputTokenId(inputTokenId + 1);
    onLogEvent?.(`Registered non-custodial ${selectedNftType} #${inputTokenId} with route ${selectedRoute}.`);
  };

  const handleExecuteEpochRelaySweep = () => {
    radarAudio.epochSweepLock();
    const grossHarvestMusd = 610.0;
    const protocolFee = grossHarvestMusd * 0.02; // 2% performance fee
    const keeperBounty = grossHarvestMusd * 0.005; // 0.5% keeper tip
    const netYield = grossHarvestMusd - protocolFee - keeperBounty;

    setProtocolFeeTreasury((p) => p + protocolFee);
    if (selectedRoute === 'REPAY_TROVE_DEBT') {
      setTroveDebtRemaining((d) => Math.max(1800, d - netYield));
    } else if (selectedRoute === 'COMPOUND_SMUSD') {
      setCompoundedSMusd((s) => s + netYield);
    } else {
      setSpCompounded((sp) => sp + netYield);
    }

    setFlightPlans((prev) =>
      prev.map((fp) => ({
        ...fp,
        lastEpochHarvestMusd: Number((netYield / prev.length).toFixed(2)),
        status: 'SWEPT_THIS_EPOCH',
      }))
    );
    onLogEvent?.(`Epoch sweep executed: ${grossHarvestMusd.toFixed(2)} MUSD harvested and swapped.`);
  };

  const routeMeta: Record<YieldRoute, { label: string; short: string; value: string }> = {
    REPAY_TROVE_DEBT: { label: 'Repay my trove debt', short: 'Repay debt', value: `${troveDebtRemaining.toFixed(0)} MUSD left` },
    COMPOUND_SMUSD: { label: 'Compound into sMUSD', short: 'sMUSD', value: `${compoundedSMusd.toFixed(0)} sMUSD` },
    PROVIDE_STABILITY_POOL: { label: 'Deposit to Stability Pool', short: 'Stability Pool', value: `${spCompounded.toFixed(0)} MUSD` },
  };
  const bestGauge = [...gauges].sort((a, b) => b.bribePer1kVotes - a.bribePer1kVotes)[0];
  const sel = gauges.find((g) => g.id === selectedGaugeId) ?? gauges[0];
  const weightTotal = gauges.reduce((a, g) => a + g.selectedWeight, 0);
  const projected = gauges.reduce((a, g) => a + (g.selectedWeight / 100) * g.bribePer1kVotes, 0);

  return (
    <div className="space-y-6">
      <PageHeader
        code="07"
        pillar="Governance"
        title="Vote every epoch, keep your NFT"
        description="Relay votes your veBTC or veMEZO for the best bribes each epoch, harvests only whitelisted rewards and turns them into MUSD. Your lock never leaves your wallet."
        actions={
          <>
            <Button variant="primary" onClick={handleExecuteEpochRelaySweep}>
              <Zap className="h-4 w-4" /> Execute sweep
            </Button>
            <Button onClick={handleAutoOptimizeVectors}>Auto-optimize votes</Button>
          </>
        }
        stats={[
          { label: 'Epoch flips in', value: <span ref={squawkClockRef}>—</span>, tone: 'copper' },
          { label: 'veBTC locks', value: fmt(telemetry.veBtcCount) },
          { label: 'veMEZO locks', value: fmt(telemetry.veMezoCount) },
          { label: 'BoostVoter gauges', value: fmt(telemetry.boostGaugeCount), sub: `${fmt(telemetry.boostTotalWeight, 1)} total weight` },
        ]}
      />

      <RelayLive wallet={wallet} onLogEvent={onLogEvent} />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-5" eyebrow="Relay a lock" title="Approve once, vote every epoch" glow>
          <div className="space-y-5">
            <Segmented
              value={selectedNftType}
              onChange={(v) => {
                radarAudio.cockpitToggle();
                setSelectedNftType(v);
              }}
              options={[
                { value: 'veBTC' as const, label: 'veBTC' },
                { value: 'veMEZO' as const, label: 'veMEZO' },
              ]}
            />
            <Field label={`${selectedNftType} token ID`}>
              <NumberInput value={inputTokenId} onChange={setInputTokenId} />
            </Field>
            <div>
              <div className="label mb-2">Send rewards to</div>
              <Segmented
                value={selectedRoute}
                onChange={(v) => {
                  radarAudio.cockpitToggle();
                  setSelectedRoute(v);
                }}
                options={(Object.keys(routeMeta) as YieldRoute[]).map((r) => ({ value: r, label: routeMeta[r].short }))}
              />
              <div className="mt-2 font-mono text-[12px] text-faint">{routeMeta[selectedRoute].value}</div>
            </div>
            <KeyValue k="Top gauge now" v={`${bestGauge.callsign} · $${bestGauge.bribePer1kVotes.toFixed(2)}/1k`} />
            <Toggle label="Auto max-lock each epoch" on={autoMaxLock} onChange={setAutoMaxLock} />
            <Button variant="primary" size="lg" className="w-full" onClick={handleRegisterNonCustodialNft}>
              {walletAddress ? 'Approve operator & relay my vote' : 'Relay my vote'}
            </Button>
          </div>
        </Panel>

        <Panel className="lg:col-span-7" eyebrow="Gauge radar" title="Where this epoch's bribes are" right={<span ref={sweepAzimuthRef} className="font-mono text-[12px] text-muted">—</span>}>
          <canvas ref={radarCanvasRef} width={440} height={440} className="mx-auto h-auto w-full max-w-[440px]" />
          <p className="mt-2 text-center text-[12px] text-faint">Blip size shows bribe per 1k votes. Dashed lines are your vote.</p>
        </Panel>
      </div>

      <Panel
        eyebrow="This epoch"
        title="Gauges"
        flush
        right={<span className="font-mono text-[12px] text-muted">{weightTotal}% allocated · blended ${projected.toFixed(2)}/1k</span>}
      >
        <Table head={['Gauge', 'Bribes', 'Per 1k votes', 'Your vote']} cols="1.5fr 110px 120px 100px">
          {gauges.map((g) => (
            <Row
              key={g.id}
              cols="1.5fr 110px 120px 100px"
              active={g.id === selectedGaugeId}
              onClick={() => {
                radarAudio.sonarPing(900);
                setSelectedGaugeId(g.id);
              }}
            >
              <span>
                {g.callsign}
                <span className="block text-[12px] text-faint">
                  {g.voterType} · {g.whitelistedBribeToken}
                </span>
              </span>
              <span className="text-right font-mono">${g.bribeMusdValue.toLocaleString()}</span>
              <span className="text-right font-mono text-ice">${g.bribePer1kVotes.toFixed(2)}</span>
              <span className="text-right">
                <span className={`inline-flex h-7 items-center rounded-full px-2.5 font-mono text-[12px] ${g.selectedWeight ? 'bg-copper/15 text-copper' : 'bg-white/[0.04] text-faint'}`}>
                  {g.selectedWeight}%
                </span>
              </span>
            </Row>
          ))}
        </Table>
        <div className="border-t border-line px-6 py-3 font-mono text-[12px] text-faint">
          Selected {sel.callsign} · protocol fees ${protocolFeeTreasury.toFixed(2)} · 2% fee and 0.5% keeper tip per sweep
        </div>
      </Panel>

      <div className="grid gap-6 md:grid-cols-3">
        <Panel eyebrow="Safeguard" title="Zero custody">
          <ul className="space-y-2 text-[14px] text-muted">
            <li>NFTs stay in your wallet.</li>
            <li>Voter checks isApprovedOrOwner.</li>
            <li>Revoke the approval any time.</li>
          </ul>
        </Panel>
        <Panel eyebrow="Safeguard" title="Whitelisted bribes only">
          <ul className="space-y-2 text-[14px] text-muted">
            <li>Unknown tokens never reach the router.</li>
            <li>Broken tokens cannot revert the epoch.</li>
          </ul>
          <div className="mt-4">
            <Callout
              tone={whitelistGuardTest === 'PASS' ? 'pos' : 'neg'}
              title={whitelistGuardTest === 'PASS' ? 'All tokens verified' : 'Rogue token blocked'}
              action={
                <Button
                  size="sm"
                  onClick={() => {
                    radarAudio.sonarPing(whitelistGuardTest === 'PASS' ? 420 : 1200);
                    setWhitelistGuardTest(whitelistGuardTest === 'PASS' ? 'BLOCKED_ROGUE_TOKEN' : 'PASS');
                  }}
                >
                  {whitelistGuardTest === 'PASS' ? 'Inject rogue token' : 'Reset'}
                </Button>
              }
            />
          </div>
        </Panel>
        <Panel eyebrow="Safeguard" title="Rewards become MUSD">
          <ul className="space-y-2 text-[14px] text-muted">
            <li>Bribes swap to MUSD on Tigris.</li>
            <li>Then repay debt, enter sMUSD or the Stability Pool.</li>
          </ul>
          <a href={`${EXPLORER}/address/${MEZO_VE_CONTRACTS.RelayVault}`} target="_blank" rel="noreferrer" className="mt-4 inline-flex items-center gap-1 font-mono text-[12px] text-muted hover:text-fg">
            RelayVault <ArrowUpRight className="h-3 w-3" />
          </a>
        </Panel>
      </div>

      <Panel eyebrow="Plans" title="Relayed locks" flush right={<span className="font-mono text-[12px] text-muted">{flightPlans.length} registered</span>}>
        <Table head={['Lock', 'Power', 'Rewards to', 'Last sweep']} cols="1fr 120px 1fr 140px">
          {flightPlans.map((fp) => (
            <Row key={fp.regId} cols="1fr 120px 1fr 140px">
              <span>
                {fp.nftType} #{fp.tokenId}
                <span className="ml-2 text-[12px] text-faint">{fp.autoMaxLock ? 'auto max-lock' : 'manual lock'}</span>
              </span>
              <span className="text-right font-mono">{fp.votingPower.toLocaleString()}</span>
              <span className="text-right text-muted">{routeMeta[fp.route].label}</span>
              <span className="text-right font-mono">
                {fp.status === 'SWEPT_THIS_EPOCH' ? <span className="text-pos">+{fp.lastEpochHarvestMusd} MUSD</span> : <span className="text-faint">waiting</span>}
              </span>
            </Row>
          ))}
        </Table>
      </Panel>
    </div>
  );
}

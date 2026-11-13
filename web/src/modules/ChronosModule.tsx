import { useEffect, useRef, useState } from 'react';
import { Button, EXPLORER, Field, KeyValue, NumberInput, PageHeader, Panel, Row, Table , SimDivider } from '../ui/kit';
import { ChronosLive, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import {
  ArrowUpRight,
  Bell,
  Layers,
  Scissors,
  Zap,
} from 'lucide-react';
import {
  CHRONOS_MEZO_ADDRESSES,
  fetchTreasurySnapshot,
  TreasuryChainSnapshot,
} from '../lib/meridianChain';
import { swissAudio } from '../lib/fixingBellAudio';

interface TenorSeries {
  seriesId: number;
  code: '30D' | '90D' | '180D';
  days: number;
  fixedRateBps: number; // e.g. 465 = 4.65%
  ptDiscountPrice: number;
  ytImpliedPrice: number;
  totalLockedMusd: number;
  auctionVolumeMusd: number;
}

interface AuctionBidTick {
  rateBps: number;
  bidMusd: number;
  cumulativeMusd: number;
}

export function ChronosModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [snapshot, setSnapshot] = useState<TreasuryChainSnapshot>({
    blockNumber: 4_812_980n,
    btcPriceUsd: 76559.43,
    sMusdSupply: 897415.12,
    sMusdYieldIndex: 1.00024,
    spDepositsMusd: 86209195.88,
    minNetDebtMusd: 1800,
    borrowRatePct: 0.1,
    isRecoveryMode: false,
    isLive: false,
  });

  const [selectedSeriesId, setSelectedSeriesId] = useState<number>(1);

  const [seriesList, setSeriesList] = useState<TenorSeries[]>([
    {
      seriesId: 0,
      code: '30D',
      days: 30,
      fixedRateBps: 445,
      ptDiscountPrice: 0.9963,
      ytImpliedPrice: 0.0037,
      totalLockedMusd: 184000,
      auctionVolumeMusd: 42000,
    },
    {
      seriesId: 1,
      code: '90D',
      days: 90,
      fixedRateBps: 525,
      ptDiscountPrice: 0.9871,
      ytImpliedPrice: 0.0129,
      totalLockedMusd: 312500,
      auctionVolumeMusd: 94000,
    },
    {
      seriesId: 2,
      code: '180D',
      days: 180,
      fixedRateBps: 610,
      ptDiscountPrice: 0.9699,
      ytImpliedPrice: 0.0301,
      totalLockedMusd: 265000,
      auctionVolumeMusd: 78500,
    },
  ]);

  const [stripAmountMusd, setStripAmountMusd] = useState<number>(10000);
  const [bidAmountMusd, setBidAmountMusd] = useState<number>(5000);
  const [bidMaxRateBps, setBidMaxRateBps] = useState<number>(540);
  const [zapBtcColl, setZapBtcColl] = useState<number>(0.18);
  const [zapMusdBorrow, setZapMusdBorrow] = useState<number>(7500);
  const [userPtBalance, setUserPtBalance] = useState<number>(15000);
  const [userYtBalance, setUserYtBalance] = useState<number>(15000);
  const [protocolRevenueMusd, setProtocolRevenueMusd] = useState<number>(2840.5);

  // One bid ladder per tenor (keyed by seriesId), so each tenor clears against its own demand.
  const [bidLadders, setBidLadders] = useState<Record<number, AuctionBidTick[]>>({
    0: [
      { rateBps: 400, bidMusd: 16000, cumulativeMusd: 16000 },
      { rateBps: 425, bidMusd: 26000, cumulativeMusd: 42000 },
      { rateBps: 445, bidMusd: 36000, cumulativeMusd: 78000 },
      { rateBps: 470, bidMusd: 18000, cumulativeMusd: 96000 },
      { rateBps: 500, bidMusd: 12000, cumulativeMusd: 108000 },
    ],
    1: [
      { rateBps: 450, bidMusd: 18000, cumulativeMusd: 18000 },
      { rateBps: 485, bidMusd: 26000, cumulativeMusd: 44000 },
      { rateBps: 525, bidMusd: 34000, cumulativeMusd: 78000 },
      { rateBps: 560, bidMusd: 21000, cumulativeMusd: 99000 },
      { rateBps: 615, bidMusd: 15000, cumulativeMusd: 114000 },
    ],
    2: [
      { rateBps: 540, bidMusd: 15000, cumulativeMusd: 15000 },
      { rateBps: 575, bidMusd: 24000, cumulativeMusd: 39000 },
      { rateBps: 610, bidMusd: 38000, cumulativeMusd: 77000 },
      { rateBps: 640, bidMusd: 20000, cumulativeMusd: 97000 },
      { rateBps: 680, bidMusd: 12000, cumulativeMusd: 109000 },
    ],
  });
  const bidLadder = bidLadders[selectedSeriesId] ?? bidLadders[1];
  const setBidLadder = (ladder: AuctionBidTick[]) =>
    setBidLadders((prev) => ({ ...prev, [selectedSeriesId]: ladder }));

  // 60fps DOM refs for Swiss Maturity Chronometer (zero React state re-renders)
  const swissClockRef = useRef<HTMLSpanElement | null>(null);
  const liveYieldTickRef = useRef<HTMLSpanElement | null>(null);

  useEffect(() => {
    fetchTreasurySnapshot().then(setSnapshot);
    const id = setInterval(() => {
      fetchTreasurySnapshot().then(setSnapshot);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let rafId: number;
    const start = performance.now();

    const loop = (now: number) => {
      if (swissClockRef.current) {
        const d = new Date();
        const cs = String(Math.floor(d.getMilliseconds() / 10)).padStart(2, '0');
        swissClockRef.current.textContent = `FIXING CLOCK ${d.toISOString().slice(11, 19)}.${cs} UTC`;
      }
      if (liveYieldTickRef.current) {
        const accrued = 148.24 + ((now - start) / 1000) * 0.0185;
        liveYieldTickRef.current.textContent = `${accrued.toFixed(5)} MUSD`;
      }
      rafId = requestAnimationFrame(loop);
    };

    rafId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(rafId);
  }, []);

  const activeSeries = seriesList[selectedSeriesId] || seriesList[1];
  const variableSmusdAprPct = 6.45;

  const handleStripMusd = () => {
    swissAudio.relayStep();
    if (stripAmountMusd <= 0) return;
    setUserPtBalance((p) => p + stripAmountMusd);
    setUserYtBalance((y) => y + stripAmountMusd);
    setSeriesList((prev) =>
      prev.map((s) =>
        s.seriesId === selectedSeriesId
          ? { ...s, totalLockedMusd: s.totalLockedMusd + stripAmountMusd }
          : s
      )
    );
    onLogEvent?.(`Stripped ${stripAmountMusd} sMUSD into ${activeSeries.code} PT and YT.`);
  };

  const handleSubmitBatchBid = () => {
    swissAudio.relayStep();
    if (bidAmountMusd <= 0) return;
    const updated = [...bidLadder, { rateBps: bidMaxRateBps, bidMusd: bidAmountMusd, cumulativeMusd: 0 }]
      .sort((a, b) => a.rateBps - b.rateBps);
    let cum = 0;
    const recomputed = updated.map((row) => {
      cum += row.bidMusd;
      return { ...row, cumulativeMusd: cum };
    });
    setBidLadder(recomputed);
    onLogEvent?.(`Batch bid posted: ${bidAmountMusd} MUSD at max ${(bidMaxRateBps / 100).toFixed(2)}%.`);
  };

  const handleSettleFixingAuction = () => {
    swissAudio.fixingBell();
    // Uniform clearing rate = weighted median tick where supply (~75,000 PT) meets demand
    const targetSupply = 75000;
    const clearingRow =
      bidLadder.find((r) => r.cumulativeMusd >= targetSupply) ||
      bidLadder[Math.floor(bidLadder.length / 2)];
    const newBps = clearingRow.rateBps;
    const newDiscount = Number(
      (1 - (newBps / 10000) * (activeSeries.days / 365)).toFixed(4)
    );

    setSeriesList((prev) =>
      prev.map((s) =>
        s.seriesId === selectedSeriesId
          ? {
              ...s,
              fixedRateBps: newBps,
              ptDiscountPrice: newDiscount,
              ytImpliedPrice: Number((1 - newDiscount).toFixed(4)),
              auctionVolumeMusd: s.auctionVolumeMusd + 25000,
            }
          : s
      )
    );
    setProtocolRevenueMusd((r) => r + 62.5);
    onLogEvent?.(`Chronos fixing settled at ${(newBps / 100).toFixed(2)}% clearing rate.`);
  };

  const zapCollUsd = zapBtcColl * snapshot.btcPriceUsd;
  const zapIcrPct = (zapCollUsd / (zapMusdBorrow + 200)) * 100;
  const upfrontBorrowFeeMusd = (zapMusdBorrow * snapshot.borrowRatePct) / 100;
  const upfrontYtSaleProceedsMusd = zapMusdBorrow * activeSeries.ytImpliedPrice;
  const netEffectiveCostMusd = upfrontBorrowFeeMusd - upfrontYtSaleProceedsMusd;

  const handleExecuteZeroFeeTroveZap = () => {
    swissAudio.fixingBell();
    setUserPtBalance((p) => p + zapMusdBorrow);
    setSeriesList((prev) =>
      prev.map((s) =>
        s.seriesId === selectedSeriesId
          ? { ...s, totalLockedMusd: s.totalLockedMusd + zapMusdBorrow }
          : s
      )
    );
    onLogEvent?.(`Zero-fee Trove Zap executed: minted ${zapMusdBorrow} MUSD into ${activeSeries.code} PT.`);
  };

  const pct = (bps: number) => `${(bps / 100).toFixed(2)}%`;
  const num = (n: number) => n.toLocaleString('en-US', { maximumFractionDigits: 0 });
  const maturity = (days: number) =>
    new Date(Date.now() + days * 86400000).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }).toUpperCase();
  const totalCleared = seriesList.reduce((a, s) => a + s.auctionVolumeMusd, 0);

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="04"
        pillar="Yield"
        title="Fixed MUSD rates, set by auction"
        description="Split sMUSD into principal and yield tokens. Each epoch a uniform-price auction sets one fixed rate per tenor."
        actions={
          <Button variant="primary" onClick={handleSettleFixingAuction}>
            <Bell className="h-4 w-4" /> Settle {activeSeries.code} fixing
          </Button>
        }
        stats={[
          ...seriesList.map((s) => ({
            label: `${s.code} fixed`,
            value: pct(s.fixedRateBps),
            sub: `${chainStats?.chronos.lockedBySeries[s.seriesId] != null ? num(chainStats.chronos.lockedBySeries[s.seriesId]!) : '—'} MUSD locked on-chain · sample fixing`,
            tone: (s.seriesId === selectedSeriesId ? 'copper' : 'default') as 'copper' | 'default',
          })),
          { label: 'sMUSD floating', value: `${variableSmusdAprPct.toFixed(2)}%`, sub: 'variable reference', tone: 'muted' as const },
        ]}
      />

      <ChronosLive wallet={wallet} onLogEvent={onLogEvent} tenorCode={activeSeries.code} chainSeriesId={activeSeries.seriesId + 1} />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-7" eyebrow="Term structure" title="Yield curve" glow right={<span className="font-mono text-[12px] text-muted">{num(totalCleared)} MUSD cleared</span>}>
          <svg viewBox="0 0 600 260" className="w-full">
            {[0, 1, 2, 3, 4].map((i) => {
              const y = 30 + i * 50;
              return (
                <g key={i}>
                  <line x1="44" x2="590" y1={y} y2={y} stroke="rgba(255,255,255,0.06)" />
                  <text x="0" y={y + 4} fontSize="10" fontFamily="Geist Mono, monospace" fill="#5C626B">
                    {(8 - i * 1.25).toFixed(2)}%
                  </text>
                </g>
              );
            })}
            {(() => {
              const y = (r: number) => 230 - ((r - 3) / 5) * 200;
              const sm = y(variableSmusdAprPct);
              const pts = seriesList.map((s, i) => ({ x: [110, 330, 560][i], y: y(s.fixedRateBps / 100), s }));
              const d = `M${pts[0].x},${pts[0].y} C${pts[0].x + 90},${pts[0].y} ${pts[1].x - 90},${pts[1].y} ${pts[1].x},${pts[1].y} S${pts[2].x - 90},${pts[2].y} ${pts[2].x},${pts[2].y}`;
              return (
                <g>
                  <line x1="44" x2="590" y1={sm} y2={sm} stroke="#8A9099" strokeDasharray="3 4" />
                  <text x="48" y={sm - 8} fontSize="10" fontFamily="Geist Mono, monospace" fill="#8A9099">
                    sMUSD floating {variableSmusdAprPct.toFixed(2)}%
                  </text>
                  <path d={d} fill="none" stroke="#9FC2FF" strokeWidth="2" />
                  {pts.map(({ x, y: py, s }) => {
                    const on = s.seriesId === selectedSeriesId;
                    return (
                      <g key={s.code} className="cursor-pointer" onClick={() => { swissAudio.relayStep(); setSelectedSeriesId(s.seriesId); }}>
                        <line x1={x} x2={x} y1={py} y2="230" stroke="rgba(255,255,255,0.08)" />
                        <circle cx={x} cy={py} r={on ? 7 : 5} fill={on ? '#E59A38' : '#111317'} stroke={on ? '#E59A38' : '#9FC2FF'} strokeWidth="1.5" />
                        <text x={x} y={py - 15} textAnchor="middle" fontSize="12" fontFamily="Geist Mono, monospace" fill="#ECEEF1">
                          {pct(s.fixedRateBps)}
                        </text>
                        <text x={x} y="252" textAnchor="middle" fontSize="10" fontFamily="Geist Mono, monospace" fill="#5C626B">
                          {s.days}D
                        </text>
                      </g>
                    );
                  })}
                </g>
              );
            })()}
          </svg>
        </Panel>

        <Panel className="lg:col-span-5" eyebrow="Series" title="Principal tokens" flush>
          <div className="divide-y divide-line">
            {seriesList.map((s) => (
              <Row key={s.seriesId} cols="1fr auto" active={s.seriesId === selectedSeriesId} onClick={() => { swissAudio.relayStep(); setSelectedSeriesId(s.seriesId); }}>
                <span>
                  <span className="text-[15px]">PT-MUSD · {s.code}</span>
                  <span className="mt-0.5 block font-mono text-[11px] text-faint">matures {maturity(s.days)}</span>
                </span>
                <span className="text-right">
                  <span className="block font-mono text-[15px] text-copper">{pct(s.fixedRateBps)}</span>
                  <span className="block font-mono text-[11px] text-faint">PT {s.ptDiscountPrice.toFixed(4)}</span>
                </span>
              </Row>
            ))}
          </div>
        </Panel>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <Panel eyebrow={`01 · ${activeSeries.code}`} title="Strip MUSD" right={<Scissors className="h-4 w-4 text-faint" />}>
          <p className="text-[14px] text-muted">1 sMUSD becomes 1 PT plus 1 YT. PT redeems 1:1 at maturity; YT earns every coupon until then.</p>
          <div className="mt-5 grid grid-cols-2 gap-3">
            <div className="rounded-xl border border-line bg-raised p-4">
              <div className="label">PT price</div>
              <div className="mt-1 font-mono text-[20px]">{activeSeries.ptDiscountPrice.toFixed(4)}</div>
              <div className="text-[12px] text-muted">{pct(activeSeries.fixedRateBps)} locked</div>
            </div>
            <div className="rounded-xl border border-line bg-raised p-4">
              <div className="label">YT price</div>
              <div className="mt-1 font-mono text-[20px]">{activeSeries.ytImpliedPrice.toFixed(4)}</div>
              <div className="text-[12px] text-muted">{(1 / activeSeries.ytImpliedPrice).toFixed(1)}× exposure</div>
            </div>
          </div>
          <div className="mt-5 space-y-3">
            <Field label="Amount">
              <NumberInput value={stripAmountMusd} onChange={setStripAmountMusd} step={1000} min={100} suffix="MUSD" />
            </Field>
            <Button variant="primary" className="w-full" onClick={handleStripMusd}>Strip into PT + YT</Button>
          </div>
          <div className="mt-4 font-mono text-[12px] text-muted">
            Holding {num(userPtBalance)} PT · {num(userYtBalance)} YT
            <br />
            Accrued coupon <span ref={liveYieldTickRef} className="text-ice">—</span>
          </div>
        </Panel>

        <Panel eyebrow={`02 · ${activeSeries.code}`} title="Batch rate auction" right={<Layers className="h-4 w-4 text-faint" />} flush>
          <Table head={['Rate', 'Bid', 'Cumulative']} cols="1fr 90px 110px">
            {bidLadder.map((row, idx) => {
              const clearing = row.rateBps === activeSeries.fixedRateBps;
              return (
                <Row key={idx} cols="1fr 90px 110px" active={clearing}>
                  <span className="flex items-center gap-2 font-mono">
                    {pct(row.rateBps)}
                    {clearing && <span className="rounded-full border border-copper/50 px-1.5 text-[9px] text-copper">CLEARING</span>}
                  </span>
                  <span className="text-right font-mono text-muted">{num(row.bidMusd)}</span>
                  <span className="text-right font-mono">{num(row.cumulativeMusd)}</span>
                </Row>
              );
            })}
          </Table>
          <div className="grid grid-cols-2 gap-3 border-t border-line p-6">
            <Field label="Bid">
              <NumberInput value={bidAmountMusd} onChange={setBidAmountMusd} step={1000} suffix="MUSD" />
            </Field>
            <Field label="Rate">
              <NumberInput value={bidMaxRateBps} onChange={setBidMaxRateBps} step={5} suffix="BPS" />
            </Field>
            <Button className="col-span-2" onClick={handleSubmitBatchBid}>Post bid</Button>
            <div className="col-span-2 text-[12px] text-faint">Clears at the rate where cumulative demand reaches 75,000 PT.</div>
          </div>
        </Panel>

        <Panel eyebrow={`03 · ${activeSeries.code}`} title="BTC trove to fixed term" right={<Zap className="h-4 w-4 text-faint" />}>
          <p className="text-[14px] text-muted">
            One transaction opens a trove, mints MUSD and strips it. Selling the YT up front covers the {snapshot.borrowRatePct}% borrow fee.
          </p>
          <div className="mt-5 grid grid-cols-2 gap-3">
            <Field label="BTC">
              <NumberInput value={zapBtcColl} onChange={setZapBtcColl} step="0.02" />
            </Field>
            <Field label="MUSD to mint">
              <NumberInput value={zapMusdBorrow} onChange={setZapMusdBorrow} step={500} />
            </Field>
          </div>
          <div className="mt-4">
            <KeyValue k="Collateral ratio" v={`${zapIcrPct.toFixed(1)}%`} />
            <KeyValue k="Borrow fee" v={`−${upfrontBorrowFeeMusd.toFixed(2)}`} />
            <KeyValue k="YT sale credit" v={`+${upfrontYtSaleProceedsMusd.toFixed(2)}`} />
            <KeyValue k="Net up front" v={`+${Math.abs(netEffectiveCostMusd).toFixed(2)} MUSD`} strong tone="pos" />
          </div>
          <Button variant="primary" className="mt-5 w-full" onClick={handleExecuteZeroFeeTroveZap}>
            Zap into {activeSeries.code} PT
          </Button>
        </Panel>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 px-1 font-mono text-[12px] text-faint">
        <span ref={swissClockRef}>—</span>
        <span>Fees collected {protocolRevenueMusd.toFixed(2)} MUSD · min trove debt {snapshot.minNetDebtMusd} MUSD</span>
        <a href={EXPLORER} target="_blank" rel="noreferrer" className="flex items-center gap-1 hover:text-fg">
          sMUSD {CHRONOS_MEZO_ADDRESSES.sMUSD.slice(0, 10)}… <ArrowUpRight className="h-3 w-3" />
        </a>
      </div>
    </div>
  );
}

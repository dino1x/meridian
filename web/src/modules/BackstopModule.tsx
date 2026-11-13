import { useEffect, useRef, useState } from 'react';
import { Button, EXPLORER, Field, KeyValue, NumberInput, PageHeader, Panel, Segmented, Slider, StatusPill , SimDivider } from '../ui/kit';
import { VaultLive, live, useProtocolStats } from './onchain';
import type { ConnectedWallet } from '../lib/meridianChain';
import { ADDR } from '../lib/tx';
import {
  ArrowUpRight,
  Gavel,
  Plus,
} from 'lucide-react';
import {
  AuctionHouseTelemetry,
  BACKSTOP_MEZO_ADDRESSES,
  fetchAuctionTelemetry,
} from '../lib/meridianChain';
import { gavelAudio } from '../lib/gavelAudio';

interface LiquidationLot {
  lotId: number;
  catalogueRef: string;
  btcSize: number;
  elapsedMinutes: number; // 0 to 120 min (2-hour Dutch decay from 100% -> 92% of oracle)
  status: 'ON_THE_ROSTRUM' | 'HAMMERED_SOLD';
  hammerMusdPerBtc?: number;
  buyerPaddle?: string;
}

export function BackstopModule({ onLogEvent, wallet = null }: { onLogEvent?: (msg: string) => void; walletAddress?: string | null; wallet?: ConnectedWallet | null }) {
  const [telemetry, setTelemetry] = useState<AuctionHouseTelemetry>({
    blockNumber: 4_813_095n,
    btcPriceUsd: 76559.43,
    spDepositsMusd: 86209195.88,
    troveCount: 352,
    isRecoveryMode: false,
    isLive: false,
  });

  const [consignDepositMusd, setConsignDepositMusd] = useState<number>(10000);
  const [vaultPooledMusd, setVaultPooledMusd] = useState<number>(428_500);
  const [vaultShareNav, setVaultShareNav] = useState<number>(1.0685);
  const [buyerPremiumRevenue, setBuyerPremiumRevenue] = useState<number>(2_940.15);
  const [scrubberMinutes, setScrubberMinutes] = useState<number>(52);

  const [lots, setLots] = useState<LiquidationLot[]>([
    {
      lotId: 16,
      catalogueRef: 'LOT XVI — STABILITY POOL SEIZURE',
      btcSize: 0.42,
      elapsedMinutes: 52,
      status: 'ON_THE_ROSTRUM',
    },
    {
      lotId: 15,
      catalogueRef: 'LOT XV — RECOVERY MODE LIQUIDATION',
      btcSize: 0.28,
      elapsedMinutes: 84,
      status: 'HAMMERED_SOLD',
      hammerMusdPerBtc: 72272.1,
      buyerPaddle: 'PADDLE #408',
    },
    {
      lotId: 14,
      catalogueRef: 'LOT XIV — TROVE LIQUIDATION',
      btcSize: 0.65,
      elapsedMinutes: 68,
      status: 'HAMMERED_SOLD',
      hammerMusdPerBtc: 73088.7,
      buyerPaddle: 'PADDLE #119',
    },
  ]);

  const [selectedLotId, setSelectedLotId] = useState<number>(16);

  // 60fps Dutch Clock DOM refs (zero React re-renders!)
  const liveDutchPriceRef = useRef<HTMLDivElement | null>(null);
  const liveDiscountBpsRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    fetchAuctionTelemetry().then(setTelemetry);
    const id = setInterval(() => {
      fetchAuctionTelemetry().then(setTelemetry);
    }, 15000);
    return () => clearInterval(id);
  }, []);

  const selectedLot = lots.find((l) => l.lotId === selectedLotId) || lots[0];

  const calcDutchFactor = (mins: number) => {
    const clamped = Math.min(120, Math.max(0, mins));
    // Linearly decays from 1.0000 (100%) to 0.9200 (92%) over 120 minutes
    return 1.0 - (clamped / 120) * 0.08;
  };

  useEffect(() => {
    let rafId: number;
    const start = performance.now();

    const loop = (now: number) => {
      const subMin = ((now - start) / 1000) * 0.015;
      const mins =
        selectedLot.status === 'ON_THE_ROSTRUM'
          ? Math.min(120, scrubberMinutes + subMin)
          : selectedLot.elapsedMinutes;
      const factor = calcDutchFactor(mins);
      const askPerBtc = telemetry.btcPriceUsd * factor;
      const discountPct = (1 - factor) * 100;

      if (liveDutchPriceRef.current) {
        liveDutchPriceRef.current.textContent = `${askPerBtc.toLocaleString('en-US', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })} MUSD / BTC`;
      }
      if (liveDiscountBpsRef.current) {
        liveDiscountBpsRef.current.textContent = `${discountPct.toFixed(2)}% below oracle · ${(
          10 - discountPct
        ).toFixed(2)}% net margin to the vault`;
      }

      rafId = requestAnimationFrame(loop);
    };

    rafId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(rafId);
  }, [selectedLot, scrubberMinutes, telemetry.btcPriceUsd]);

  const handleConsignMusd = () => {
    gavelAudio.paddleRaise();
    if (consignDepositMusd <= 0) return;
    setVaultPooledMusd((v) => v + consignDepositMusd);
    onLogEvent?.(`Consigned ${consignDepositMusd} MUSD to Backstop Vault.`);
  };

  const handleStrikeGavel = (lot: LiquidationLot) => {
    if (lot.status !== 'ON_THE_ROSTRUM') return;
    gavelAudio.gavelStrike();
    const mins = lot.lotId === selectedLot.lotId ? scrubberMinutes : lot.elapsedMinutes;
    const factor = calcDutchFactor(mins);
    const hammerPerBtc = telemetry.btcPriceUsd * factor;
    const totalProceeds = hammerPerBtc * lot.btcSize;
    const buyerPremium = totalProceeds * 0.005; // 0.5% buyer's premium

    setLots((prev) =>
      prev.map((l) =>
        l.lotId === lot.lotId
          ? {
              ...l,
              elapsedMinutes: mins,
              status: 'HAMMERED_SOLD',
              hammerMusdPerBtc: Number(hammerPerBtc.toFixed(2)),
              buyerPaddle: 'PADDLE #712 (YOU)',
            }
          : l
      )
    );
    setVaultPooledMusd((v) => v + totalProceeds * 0.045);
    setVaultShareNav((n) => Number((n + 0.0042).toFixed(4)));
    setBuyerPremiumRevenue((r) => r + buyerPremium);
    onLogEvent?.(`Gavel struck! Lot #${lot.lotId} hammered sold at ${hammerPerBtc.toFixed(2)} MUSD/BTC.`);
  };

  const handleCatalogueNewLiquidationLot = () => {
    gavelAudio.paddleRaise();
    const nextId = Math.max(...lots.map((l) => l.lotId)) + 1;
    const newLot: LiquidationLot = {
      lotId: nextId,
      catalogueRef: `LOT #${nextId} — FRESH TROVE LIQUIDATION`,
      btcSize: 0.35,
      elapsedMinutes: 18,
      status: 'ON_THE_ROSTRUM',
    };
    setLots([newLot, ...lots]);
    setSelectedLotId(nextId);
    setScrubberMinutes(18);
    onLogEvent?.(`Catalogued fresh liquidation Lot #${nextId} (0.35 BTC).`);
  };

  const [filter, setFilter] = useState<'ALL' | 'OPEN' | 'SOLD'>('ALL');
  const shownLots = lots.filter((l) =>
    filter === 'ALL' ? true : filter === 'OPEN' ? l.status === 'ON_THE_ROSTRUM' : l.status === 'HAMMERED_SOLD'
  );
  const selMins = selectedLot.status === 'ON_THE_ROSTRUM' ? scrubberMinutes : selectedLot.elapsedMinutes;
  const usd = (n: number) => n.toLocaleString('en-US', { maximumFractionDigits: 0 });
  const isOpen = selectedLot.status === 'ON_THE_ROSTRUM';

  const chainStats = useProtocolStats();

  return (
    <div className="space-y-6">
      <PageHeader
        code="06"
        pillar="Peg"
        title="Seized BTC, sold by Dutch auction"
        description="The vault covers liquidations in the Stability Pool, auctions the seized BTC from 100% down to 92% of the oracle over two hours, and puts the proceeds back into coverage."
        actions={
          <Button variant="primary" onClick={handleCatalogueNewLiquidationLot}>
            <Plus className="h-4 w-4" /> Catalogue new lot
          </Button>
        }
        stats={[
          { label: 'Vault assets', value: live(chainStats?.backstop.assets, 2), sub: 'MUSD in BackstopVault, on-chain' },
          { label: 'Value per bstMUSD', value: live(chainStats?.backstop.sharePrice, 4), sub: 'MUSD, on-chain', tone: 'ice' },
          { label: 'Lots catalogued', value: live(chainStats?.backstop.lots), sub: 'Liquidation lots, on-chain' },
          { label: 'Mezo Stability Pool', value: `${(telemetry.spDepositsMusd / 1e6).toFixed(2)}M`, sub: 'MUSD deposited, live' },
        ]}
      />

      <VaultLive wallet={wallet} onLogEvent={onLogEvent} vault={ADDR.backstop} shareSymbol="bstMUSD" title="Consign MUSD to the vault" blurb="Deposit MUSD into the Backstop vault for bstMUSD. The vault covers Stability Pool liquidations and auctions the seized BTC." />

      <SimDivider />

      <div className="grid gap-6 lg:grid-cols-12">
        <Panel className="lg:col-span-7" eyebrow={`Lot ${toRoman(selectedLot.lotId)}`} title={`${selectedLot.btcSize} BTC · ${prettyRef(selectedLot.catalogueRef)}`} glow>
          <div className="relative flex aspect-[16/10] items-center justify-center overflow-hidden rounded-xl border border-line bg-raised">
            <LotCoin lot={selectedLot.lotId} size={selectedLot.btcSize} big />
            <svg viewBox="0 0 600 120" className="absolute bottom-0 left-0 w-full" preserveAspectRatio="none">
              <line x1="40" y1="20" x2="580" y2="100" stroke="#9FC2FF" strokeOpacity="0.8" strokeWidth="1.5" />
              <line x1="40" y1="100" x2="580" y2="100" stroke="rgba(255,255,255,0.12)" />
              <circle cx={40 + (selMins / 120) * 540} cy={20 + (selMins / 120) * 80} r="5" fill="#E59A38" />
            </svg>
            <span className="label absolute bottom-[100px] left-5">100% of oracle</span>
            <span className="label absolute bottom-3 right-5">92% · 120 min</span>
          </div>
          {isOpen && (
            <div className="mt-5">
              <Slider
                label="Time elapsed"
                valueLabel={`${scrubberMinutes} of 120 min`}
                min={5}
                max={120}
                value={scrubberMinutes}
                onChange={(v) => {
                  gavelAudio.paddleRaise();
                  setScrubberMinutes(v);
                }}
              />
            </div>
          )}
        </Panel>

        <Panel className="lg:col-span-5" eyebrow={isOpen ? 'Bidding open' : 'Sold'} title={isOpen ? 'Current asking price' : 'Hammer price'}>
          <div ref={liveDutchPriceRef} className="text-[30px] leading-tight tracking-tight text-fg">—</div>
          <div ref={liveDiscountBpsRef} className="mt-1 text-[13px] text-muted">—</div>
          <div className="mt-6">
            <KeyValue k="Lot size" v={`${selectedLot.btcSize} BTC`} />
            <KeyValue k="Oracle value" v={`$${usd(telemetry.btcPriceUsd * selectedLot.btcSize)}`} />
            <KeyValue k="Source" v={prettyRef(selectedLot.catalogueRef)} />
          </div>
          <Button variant="primary" size="lg" className="mt-6 w-full" disabled={!isOpen} onClick={() => handleStrikeGavel(selectedLot)}>
            <Gavel className="h-4 w-4" />
            {isOpen ? `Bid for ${selectedLot.btcSize} BTC` : `Sold to ${selectedLot.buyerPaddle ?? 'bidder'}`}
          </Button>
          <p className="mt-3 text-[12px] text-faint">A 0.50% buyer’s premium applies. Proceeds go straight back into the Stability Pool.</p>
        </Panel>
      </div>

      <Panel
        eyebrow="Catalogue"
        title="Lots"
        right={
          <Segmented
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'ALL' as const, label: 'All' },
              { value: 'OPEN' as const, label: 'Bidding open' },
              { value: 'SOLD' as const, label: 'Sold' },
            ]}
          />
        }
      >
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {shownLots.map((l) => {
            const open = l.status === 'ON_THE_ROSTRUM';
            return (
              <article key={l.lotId}>
                <button
                  type="button"
                  onClick={() => {
                    gavelAudio.paddleRaise();
                    setSelectedLotId(l.lotId);
                    if (open) setScrubberMinutes(l.elapsedMinutes);
                  }}
                  className={`relative flex aspect-square w-full items-center justify-center rounded-xl border bg-raised transition-colors ${
                    l.lotId === selectedLotId ? 'border-copper/70' : 'border-line hover:border-white/20'
                  }`}
                >
                  <LotCoin lot={l.lotId} size={l.btcSize} />
                  <span className="absolute right-3 top-3">
                    <StatusPill tone={open ? 'copper' : 'muted'}>{open ? 'Auction' : 'Sold'}</StatusPill>
                  </span>
                </button>
                <div className="mt-3 text-[16px]">
                  {l.btcSize} BTC · Lot {toRoman(l.lotId)}
                </div>
                <div className="text-[13px] text-muted">{prettyRef(l.catalogueRef)}</div>
                <div className="mt-2 font-mono text-[11px] text-faint">
                  {open
                    ? `Est. ${usd(telemetry.btcPriceUsd * 0.92 * l.btcSize)} – ${usd(telemetry.btcPriceUsd * l.btcSize)} MUSD`
                    : `Hammer ${usd((l.hammerMusdPerBtc ?? 0) * l.btcSize)} MUSD · ${l.buyerPaddle}`}
                </div>
                {open && (
                  <Button size="sm" className="mt-3" onClick={() => handleStrikeGavel(l)}>
                    Bid
                  </Button>
                )}
              </article>
            );
          })}
        </div>
      </Panel>

      <Panel eyebrow="Vault" title="Consign MUSD">
        <div className="grid gap-8 md:grid-cols-12">
          <p className="text-[15px] leading-relaxed text-muted md:col-span-6">
            Deposit MUSD and receive bstMUSD. The vault covers liquidations, sells the seized BTC at auction and returns every MUSD of proceeds to coverage.
          </p>
          <div className="flex items-end gap-3 md:col-span-6">
            <div className="flex-1">
              <Field label="Amount">
                <NumberInput value={consignDepositMusd} onChange={setConsignDepositMusd} step={1000} suffix="MUSD" />
              </Field>
            </div>
            <Button variant="primary" onClick={handleConsignMusd}>Consign</Button>
          </div>
        </div>
        <div className="mt-6 flex flex-wrap gap-6 border-t border-line pt-4 font-mono text-[12px] text-faint">
          <span>Sample vault: {usd(vaultPooledMusd)} MUSD pooled · {vaultShareNav.toFixed(4)} per share · ${usd(buyerPremiumRevenue)} premium</span>
          <span>{telemetry.troveCount} troves</span>
          <a href={EXPLORER} target="_blank" rel="noreferrer" className="flex items-center gap-1 hover:text-fg">
            Stability Pool {BACKSTOP_MEZO_ADDRESSES.StabilityPool.slice(0, 8)}… <ArrowUpRight className="h-3 w-3" />
          </a>
        </div>
      </Panel>
    </div>
  );
}

function toRoman(n: number) {
  const map: [number, string][] = [[50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']];
  let out = '';
  for (const [v, s] of map) while (n >= v) { out += s; n -= v; }
  return out;
}

function prettyRef(ref: string) {
  const part = ref.split('—')[1]?.trim() ?? ref;
  return part.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
}

/* Engraved coin for each lot, drawn in the shared copper tone */
function LotCoin({ lot, size, big = false }: { lot: number; size: number; big?: boolean }) {
  const s = big ? 240 : 150;
  const gid = `bs-coin-${lot}-${big ? 'l' : 's'}`;
  return (
    <svg viewBox="0 0 200 200" width={s} height={s} aria-hidden>
      <defs>
        <radialGradient id={gid} cx="35%" cy="30%" r="80%">
          <stop offset="0%" stopColor="#F6C98A" />
          <stop offset="55%" stopColor="#E59A38" />
          <stop offset="100%" stopColor="#7A4B14" />
        </radialGradient>
      </defs>
      <circle cx="100" cy="100" r="86" fill={`url(#${gid})`} />
      <circle cx="100" cy="100" r="74" fill="none" stroke="#fff" strokeOpacity="0.35" />
      {Array.from({ length: 60 }).map((_, i) => {
        const a = (i / 60) * Math.PI * 2;
        return <line key={i} x1={100 + Math.cos(a) * 80} y1={100 + Math.sin(a) * 80} x2={100 + Math.cos(a) * 85} y2={100 + Math.sin(a) * 85} stroke="#3B2408" strokeOpacity="0.35" />;
      })}
      <text x="100" y="114" textAnchor="middle" fontFamily="Inter Tight, sans-serif" fontSize="60" fill="#fff" fillOpacity="0.9">₿</text>
      <text x="100" y="146" textAnchor="middle" fontFamily="Geist Mono, monospace" fontSize="9" letterSpacing="2" fill="#fff" fillOpacity="0.85">
        LOT {toRoman(lot)} · {size} BTC
      </text>
    </svg>
  );
}

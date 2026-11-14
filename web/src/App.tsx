import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Volume2, VolumeX, Wallet } from "lucide-react";
import {
  ConnectedWallet,
  connectMezoWallet,
  fetchMezoLiveTelemetry,
  MezoLiveTelemetry,
  OFFLINE_SNAPSHOT,
  shortAddress,
} from "./lib/meridianChain";
import { meridianAudio } from "./lib/meridianAudio";
import { greenhouseAudio } from "./lib/greenhouseAudio";
import { gavelAudio } from "./lib/gavelAudio";
import { swissAudio } from "./lib/fixingBellAudio";
import { printerAudio } from "./lib/thermalPrinterAudio";
import { signalAudio } from "./lib/signalBoxAudio";
import { metrologyAudio } from "./lib/metrologyAudio";
import { radarAudio } from "./lib/radarAudio";
import { pressAudio } from "./lib/pressAudio";
import { ActiveRoute, OverviewView } from "./modules/OverviewView";
import { RoostModule } from "./modules/RoostModule";
import { RelayModule } from "./modules/RelayModule";
import { ChronosModule } from "./modules/ChronosModule";
import { AutopayModule } from "./modules/AutopayModule";
import { PegKeeperModule } from "./modules/PegKeeperModule";
import { BackstopModule } from "./modules/BackstopModule";
import { KeeperGridModule } from "./modules/KeeperGridModule";
import { DrawdownModule } from "./modules/DrawdownModule";

// Each module has its own procedural sound set; the header's sound button controls all of them.
const MODULE_AUDIO = [greenhouseAudio, gavelAudio, swissAudio, printerAudio, signalAudio, metrologyAudio, radarAudio, pressAudio];

const NAV_GROUPS: { pillar: string; items: { id: ActiveRoute; label: string }[] }[] = [
  { pillar: "Credit", items: [{ id: "autopay", label: "Autopay" }, { id: "drawdown", label: "Drawdown" }] },
  { pillar: "Yield", items: [{ id: "roost", label: "Roost" }, { id: "chronos", label: "Chronos" }] },
  { pillar: "Peg", items: [{ id: "pegkeeper", label: "PegKeeper" }, { id: "backstop", label: "Backstop" }] },
  { pillar: "Governance", items: [{ id: "relay", label: "Relay" }, { id: "keepergrid", label: "KeeperGrid" }] },
];

export function App() {
  const [route, setRoute] = useState<ActiveRoute>("overview");
  const [telemetry, setTelemetry] = useState<MezoLiveTelemetry>(OFFLINE_SNAPSHOT);
  const [telemetryLoaded, setTelemetryLoaded] = useState(false);
  const announcedRef = useRef(false);
  const [wallet, setWallet] = useState<ConnectedWallet | null>(null);
  const [muted, setMuted] = useState(false);
  const [eventLog, setEventLog] = useState<string[]>(["Connecting to Mezo Testnet (chain 31611)…"]);

  const appendEvent = useCallback((msg: string) => {
    const stamp = new Date().toLocaleTimeString("en-US", { hour12: false });
    setEventLog((prev) => [`${stamp}  ${msg}`, ...prev.slice(0, 5)]);
  }, []);

  useEffect(() => {
    let active = true;
    const load = async () => {
      const data = await fetchMezoLiveTelemetry();
      if (!active) return;
      setTelemetry(data);
      setTelemetryLoaded(true);
      if (!announcedRef.current) {
        announcedRef.current = true;
        appendEvent(
          data.isLiveRpc
            ? `Live data from Mezo Testnet at block ${data.blockNumber.toString()}.`
            : "Mezo RPC unreachable. Showing an offline snapshot; figures are not live."
        );
      }
    };
    void load();
    const id = window.setInterval(() => void load(), 20_000);
    return () => {
      active = false;
      window.clearInterval(id);
    };
  }, [appendEvent]);

  const navigate = (next: ActiveRoute) => {
    meridianAudio.switchTab();
    setRoute(next);
    window.scrollTo({ top: 0 });
  };

  const handleConnect = async () => {
    if (wallet) {
      setWallet(null);
      appendEvent("Wallet disconnected.");
      return;
    }
    meridianAudio.settle();
    const res = await connectMezoWallet();
    setWallet(res);
    appendEvent(
      res.mode === "injected"
        ? `Wallet connected: ${shortAddress(res.address)} on Mezo Testnet.`
        : `No browser wallet found. Using a read-only demo address ${shortAddress(res.address)}.`
    );
  };

  const toggleAudio = () => {
    const next = !muted;
    setMuted(next);
    meridianAudio.setMuted(next);
    MODULE_AUDIO.forEach((a) => {
      a.enabled = !next;
    });
    if (!next) meridianAudio.click(640);
  };

  const status = !telemetryLoaded
    ? { tone: "bg-faint", label: "Connecting" }
    : telemetry.isLiveRpc
      ? { tone: "bg-pos", label: "Live" }
      : { tone: "bg-neg", label: "Offline snapshot" };

  const ticker = [
    `BTC $${telemetry.btcPriceUsd.toLocaleString("en-US", { maximumFractionDigits: 0 })}`,
    `Stability Pool ${(telemetry.spDepositsMusd / 1_000_000).toFixed(2)}M MUSD`,
    `sMUSD supply ${(telemetry.sMusdSupply / 1_000).toFixed(1)}K`,
    `${telemetry.troveCount} troves`,
    `MCR ${telemetry.mcrPercent.toFixed(0)}% · CCR ${telemetry.ccrPercent.toFixed(0)}%`,
    telemetry.isRecoveryMode ? "Recovery Mode active" : "Normal Mode",
    `${telemetry.boostGaugeCount} gauges`,
    `Block ${telemetry.blockNumber.toString()}`,
  ];

  return (
    <div className="min-h-screen bg-base text-fg">
      {/* Market ticker */}
      <div className="group overflow-hidden border-b border-line bg-[#08090B] py-2">
        <div className="animate-ticker font-mono text-[11px] text-muted">
          {[...ticker, ...ticker].map((t, i) => (
            <span key={`${t}-${i}`} className="mx-6 inline-flex items-center gap-2 whitespace-nowrap">
              <span className="h-1 w-1 rounded-full bg-copper" />
              {t}
            </span>
          ))}
        </div>
      </div>

      {/* Header */}
      <header className="sticky top-0 z-40 border-b border-line bg-base/85 backdrop-blur-xl">
        <div className="mx-auto flex max-w-[1240px] items-center justify-between gap-6 px-5 py-3.5 md:px-8">
          <button type="button" onClick={() => navigate("overview")} className="flex items-center gap-3">
            <MeridianMark />
            <span className="text-[17px] font-medium tracking-tight">Meridian</span>
            <span className="hidden rounded-full border border-line px-2 py-0.5 font-mono text-[10px] text-muted sm:inline">Mezo Testnet</span>
          </button>

          <div className="flex items-center gap-2">
            <span className="hidden h-9 items-center gap-2 rounded-full border border-line bg-raised px-3.5 font-mono text-[12px] text-muted md:inline-flex">
              <span className={`h-1.5 w-1.5 rounded-full ${status.tone}`} />
              {status.label}
              <span className="text-faint">·</span>
              <span className="text-fg">#{telemetry.blockNumber.toString()}</span>
            </span>
            <button
              type="button"
              onClick={toggleAudio}
              aria-label={muted ? "Turn sound on" : "Turn sound off"}
              className="flex h-9 w-9 items-center justify-center rounded-full border border-line bg-raised text-muted hover:text-fg"
            >
              {muted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
            </button>
            <button
              type="button"
              onClick={() => void handleConnect()}
              className="inline-flex h-9 items-center gap-2 rounded-full bg-copper px-4 text-[14px] font-medium text-base hover:bg-[#F0A84A]"
            >
              <Wallet className="h-4 w-4" />
              {wallet ? shortAddress(wallet.address) : "Connect wallet"}
            </button>
          </div>
        </div>

        {/* Module navigation, grouped by pillar */}
        <nav className="mx-auto flex max-w-[1240px] items-center gap-1 overflow-x-auto px-5 pb-2.5 md:px-8">
          <NavItem active={route === "overview"} onClick={() => navigate("overview")}>
            Overview
          </NavItem>
          {NAV_GROUPS.map((g) => (
            <div key={g.pillar} className="flex shrink-0 items-center gap-1">
              <span className="mx-2 h-4 w-px bg-line" />
              <span className="mr-1 hidden font-mono text-[10px] uppercase tracking-[0.08em] text-faint lg:inline">{g.pillar}</span>
              {g.items.map((it) => (
                <NavItem key={it.id} active={route === it.id} onClick={() => navigate(it.id)}>
                  {it.label}
                </NavItem>
              ))}
            </div>
          ))}
        </nav>
      </header>

      <main className="mx-auto max-w-[1240px] px-5 py-8 md:px-8">
        <div hidden={route !== "overview"}>
          <OverviewView telemetry={telemetry} onNavigate={navigate} />
        </div>
        {/* Modules stay mounted so their state survives switching between them. */}
        <div hidden={route !== "autopay"}><AutopayModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "drawdown"}><DrawdownModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "roost"}><RoostModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "chronos"}><ChronosModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "pegkeeper"}><PegKeeperModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "backstop"}><BackstopModule onLogEvent={appendEvent} wallet={wallet} /></div>
        <div hidden={route !== "relay"}><RelayModule onLogEvent={appendEvent} walletAddress={wallet?.address ?? null} wallet={wallet} /></div>
        <div hidden={route !== "keepergrid"}><KeeperGridModule onLogEvent={appendEvent} walletAddress={wallet?.address ?? null} wallet={wallet} /></div>
      </main>

      {/* Activity log */}
      <footer className="mx-auto max-w-[1240px] px-5 pb-10 md:px-8">
        <div className="panel px-6 py-5">
          <div className="flex items-center justify-between">
            <span className="eyebrow">Activity</span>
            <span className="font-mono text-[11px] text-faint">Mezo Testnet · chain 31611</span>
          </div>
          <div className="mt-3 space-y-1.5 font-mono text-[12px]">
            {eventLog.map((line, i) => (
              <div key={`${line}-${i}`} className={i === 0 ? "text-fg" : "text-faint"}>
                {line}
              </div>
            ))}
          </div>
        </div>
      </footer>
    </div>
  );
}

function NavItem({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`h-8 shrink-0 rounded-full px-3.5 text-[13px] transition-colors ${
        active ? "bg-white/10 text-fg" : "text-muted hover:text-fg"
      }`}
    >
      {children}
    </button>
  );
}

function MeridianMark() {
  return (
    <svg width="26" height="26" viewBox="0 0 26 26" aria-hidden>
      <circle cx="13" cy="13" r="12" fill="none" stroke="#E59A38" strokeWidth="1.5" />
      <path d="M13 1v24" stroke="#E59A38" strokeWidth="1.5" />
      <ellipse cx="13" cy="13" rx="5.5" ry="12" fill="none" stroke="#ECEEF1" strokeOpacity="0.6" strokeWidth="1" />
    </svg>
  );
}

export default App;

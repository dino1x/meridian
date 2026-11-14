import { useMemo, useState } from "react";
import { ArrowUpRight, Check, Copy } from "lucide-react";
import { explorerAddressUrl, MezoLiveTelemetry, REGISTRY_CATALOG } from "../lib/meridianChain";
import { meridianAudio } from "../lib/meridianAudio";
import { Button, Eyebrow, Panel, Segmented, StatGrid, fmt, short } from "../ui/kit";

export type ActiveRoute =
  | "overview"
  | "autopay"
  | "drawdown"
  | "roost"
  | "chronos"
  | "pegkeeper"
  | "backstop"
  | "relay"
  | "keepergrid";

interface OverviewViewProps {
  telemetry: MezoLiveTelemetry;
  onNavigate: (route: ActiveRoute) => void;
}

type Pillar = "Credit & Payroll" | "Yield & Fixed Income" | "Peg & Auctions" | "Governance & Keepers";

const MODULES: { route: ActiveRoute; name: string; pillar: Pillar; line: string; fact: string }[] = [
  { route: "autopay", name: "Autopay", pillar: "Credit & Payroll", line: "A BTC trove that repays its own MUSD debt from sMUSD yield.", fact: "1% fee + 0.5% keeper tip per harvest" },
  { route: "drawdown", name: "Drawdown", pillar: "Credit & Payroll", line: "Payroll streamed from a BTC treasury, borrowed only when claimed.", fact: "0.50% fee per claim" },
  { route: "roost", name: "Roost", pillar: "Yield & Fixed Income", line: "Principal-protected bonds that accrue bMUSD over time.", fact: "α = 15 days · 1% chicken-in fee" },
  { route: "chronos", name: "Chronos", pillar: "Yield & Fixed Income", line: "Fixed MUSD rates for 30, 90 and 180 days, set by auction.", fact: "Uniform-price batch auction" },
  { route: "pegkeeper", name: "PegKeeper", pillar: "Peg & Auctions", line: "Redeems MUSD below $1 and keeps the spread for depositors.", fact: "10% protocol + 2% keeper on net spread" },
  { route: "backstop", name: "Backstop", pillar: "Peg & Auctions", line: "Sells seized BTC by Dutch auction and refills the Stability Pool.", fact: "2 h decay, 100% → 92% of oracle" },
  { route: "relay", name: "Relay", pillar: "Governance & Keepers", line: "Votes your veBTC or veMEZO each epoch without taking custody.", fact: "2% fee on harvested bribes" },
  { route: "keepergrid", name: "KeeperGrid", pillar: "Governance & Keepers", line: "Keepers bonded in sMUSD run Mezo's maintenance jobs.", fact: "500 MUSD min bond · 10% slash" },
];

const PILLARS: Pillar[] = ["Credit & Payroll", "Yield & Fixed Income", "Peg & Auctions", "Governance & Keepers"];

export function OverviewView({ telemetry, onNavigate }: OverviewViewProps) {
  const [filter, setFilter] = useState<"ALL" | Pillar>("ALL");
  const [copied, setCopied] = useState<string | null>(null);

  const contracts = useMemo(
    () => (filter === "ALL" ? REGISTRY_CATALOG : REGISTRY_CATALOG.filter((c) => c.pillar === filter)),
    [filter]
  );

  const copy = (addr: string) => {
    void navigator.clipboard?.writeText(addr);
    meridianAudio.click(880);
    setCopied(addr);
    window.setTimeout(() => setCopied((c) => (c === addr ? null : c)), 1500);
  };

  return (
    <div className="space-y-8">
      {/* Hero */}
      <section className="panel panel-glow overflow-hidden">
        <div className="grid gap-10 p-8 md:grid-cols-12 md:p-12">
          <div className="md:col-span-7">
            <Eyebrow>Eight BTCFi modules on Mezo</Eyebrow>
            <h1 className="mt-5 text-[44px] leading-[1.02] md:text-[60px]">
              Borrow, earn and keep
              <br />
              MUSD at a dollar.
            </h1>
            <p className="mt-5 max-w-[520px] text-[17px] leading-relaxed text-muted">
              Meridian puts self-repaying troves, payroll, bonds, fixed rates, peg defence,
              liquidation auctions, vote relaying and keepers behind one interface.
            </p>
            <div className="mt-8 flex flex-wrap gap-2.5">
              <Button variant="primary" onClick={() => onNavigate("autopay")}>Open Autopay</Button>
              <Button onClick={() => onNavigate("chronos")}>See fixed rates</Button>
            </div>
          </div>

          {/* How the modules connect */}
          <div className="md:col-span-5">
            <div className="label">How value moves</div>
            <ol className="mt-4 space-y-2">
              {[
                ["BTC collateral", "Autopay · Drawdown"],
                ["MUSD and sMUSD yield", "Roost · Chronos"],
                ["Peg and solvency", "PegKeeper · Backstop"],
                ["Votes and upkeep", "Relay · KeeperGrid"],
              ].map(([stage, mods], i) => (
                <li key={stage} className="flex items-center justify-between rounded-xl border border-line bg-raised px-4 py-3">
                  <span className="flex items-center gap-3 text-[14px]">
                    <span className="font-mono text-[11px] text-faint">{String(i + 1).padStart(2, "0")}</span>
                    {stage}
                  </span>
                  <span className="font-mono text-[12px] text-muted">{mods}</span>
                </li>
              ))}
            </ol>
          </div>
        </div>

        <StatGrid
          className="border-t border-line"
          stats={[
            { label: "BTC oracle", value: `$${fmt(telemetry.btcPriceUsd, 0)}`, tone: "ice" },
            { label: "Stability Pool", value: `${(telemetry.spDepositsMusd / 1e6).toFixed(2)}M`, sub: "MUSD deposited" },
            { label: "Open troves", value: fmt(telemetry.troveCount), sub: `MCR ${telemetry.mcrPercent.toFixed(0)}% · CCR ${telemetry.ccrPercent.toFixed(0)}%` },
            {
              label: "System mode",
              value: telemetry.isRecoveryMode ? "Recovery" : "Normal",
              tone: telemetry.isRecoveryMode ? "warn" : "pos",
              sub: telemetry.isLiveRpc ? `Live at block ${telemetry.blockNumber.toString()}` : "Offline snapshot",
            },
          ]}
        />
      </section>

      {/* Modules */}
      <section>
        <div className="flex items-end justify-between">
          <div>
            <Eyebrow>Modules</Eyebrow>
            <h2 className="mt-3 text-[30px]">Four pillars, eight modules</h2>
          </div>
        </div>
        <div className="mt-6 grid gap-4 md:grid-cols-2">
          {PILLARS.map((p, pi) => (
            <div key={p} className="panel p-6">
              <div className="label">
                {String(pi + 1).padStart(2, "0")} · {p}
              </div>
              <div className="mt-4 space-y-3">
                {MODULES.filter((m) => m.pillar === p).map((m) => (
                  <button
                    key={m.route}
                    type="button"
                    onClick={() => onNavigate(m.route)}
                    className="group flex w-full items-start justify-between gap-4 rounded-xl border border-line bg-raised p-4 text-left transition-colors hover:border-white/20"
                  >
                    <div>
                      <div className="text-[17px]">{m.name}</div>
                      <div className="mt-1 text-[14px] text-muted">{m.line}</div>
                      <div className="mt-3 font-mono text-[11px] text-faint">{m.fact}</div>
                    </div>
                    <ArrowUpRight className="mt-1 h-4 w-4 shrink-0 text-faint group-hover:text-copper" />
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Contract registry */}
      <Panel
        eyebrow="Mezo Testnet · chain 31611"
        title="Deployed contracts"
        flush
        right={
          <Segmented
            value={filter}
            onChange={(v) => setFilter(v)}
            options={[{ value: "ALL" as const, label: "All" }, ...PILLARS.map((p) => ({ value: p, label: p.split(" ")[0] }))]}
          />
        }
      >
        <div className="divide-y divide-line">
          {contracts.map((c) => (
            <div key={c.address} className="grid grid-cols-[110px_1fr_auto] items-center gap-4 px-6 py-3.5 md:grid-cols-[120px_200px_1fr_auto]">
              <span className="text-[14px]">{c.module}</span>
              <span className="font-mono text-[13px] text-muted">{c.contractName}</span>
              <span className="hidden text-[13px] text-muted md:block">{c.role}</span>
              <span className="flex items-center gap-2">
                <span className="font-mono text-[12px] text-fg">{short(c.address)}</span>
                <button
                  type="button"
                  onClick={() => copy(c.address)}
                  aria-label={`Copy ${c.contractName} address`}
                  className="flex h-7 w-7 items-center justify-center rounded-full text-faint hover:bg-white/5 hover:text-fg"
                >
                  {copied === c.address ? <Check className="h-3.5 w-3.5 text-pos" /> : <Copy className="h-3.5 w-3.5" />}
                </button>
                <a
                  href={explorerAddressUrl(c.address)}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={`Open ${c.contractName} in the explorer`}
                  className="flex h-7 w-7 items-center justify-center rounded-full text-faint hover:bg-white/5 hover:text-fg"
                >
                  <ArrowUpRight className="h-3.5 w-3.5" />
                </a>
              </span>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}

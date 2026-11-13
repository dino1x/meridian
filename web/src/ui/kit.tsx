// Meridian UI kit: the shared building blocks every module is composed from.
import type { ReactNode, Ref } from 'react';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/* ---------- Typography ---------- */

export function Eyebrow({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cx('eyebrow', className)}>{children}</div>;
}

/* ---------- Page header: eyebrow, title, one-line description, actions, KPI strip ---------- */

export function PageHeader({
  code,
  pillar,
  title,
  description,
  actions,
  stats,
}: {
  code: string;
  pillar: string;
  title: ReactNode;
  description: ReactNode;
  actions?: ReactNode;
  stats?: { label: string; value: ReactNode; sub?: ReactNode; tone?: Tone }[];
}) {
  return (
    <header className="panel panel-glow overflow-hidden">
      <div className="grid gap-8 p-7 md:grid-cols-[1fr_auto] md:items-end md:p-9">
        <div>
          <Eyebrow>
            {code} · {pillar}
          </Eyebrow>
          <h1 className="mt-4 text-[38px] leading-[1.05] md:text-[48px]">{title}</h1>
          <p className="mt-4 max-w-[620px] text-[16px] leading-relaxed text-muted">{description}</p>
        </div>
        {actions && <div className="flex flex-wrap gap-2.5">{actions}</div>}
      </div>
      {stats && <StatGrid stats={stats} className="border-t border-line" />}
    </header>
  );
}

/* ---------- Stats: hairline grid of mono label + large figure ---------- */

export type Tone = 'default' | 'ice' | 'copper' | 'pos' | 'neg' | 'warn' | 'muted';
const toneText: Record<Tone, string> = {
  default: 'text-fg',
  ice: 'text-ice',
  copper: 'text-copper',
  pos: 'text-pos',
  neg: 'text-neg',
  warn: 'text-warn',
  muted: 'text-muted',
};

export function Stat({
  label,
  value,
  sub,
  tone = 'default',
  valueRef,
  size = 'md',
}: {
  label: string;
  value?: ReactNode;
  sub?: ReactNode;
  tone?: Tone;
  valueRef?: Ref<HTMLDivElement>;
  size?: 'md' | 'lg';
}) {
  return (
    <div>
      <div className="label">{label}</div>
      <div
        ref={valueRef}
        className={cx(
          'mt-2 tracking-tight tabular-nums',
          size === 'lg' ? 'text-[36px] leading-none' : 'text-[24px] leading-tight',
          toneText[tone]
        )}
      >
        {value ?? '—'}
      </div>
      {sub && <div className="mt-1.5 text-[12px] text-muted">{sub}</div>}
    </div>
  );
}

export function StatGrid({
  stats,
  className,
}: {
  stats: { label: string; value: ReactNode; sub?: ReactNode; tone?: Tone }[];
  className?: string;
}) {
  return (
    <div className={cx('grid grid-cols-2 gap-px bg-line', stats.length >= 4 ? 'md:grid-cols-4' : 'md:grid-cols-3', className)}>
      {stats.map((s) => (
        <div key={s.label} className="bg-surface p-6 md:px-9">
          <Stat {...s} />
        </div>
      ))}
    </div>
  );
}

/* ---------- Panels ---------- */

export function Panel({
  title,
  eyebrow,
  right,
  children,
  className,
  glow,
  flush,
}: {
  title?: ReactNode;
  eyebrow?: ReactNode;
  right?: ReactNode;
  children: ReactNode;
  className?: string;
  glow?: boolean;
  flush?: boolean;
}) {
  return (
    <section className={cx('panel', glow && 'panel-glow', 'flex flex-col', className)}>
      {(title || eyebrow || right) && (
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-line px-6 py-4">
          <div>
            {eyebrow && <div className="label mb-1">{eyebrow}</div>}
            {title && <h2 className="text-[18px] leading-snug">{title}</h2>}
          </div>
          {right && <div className="flex flex-wrap items-center gap-2">{right}</div>}
        </div>
      )}
      <div className={cx('flex-1', !flush && 'p-6')}>{children}</div>
    </section>
  );
}

export function SectionTitle({ eyebrow, title, description }: { eyebrow: string; title: ReactNode; description?: ReactNode }) {
  return (
    <div className="grid gap-4 md:grid-cols-12 md:items-end">
      <div className="md:col-span-7">
        <Eyebrow>{eyebrow}</Eyebrow>
        <h2 className="mt-3 text-[30px] leading-[1.1] md:text-[34px]">{title}</h2>
      </div>
      {description && <p className="text-[15px] leading-relaxed text-muted md:col-span-5">{description}</p>}
    </div>
  );
}

/* ---------- Buttons ---------- */

type BtnVariant = 'primary' | 'secondary' | 'ghost' | 'danger';
const btnVariant: Record<BtnVariant, string> = {
  primary: 'bg-copper text-base hover:bg-[#F0A84A] font-medium',
  secondary: 'border border-line bg-raised text-fg hover:border-white/20',
  ghost: 'text-muted hover:text-fg hover:bg-white/[0.04]',
  danger: 'bg-neg/90 text-white hover:bg-neg font-medium',
};

export function Button({
  children,
  onClick,
  variant = 'secondary',
  size = 'md',
  disabled,
  className,
  type = 'button',
  ariaLabel,
}: {
  children: ReactNode;
  onClick?: () => void;
  variant?: BtnVariant;
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  className?: string;
  type?: 'button' | 'submit';
  ariaLabel?: string;
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      aria-label={ariaLabel}
      className={cx(
        'inline-flex items-center justify-center gap-2 rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40',
        size === 'sm' && 'h-8 px-3.5 text-[13px]',
        size === 'md' && 'h-10 px-5 text-[14px]',
        size === 'lg' && 'h-12 px-6 text-[15px]',
        btnVariant[variant],
        className
      )}
    >
      {children}
    </button>
  );
}

export function LinkButton({ href, children, external }: { href: string; children: ReactNode; external?: boolean }) {
  return (
    <a
      href={href}
      target={external ? '_blank' : undefined}
      rel={external ? 'noreferrer' : undefined}
      className="inline-flex h-10 items-center gap-2 rounded-full border border-line bg-raised px-5 text-[14px] text-fg transition-colors hover:border-white/20"
    >
      {children}
    </a>
  );
}

/* ---------- Segmented control (tabs) ---------- */

export function Segmented<T extends string | number>({
  options,
  value,
  onChange,
  className,
}: {
  options: { value: T; label: ReactNode }[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
}) {
  return (
    <div className={cx('inline-flex rounded-full border border-line bg-raised p-1', className)}>
      {options.map((o) => (
        <button
          key={String(o.value)}
          type="button"
          onClick={() => onChange(o.value)}
          className={cx(
            'h-8 rounded-full px-3.5 text-[13px] transition-colors',
            o.value === value ? 'bg-white/10 text-fg' : 'text-muted hover:text-fg'
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* ---------- Status pill ---------- */

const dotTone: Record<Tone, string> = {
  default: 'bg-fg',
  ice: 'bg-ice',
  copper: 'bg-copper',
  pos: 'bg-pos',
  neg: 'bg-neg',
  warn: 'bg-warn',
  muted: 'bg-faint',
};

export function StatusPill({ tone = 'muted', children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span className="inline-flex h-7 items-center gap-2 rounded-full border border-line bg-raised px-3 text-[12px] text-fg">
      <span className={cx('h-1.5 w-1.5 rounded-full', dotTone[tone])} />
      {children}
    </span>
  );
}

/* ---------- Form controls ---------- */

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: ReactNode;
  children: ReactNode;
}) {
  return (
    <label className="block">
      <span className="label">{label}</span>
      <div className="mt-2">{children}</div>
      {hint && <div className="mt-1.5 text-[12px] text-faint">{hint}</div>}
    </label>
  );
}

export function NumberInput({
  value,
  onChange,
  step,
  min,
  suffix,
}: {
  value: number;
  onChange: (v: number) => void;
  step?: number | string;
  min?: number;
  suffix?: string;
}) {
  return (
    <div className="relative">
      <input
        type="number"
        value={value}
        step={step}
        min={min}
        onChange={(e) => onChange(Number(e.target.value))}
        className={cx('field', suffix && 'pr-16')}
      />
      {suffix && <span className="label pointer-events-none absolute right-3 top-1/2 -translate-y-1/2">{suffix}</span>}
    </div>
  );
}

export function Slider({
  label,
  valueLabel,
  min,
  max,
  step,
  value,
  onChange,
  ends,
}: {
  label: string;
  valueLabel: ReactNode;
  min: number;
  max: number;
  step?: number;
  value: number;
  onChange: (v: number) => void;
  ends?: [ReactNode, ReactNode];
}) {
  return (
    <div>
      <div className="flex items-baseline justify-between">
        <span className="label">{label}</span>
        <span className="font-mono text-[13px] text-fg">{valueLabel}</span>
      </div>
      <input type="range" className="slider mt-4 w-full" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      {ends && (
        <div className="mt-2 flex justify-between font-mono text-[11px] text-faint">
          <span>{ends[0]}</span>
          <span>{ends[1]}</span>
        </div>
      )}
    </div>
  );
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button type="button" onClick={() => onChange(!on)} className="flex w-full items-center justify-between text-[14px] text-muted" aria-label={label}>
      <span>{label}</span>
      <span className={cx('relative h-5 w-9 rounded-full transition-colors', on ? 'bg-copper' : 'bg-white/15')}>
        <span className={cx('absolute top-0.5 h-4 w-4 rounded-full bg-white transition-all', on ? 'left-[18px]' : 'left-0.5')} />
      </span>
    </button>
  );
}

/* ---------- Data rows ---------- */

export function KeyValue({ k, v, strong, tone }: { k: ReactNode; v: ReactNode; strong?: boolean; tone?: Tone }) {
  return (
    <div className={cx('flex items-baseline justify-between gap-4 py-2 text-[14px]', strong && 'mt-1 border-t border-line pt-3')}>
      <span className="text-muted">{k}</span>
      <span className={cx('font-mono tabular-nums', strong ? 'text-fg' : 'text-fg/90', tone && toneText[tone])}>{v}</span>
    </div>
  );
}

/** Label, value and a hairline bar showing a share of the maximum. */
export function MeterRow({ label, value, fraction, note, tone = 'ice' }: { label: ReactNode; value: ReactNode; fraction: number; note?: ReactNode; tone?: Tone }) {
  return (
    <div>
      <div className="flex justify-between text-[14px]">
        <span className="text-muted">{label}</span>
        <span className="font-mono tabular-nums text-fg">{value}</span>
      </div>
      <div className="mt-2.5 h-[2px] overflow-hidden rounded bg-white/[0.07]">
        <div className={cx('h-full', dotTone[tone])} style={{ width: `${Math.max(0, Math.min(100, fraction * 100))}%` }} />
      </div>
      {note && <div className="mt-1.5 text-[12px] text-faint">{note}</div>}
    </div>
  );
}

export function Table({ head, cols, children }: { head: ReactNode[]; cols: string; children: ReactNode }) {
  return (
    <div>
      <div className="grid gap-3 border-b border-line px-6 py-3" style={{ gridTemplateColumns: cols }}>
        {head.map((h, i) => (
          <span key={i} className={cx('label', i > 0 && 'text-right')}>
            {h}
          </span>
        ))}
      </div>
      <div className="divide-y divide-line">{children}</div>
    </div>
  );
}

export function Row({
  cols,
  children,
  onClick,
  active,
}: {
  cols: string;
  children: ReactNode;
  onClick?: () => void;
  active?: boolean;
}) {
  const cls = cx(
    'grid w-full items-center gap-3 px-6 py-3.5 text-left text-[14px] transition-colors',
    onClick && 'hover:bg-white/[0.025]',
    active && 'bg-white/[0.04]'
  );
  return onClick ? (
    <button type="button" onClick={onClick} className={cls} style={{ gridTemplateColumns: cols }}>
      {children}
    </button>
  ) : (
    <div className={cls} style={{ gridTemplateColumns: cols }}>
      {children}
    </div>
  );
}

/* ---------- Steps (expandable list) ---------- */

export function Steps({ steps, active, onSelect }: { steps: { title: string; body: ReactNode }[]; active: number; onSelect: (i: number) => void }) {
  return (
    <div className="border-t border-line">
      {steps.map((s, i) => (
        <button key={s.title} type="button" onClick={() => onSelect(i)} className="group w-full border-b border-line py-4 text-left">
          <div className="flex items-center gap-3 text-[15px]">
            <span className="font-mono text-[11px] text-faint">{String(i + 1).padStart(2, '0')}</span>
            <span className={active === i ? 'text-fg' : 'text-muted group-hover:text-fg'}>{s.title}</span>
          </div>
          {active === i && <div className="mt-2.5 pl-8 text-[14px] leading-relaxed text-muted">{s.body}</div>}
        </button>
      ))}
    </div>
  );
}

/* ---------- Callout ---------- */

export function Callout({ tone = 'muted', title, children, action }: { tone?: Tone; title: ReactNode; children?: ReactNode; action?: ReactNode }) {
  const border: Record<Tone, string> = {
    default: 'border-line',
    ice: 'border-ice/30',
    copper: 'border-copper/40',
    pos: 'border-pos/30',
    neg: 'border-neg/40',
    warn: 'border-warn/40',
    muted: 'border-line',
  };
  return (
    <div className={cx('flex flex-wrap items-center justify-between gap-4 rounded-xl border bg-raised px-5 py-4', border[tone])}>
      <div className="min-w-0">
        <div className="flex items-center gap-2 text-[14px]">
          <span className={cx('h-1.5 w-1.5 rounded-full', dotTone[tone])} />
          {title}
        </div>
        {children && <div className="mt-1 text-[13px] text-muted">{children}</div>}
      </div>
      {action}
    </div>
  );
}

/* ---------- Formatting ---------- */

export const fmt = (n: number, d = 0) => n.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
export const pct = (n: number, d = 2) => `${n.toFixed(d)}%`;
export const short = (addr: string) => (addr && addr.length > 10 ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : addr || '—');
export const EXPLORER = 'https://explorer.test.mezo.org';

/* ---------- On-chain transaction status ---------- */

export type TxView =
  | { kind: 'idle' }
  | { kind: 'pending'; step: string }
  | { kind: 'done'; label: string; hash: string }
  | { kind: 'error'; message: string };

export function TxStatus({ state }: { state: TxView }) {
  if (state.kind === 'idle') return null;
  if (state.kind === 'pending')
    return (
      <div className="flex items-center gap-2.5 rounded-xl border border-line bg-raised px-4 py-3 text-[13px] text-muted">
        <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-copper border-t-transparent" />
        {state.step}
      </div>
    );
  if (state.kind === 'done')
    return (
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-pos/30 bg-raised px-4 py-3 text-[13px]">
        <span className="flex items-center gap-2">
          <span className="h-1.5 w-1.5 rounded-full bg-pos" />
          {state.label} confirmed
        </span>
        <a href={`${EXPLORER}/tx/${state.hash}`} target="_blank" rel="noreferrer" className="font-mono text-[12px] text-ice hover:underline">
          {state.hash.slice(0, 10)}…{state.hash.slice(-6)}
        </a>
      </div>
    );
  return (
    <div className="flex items-start gap-2 rounded-xl border border-neg/40 bg-raised px-4 py-3 text-[13px] text-fg">
      <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-neg" />
      {state.message}
    </div>
  );
}

/** Header strip for a module's live panel: says whether actions here send real transactions. */
export function LiveNote({ live, address, musd }: { live: boolean; address?: string | null; musd?: number | null }) {
  return live ? (
    <div className="flex flex-wrap items-center justify-between gap-2 font-mono text-[12px] text-muted">
      <span className="flex items-center gap-2">
        <span className="h-1.5 w-1.5 rounded-full bg-pos" /> Sending real transactions from {short(address ?? '')}
      </span>
      {musd != null && <span>Wallet balance {fmt(musd, 2)} MUSD</span>}
    </div>
  ) : (
    <div className="flex items-center gap-2 font-mono text-[12px] text-muted">
      <span className="h-1.5 w-1.5 rounded-full bg-faint" /> Connect a browser wallet (header) to send these on Mezo Testnet. Get test MUSD at testnet.mezo.org.
    </div>
  );
}

/** Separates live on-chain panels from the sample-data simulation below them. */
export function SimDivider() {
  return (
    <div className="flex items-center gap-4 pt-2">
      <span className="h-px flex-1 bg-line" />
      <span className="label">Simulation with sample positions · nothing below sends transactions</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

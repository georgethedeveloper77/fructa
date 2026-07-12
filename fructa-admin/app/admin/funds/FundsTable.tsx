"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import {
  setRate, toggleFlag, setStatus,
  bulkSetVerified, bulkSetStatus, bulkSetRetail, bulkDeleteFunds,
} from "./actions";
import { IconChevronUp, IconChevronDown } from "../_icons";
import { ProvenanceCell, type Provenance } from "./provenance";

export type FundRow = {
  id: string; name: string; manager: string;
  fund_type: string | null; category: string | null; currency: string;
  current_rate: number | null; status: string;
  verified: boolean; featured: boolean; retail: boolean;
  company_id: string | null; logo_domain: string | null;
  basis: string | null; price_per_unit: number | null;
  price_as_of: string | null; distribution_pct: number | null;
};
export type Co = { id: string; name: string; logo_url: string | null; brand_color: string | null };

const FT: [string, string][] = [
  ["mmf", "MMF"], ["fixed_income", "Fixed Income"], ["equity", "Equity"],
  ["balanced", "Balanced"], ["special", "Special"],
];
const LEGACY: [string, string][] = [
  ["tbill", "T-Bills"], ["bond", "Bonds"], ["sacco", "SACCO"], ["stock", "NSE"],
];
const FT_LABEL = Object.fromEntries(FT);
const LEGACY_LABEL = Object.fromEntries(LEGACY);
const FT_KEYS = new Set(FT.map(([k]) => k));
const LEGACY_KEYS = new Set(LEGACY.map(([k]) => k));

function catLabel(f: FundRow): string {
  if (f.fund_type && FT_LABEL[f.fund_type]) return `${FT_LABEL[f.fund_type]} · ${f.currency}`;
  return LEGACY_LABEL[f.category ?? ""] ?? f.category ?? "—";
}

const TINTS = ["#E7B24C", "#5B8DEF", "#A78BFA", "#3DD6C4", "#3DDC97"];
function hashTint(seed: string) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return TINTS[h % TINTS.length];
}

function CheckIcon({ size = 13 }: { size?: number }) {
  return (<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>);
}
function StarIcon({ size = 13 }: { size?: number }) {
  return (<svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M12 2.5l2.9 6.4 7 .6-5.3 4.6 1.6 6.9L12 17.9 5.8 21l1.6-6.9L2.1 9.5l7-.6z" /></svg>);
}

type SortKey = "name" | "type" | "rate" | "status";

export function FundsTable({ rows, companies, prov }: { rows: FundRow[]; companies: Co[]; prov: Record<string, Provenance> }) {
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<string>("all");
  const [cur, setCur] = useState<string>("all");
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [sort, setSort] = useState<{ key: SortKey; dir: 1 | -1 }>({ key: "name", dir: 1 });
  const [pending, start] = useTransition();

  const coById = useMemo(() => new Map(companies.map((c) => [c.id, c])), [companies]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const base = rows.filter((f) => {
      if (tab !== "all") {
        if (FT_KEYS.has(tab) && f.fund_type !== tab) return false;
        if (LEGACY_KEYS.has(tab) && f.category !== tab) return false;
      }
      if (cur !== "all" && f.currency !== cur) return false;
      if (needle && !(`${f.name} ${f.manager}`.toLowerCase().includes(needle))) return false;
      return true;
    });
    base.sort((a, b) => {
      let r = 0;
      switch (sort.key) {
        case "name": r = a.name.localeCompare(b.name); break;
        case "type": r = catLabel(a).localeCompare(catLabel(b)); break;
        case "status": r = a.status.localeCompare(b.status); break;
        case "rate": {
          const av = a.current_rate, bv = b.current_rate;
          if (av == null && bv == null) { r = 0; break; }
          if (av == null) return 1;   // missing rate always last
          if (bv == null) return -1;
          r = av - bv; break;
        }
      }
      return r * sort.dir;
    });
    return base;
  }, [rows, tab, cur, q, sort]);

  const allSel = filtered.length > 0 && filtered.every((f) => sel.has(f.id));
  const toggle = (id: string) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const toggleAll = () => setSel(allSel ? new Set() : new Set(filtered.map((f) => f.id)));
  const ids = () => [...sel];
  const clear = () => setSel(new Set());

  const by = (key: SortKey) => setSort((s) => (s.key === key ? { key, dir: (s.dir * -1) as 1 | -1 } : { key, dir: 1 }));
  const Th = ({ k, children }: { k: SortKey; children: React.ReactNode }) => (
    <th className="px-3 py-3">
      <button onClick={() => by(k)} className="inline-flex items-center gap-1 font-medium uppercase tracking-wider hover:text-mute">
        {children}
        {sort.key === k && <span className="text-gold">{sort.dir === 1 ? <IconChevronUp size={12} /> : <IconChevronDown size={12} />}</span>}
      </button>
    </th>
  );

  const tabBtn = (key: string, label: string) => (
    <button key={key} onClick={() => setTab(key)}
      className={"rounded-md px-2.5 py-1 text-sm " + (tab === key ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>
      {label}
    </button>
  );

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search funds or managers…"
          className="w-64 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
        <div className="flex flex-wrap items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
          {tabBtn("all", "All")}
          {FT.map(([k, l]) => tabBtn(k, l))}
          {LEGACY.map(([k, l]) => tabBtn(k, l))}
        </div>
        <div className="ml-auto flex items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
          {[["all", "All ccy"], ["KES", "KES"], ["USD", "USD"]].map(([k, l]) => (
            <button key={k} onClick={() => setCur(k)}
              className={"rounded-md px-2.5 py-1 text-sm " + (cur === k ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>{l}</button>
          ))}
        </div>
        <span className="tnum text-xs text-faint">{filtered.length} funds</span>
      </div>

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        {sel.size > 0 && (
          <div className="flex flex-wrap items-center gap-2 border-b border-line bg-panel2 px-4 py-2.5 text-sm">
            <span className="text-mute">{sel.size} selected</span>
            <div className="ml-auto flex flex-wrap items-center gap-2">
              <button disabled={pending} onClick={() => start(() => bulkSetVerified(ids(), true))} className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1 text-xs text-gold hover:bg-gold/20">Verify</button>
              <button disabled={pending} onClick={() => start(() => bulkSetStatus(ids(), "live"))} className="rounded-md border border-line px-3 py-1 text-xs text-mute hover:text-ink">Set live</button>
              <button disabled={pending} onClick={() => start(() => bulkSetStatus(ids(), "hidden"))} className="rounded-md border border-line px-3 py-1 text-xs text-mute hover:text-ink">Hide</button>
              <button disabled={pending} onClick={() => start(() => bulkSetRetail(ids(), true))} className="rounded-md border border-line px-3 py-1 text-xs text-mute hover:text-ink">In app</button>
              <button disabled={pending} onClick={() => start(() => bulkSetRetail(ids(), false))} className="rounded-md border border-line px-3 py-1 text-xs text-mute hover:text-ink">Off app</button>
              <button disabled={pending}
                onClick={() => { if (confirm(`Delete ${sel.size} funds and their rate history? This cannot be undone.`)) start(async () => { await bulkDeleteFunds(ids()); clear(); }); }}
                className="rounded-md border border-bad/40 px-3 py-1 text-xs text-bad hover:bg-bad/10">Delete</button>
            </div>
          </div>
        )}

        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-[11px] text-faint">
              <th className="w-10 px-4 py-3"><input type="checkbox" checked={allSel} onChange={toggleAll} className="accent-gold" /></th>
              <Th k="name">Fund</Th>
              <Th k="type">Type</Th>
              <Th k="rate">Rate</Th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Source</th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Flags</th>
              <Th k="status">Status</Th>
              <th className="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            {filtered.map((f) => {
              const co = f.company_id ? coById.get(f.company_id) : undefined;
              const url = co?.logo_url ?? null;
              const color = co?.brand_color ?? hashTint(f.manager || f.name);
              return (
                <tr key={f.id} className="border-b border-line/60 last:border-0 hover:bg-panel2/30">
                  <td className="px-4 py-3"><input type="checkbox" checked={sel.has(f.id)} onChange={() => toggle(f.id)} className="accent-gold" /></td>

                  <td className="px-3 py-3">
                    <div className="flex items-center gap-3">
                      <span className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full border border-line"
                        style={url ? { background: "#fff" } : { background: `color-mix(in srgb, ${color} 18%, transparent)`, color }}>
                        {url ? <img src={url} alt="" className="h-8 w-8 object-contain p-0.5" /> : <span className="text-xs font-semibold">{(f.name || "?").slice(0, 1).toUpperCase()}</span>}
                      </span>
                      <div className="min-w-0">
                        <div className="font-medium text-ink">{f.name}</div>
                        <div className="text-xs text-faint">{f.manager}{f.currency ? ` · ${f.currency}` : ""}{!f.retail ? " · dormant" : ""}</div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3 py-3"><span className="rounded-md border border-line bg-panel2 px-2 py-0.5 text-xs text-mute">{catLabel(f)}</span></td>

                  <td className="px-3 py-3"><RateCell f={f} /></td>

                  <td className="px-3 py-3"><ProvenanceCell p={prov[f.id]} /></td>

                  <td className="px-3 py-3">
                    <div className="flex items-center gap-1.5">
                      <FlagBtn id={f.id} field="verified" on={f.verified} title="Verified"><CheckIcon /></FlagBtn>
                      <FlagBtn id={f.id} field="featured" on={f.featured} title="Featured"><StarIcon /></FlagBtn>
                    </div>
                  </td>

                  <td className="px-3 py-3">
                    <div className="flex items-center gap-2">
                      <span className={"text-xs " + (f.status === "live" ? "text-live" : f.status === "stale" ? "text-warn" : "text-faint")}>{f.status}</span>
                      <form action={setStatus}>
                        <input type="hidden" name="id" value={f.id} />
                        <input type="hidden" name="status" value={f.status === "hidden" ? "live" : "hidden"} />
                        <button className="rounded-md border border-line px-2 py-0.5 text-xs text-mute hover:text-ink">{f.status === "hidden" ? "Show" : "Hide"}</button>
                      </form>
                    </div>
                  </td>

                  <td className="px-3 py-3 text-right"><Link href={`/admin/funds/${f.id}`} className="text-xs text-mute hover:text-gold">Edit</Link></td>
                </tr>
              );
            })}
            {filtered.length === 0 && (
              <tr><td colSpan={8} className="px-4 py-10 text-center text-sm text-mute">No funds match.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// Rate cell routes on `basis`, the same field that gates yield UI in the app:
//   yield (or null) -> the inline editable rate, unchanged
//   nav             -> read-only unit price (edited on the detail page's
//                      Pricing card, so it can't be corrupted from here)
//   none            -> no headline figure; never offer a yield input, so
//                      equity/balanced/special funds can't be given a fake rate
function fmtPrice(v: number): string {
  return v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

function RateCell({ f }: { f: FundRow }) {
  const basis = f.basis ?? "yield";

  if (basis === "nav") {
    return (
      <div className="flex flex-col leading-tight">
        {f.price_per_unit != null
          ? <span className="tnum text-sm text-blue">{fmtPrice(f.price_per_unit)}</span>
          : <span className="text-xs text-faint">no price</span>}
        <span className="text-[10px] text-faint">
          unit price{f.distribution_pct != null ? ` \u00B7 ${f.distribution_pct.toFixed(2)}% dist` : ""}
        </span>
      </div>
    );
  }

  if (basis === "none") {
    return <span className="text-xs text-faint">not rate-based</span>;
  }

  return (
    <form action={setRate} className="flex items-center gap-1.5">
      <input type="hidden" name="id" value={f.id} />
      <input name="rate" type="number" step="0.01" min="0" max="30" defaultValue={f.current_rate ?? ""} placeholder="rate"
        className="w-[70px] rounded-md border border-line bg-panel2 px-2 py-1 text-sm tnum text-ink outline-none placeholder:text-faint focus:border-gold/60" />
      <button className="rounded-md border border-line px-2.5 py-1 text-xs text-mute hover:border-gold/60 hover:text-gold">Set</button>
    </form>
  );
}

function FlagBtn({ id, field, on, title, children }: { id: string; field: string; on: boolean; title: string; children: React.ReactNode }) {
  return (
    <form action={toggleFlag}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="field" value={field} />
      <input type="hidden" name="value" value={(!on).toString()} />
      <button title={title} className={"inline-flex h-6 w-6 items-center justify-center rounded-md border " + (on ? "border-gold/50 bg-gold/10 text-gold" : "border-line text-faint hover:text-mute")}>{children}</button>
    </form>
  );
}

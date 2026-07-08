"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import {
  updateCompany,
  setBrandColor,
  toggleCompanyVerified,
  deleteCompany,
  bulkSetVerified,
  bulkDeleteCompanies,
} from "./actions";
import { LogoCell } from "./LogoCell";
import { IconCheck, IconChevronUp, IconChevronDown } from "../_icons";

export type Company = {
  id: string;
  name: string;
  type: string;
  brand_color: string | null;
  logo_url: string | null;
  website: string | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  verified: boolean;
};

const TYPES: Record<string, string> = {
  fund_manager: "Fund manager",
  insurer: "Insurer",
  sacco: "SACCO",
  government: "Government",
};

type SortKey = "name" | "type" | "funds" | "verified";
type Filter = "all" | "nologo" | "nobrand" | "orphan" | "unverified";

function SearchIcon() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.5" y2="16.5" />
    </svg>
  );
}

function LabeledInput({
  label,
  name,
  defaultValue,
  placeholder,
}: {
  label: string;
  name: string;
  defaultValue: string | null;
  placeholder?: string;
}) {
  return (
    <label className="flex min-w-0 flex-col gap-1">
      <span className="text-[10px] uppercase tracking-wider text-faint">{label}</span>
      <input
        name={name}
        defaultValue={defaultValue ?? ""}
        placeholder={placeholder}
        className="w-full rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-xs text-ink outline-none placeholder:text-faint focus:border-gold/60"
      />
    </label>
  );
}

export function CompaniesTable({
  rows,
  counts,
}: {
  rows: Company[];
  counts: Record<string, number>;
}) {
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [pending, start] = useTransition();
  const [sort, setSort] = useState<{ key: SortKey; dir: 1 | -1 }>({ key: "name", dir: 1 });
  const [q, setQ] = useState("");
  const [flt, setFlt] = useState<Filter>("all");

  // ── analysis (over ALL rows, not the filtered view) ────────────────────
  const stats = useMemo(() => {
    const fundsFor = (id: string) => counts[id] ?? 0;
    const byType: Record<string, number> = {};
    let verified = 0, withLogo = 0, withBrand = 0, totalFunds = 0, orphan = 0, noLogo = 0, noBrand = 0, unverified = 0;
    for (const r of rows) {
      byType[r.type] = (byType[r.type] ?? 0) + 1;
      if (r.verified) verified++; else unverified++;
      if (r.logo_url) withLogo++; else noLogo++;
      if (r.brand_color) withBrand++; else noBrand++;
      const f = fundsFor(r.id);
      totalFunds += f;
      if (f === 0) orphan++;
    }
    return { total: rows.length, verified, withLogo, withBrand, totalFunds, orphan, noLogo, noBrand, unverified, byType };
  }, [rows, counts]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return rows.filter((r) => {
      if (needle && !`${r.name} ${r.id} ${r.website ?? ""}`.toLowerCase().includes(needle)) return false;
      switch (flt) {
        case "nologo": return !r.logo_url;
        case "nobrand": return !r.brand_color;
        case "orphan": return (counts[r.id] ?? 0) === 0;
        case "unverified": return !r.verified;
        default: return true;
      }
    });
  }, [rows, q, flt, counts]);

  const sorted = useMemo(() => {
    return [...filtered].sort((a, b) => {
      let r = 0;
      switch (sort.key) {
        case "name": r = a.name.localeCompare(b.name); break;
        case "type": r = a.type.localeCompare(b.type); break;
        case "funds": r = (counts[a.id] ?? 0) - (counts[b.id] ?? 0); break;
        case "verified": r = Number(a.verified) - Number(b.verified); break;
      }
      return r * sort.dir;
    });
  }, [filtered, sort, counts]);

  const allSel = sorted.length > 0 && sorted.every((r) => sel.has(r.id));
  const toggle = (id: string) =>
    setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const toggleAll = () => setSel(allSel ? new Set() : new Set(sorted.map((r) => r.id)));
  const ids = () => [...sel];

  const by = (key: SortKey) =>
    setSort((s) => (s.key === key ? { key, dir: (s.dir * -1) as 1 | -1 } : { key, dir: 1 }));

  const Th = ({ k, children }: { k: SortKey; children: React.ReactNode }) => (
    <button onClick={() => by(k)} className="inline-flex items-center gap-1 font-medium uppercase tracking-wider hover:text-mute">
      {children}
      {sort.key === k && (
        <span className="text-gold">{sort.dir === 1 ? <IconChevronUp size={12} /> : <IconChevronDown size={12} />}</span>
      )}
    </button>
  );

  const Kpi = ({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: "warn" | "ok" }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={"mt-0.5 text-2xl font-semibold tnum " + (tone === "warn" ? "text-warn" : tone === "ok" ? "text-live" : "text-ink")}>{value}</div>
      {sub && <div className="text-[11px] text-faint">{sub}</div>}
    </div>
  );

  const Chip = ({ f, label, n }: { f: Filter; label: string; n: number }) => (
    <button
      onClick={() => setFlt((cur) => (cur === f ? "all" : f))}
      className={"rounded-md border px-2.5 py-1 text-xs " + (flt === f ? "border-gold/60 bg-gold/10 text-gold" : "border-line text-mute hover:text-ink")}
    >
      {label} <span className="tnum">{n}</span>
    </button>
  );

  return (
    <div className="space-y-3">
      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-6">
        <Kpi label="Companies" value={stats.total} />
        <Kpi label="Verified" value={stats.verified} sub={`${stats.total ? Math.round((stats.verified / stats.total) * 100) : 0}%`} tone={stats.verified === stats.total ? "ok" : undefined} />
        <Kpi label="With logo" value={stats.withLogo} sub={`${stats.noLogo} missing`} tone={stats.noLogo ? "warn" : "ok"} />
        <Kpi label="With brand" value={stats.withBrand} sub={`${stats.noBrand} missing`} tone={stats.noBrand ? "warn" : "ok"} />
        <Kpi label="Funds mapped" value={stats.totalFunds} />
        <Kpi label="Orphans" value={stats.orphan} sub="0 funds" tone={stats.orphan ? "warn" : "ok"} />
      </div>

      {/* type distribution */}
      <div className="flex flex-wrap gap-x-5 gap-y-1 rounded-xl border border-line bg-panel px-4 py-2.5 text-xs text-mute">
        {Object.entries(stats.byType).sort((a, b) => b[1] - a[1]).map(([t, n]) => (
          <span key={t}><span className="tnum font-medium text-ink">{n}</span> {TYPES[t] ?? t}</span>
        ))}
      </div>

      {/* search + quick filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-faint"><SearchIcon /></span>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search name, slug, site…"
            className="w-64 rounded-md border border-line bg-panel2 py-1.5 pl-8 pr-3 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60"
          />
        </div>
        <Chip f="unverified" label="Unverified" n={stats.unverified} />
        <Chip f="nologo" label="No logo" n={stats.noLogo} />
        <Chip f="nobrand" label="No brand" n={stats.noBrand} />
        <Chip f="orphan" label="Orphans" n={stats.orphan} />
        <span className="tnum ml-auto text-xs text-faint">{sorted.length} shown</span>
      </div>

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        {sel.size > 0 && (
          <div className="flex items-center gap-3 border-b border-line bg-panel2 px-4 py-2.5 text-sm">
            <span className="text-mute">{sel.size} selected</span>
            <div className="ml-auto flex items-center gap-2">
              <button disabled={pending} onClick={() => start(() => bulkSetVerified(ids(), true))} className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1 text-xs text-gold hover:bg-gold/20">Verify</button>
              <button disabled={pending} onClick={() => start(() => bulkSetVerified(ids(), false))} className="rounded-md border border-line px-3 py-1 text-xs text-mute hover:text-ink">Unverify</button>
              <button
                disabled={pending}
                onClick={() => { if (confirm(`Delete ${sel.size} companies? Funds are detached, not deleted.`)) { start(async () => { await bulkDeleteCompanies(ids()); setSel(new Set()); }); } }}
                className="rounded-md border border-bad/40 px-3 py-1 text-xs text-bad hover:bg-bad/10"
              >
                Delete
              </button>
            </div>
          </div>
        )}

        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-[11px] text-faint">
              <th className="w-10 px-4 py-3"><input type="checkbox" checked={allSel} onChange={toggleAll} className="accent-gold" /></th>
              <th className="px-3 py-3"><Th k="name">Company</Th></th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Brand</th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Logo</th>
              <th className="px-3 py-3"><Th k="funds">Funds</Th></th>
              <th className="px-3 py-3"><Th k="verified">Verified</Th></th>
              <th className="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            {sorted.map((c) => (
              <tr key={c.id} className="border-b border-line/60 last:border-0 align-top hover:bg-panel2/30">
                <td className="px-4 py-3"><input type="checkbox" checked={sel.has(c.id)} onChange={() => toggle(c.id)} className="mt-1 accent-gold" /></td>

                <td className="px-3 py-3">
                  <form action={updateCompany} className="flex w-[400px] flex-col gap-2">
                    <input type="hidden" name="id" value={c.id} />
                    <input name="name" defaultValue={c.name} className="w-full rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm font-medium text-ink outline-none focus:border-gold/60" />
                    <div className="grid grid-cols-2 gap-2">
                      <LabeledInput label="Website" name="website" defaultValue={c.website} placeholder="https://…" />
                      <LabeledInput label="Phone" name="phone" defaultValue={c.phone} placeholder="+254…" />
                      <LabeledInput label="WhatsApp" name="whatsapp" defaultValue={c.whatsapp} placeholder="+254…" />
                      <LabeledInput label="Email" name="email" defaultValue={c.email} placeholder="name@domain" />
                    </div>
                    <div className="flex items-center gap-2">
                      <select name="type" defaultValue={c.type} className="rounded-md border border-line bg-panel2 px-2 py-1.5 text-xs text-mute outline-none focus:border-gold/60">
                        {Object.entries(TYPES).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                      </select>
                      <button className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20">Save</button>
                      <span className="ml-auto truncate text-[11px] text-faint">{c.id}</span>
                    </div>
                  </form>
                </td>

                <td className="px-3 py-3">
                  <form action={setBrandColor} className="flex items-center gap-1.5">
                    <input type="hidden" name="id" value={c.id} />
                    <span className="h-5 w-5 rounded border border-line" style={{ background: c.brand_color ?? "transparent" }} />
                    <input type="color" name="brand_color" defaultValue={c.brand_color ?? "#8A92A3"} className="h-7 w-10 cursor-pointer rounded border border-line bg-panel2" />
                    <button className="rounded-md border border-gold/50 bg-gold/10 px-2 py-1 text-xs font-medium text-gold hover:bg-gold/20">Set</button>
                  </form>
                </td>

                <td className="px-3 py-3"><LogoCell id={c.id} type={c.type} logoUrl={c.logo_url} /></td>

                <td className="px-3 py-3">
                  <Link href={`/admin/companies/${c.id}`} className="tnum text-mute underline-offset-2 hover:text-gold hover:underline">{counts[c.id] ?? 0}</Link>
                </td>

                <td className="px-3 py-3">
                  <form action={toggleCompanyVerified}>
                    <input type="hidden" name="id" value={c.id} />
                    <input type="hidden" name="value" value={(!c.verified).toString()} />
                    <button title={c.verified ? "Verified" : "Not verified"} className={"inline-flex h-6 w-6 items-center justify-center rounded-md border " + (c.verified ? "border-gold/50 bg-gold/10 text-gold" : "border-line text-faint hover:text-mute")}><IconCheck size={13} /></button>
                  </form>
                </td>

                <td className="px-3 py-3 text-right">
                  <form action={deleteCompany}>
                    <input type="hidden" name="id" value={c.id} />
                    <button className="text-faint hover:text-bad">Delete</button>
                  </form>
                </td>
              </tr>
            ))}
            {sorted.length === 0 && (
              <tr><td colSpan={7} className="px-4 py-10 text-center text-sm text-mute">No companies match.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

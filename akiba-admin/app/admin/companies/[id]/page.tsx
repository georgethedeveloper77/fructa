import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase/server";
import { addFund, setRate, toggleRetail } from "../../funds/actions";
import { updateCustody, updateContact } from "../actions";
import { IconCheck } from "../../_icons";

export const dynamic = "force-dynamic";

type Fund = {
  id: string; name: string; fund_type: string | null; category: string | null;
  currency: string; current_rate: number | null; status: string;
  verified: boolean; featured: boolean; retail: boolean; aum_kes: number | null;
};

const FT_ORDER = ["mmf", "fixed_income", "equity", "balanced", "special"];
const FT_LABEL: Record<string, string> = {
  mmf: "Money Market", fixed_income: "Fixed Income", equity: "Equity",
  balanced: "Balanced", special: "Special",
};
const LEGACY_LABEL: Record<string, string> = {
  tbill: "T-Bills", bond: "Bonds", sacco: "SACCO", stock: "NSE", other: "Other",
};
const TYPE_LABEL: Record<string, string> = {
  fund_manager: "Fund manager", insurer: "Insurer", sacco: "SACCO", government: "Government",
};

function kesShort(n: number | null): string {
  if (n == null) return "—";
  if (n >= 1e9) return `KES ${(n / 1e9).toFixed(1)}B`;
  if (n >= 1e6) return `KES ${(n / 1e6).toFixed(0)}M`;
  return `KES ${Math.round(n).toLocaleString()}`;
}

export default async function CompanyDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const db = supabaseAdmin();

  const { data: c } = await db.from("companies")
    .select("id,name,type,brand_color,logo_url,website,phone,whatsapp,email,verified,manager,aum_kes,market_share,rank,aum_as_of,trustee,custodian,auditor")
    .eq("id", id).maybeSingle();
  if (!c) notFound();

  const { data: fundsData } = await db.from("funds")
    .select("id,name,fund_type,category,currency,current_rate,status,verified,featured,retail,aum_kes")
    .eq("company_id", id).order("name");
  const funds = (fundsData ?? []) as Fund[];

  const groups = new Map<string, Fund[]>();
  for (const f of funds) {
    const k = f.fund_type ?? f.category ?? "other";
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(f);
  }
  const orderedKeys = [
    ...FT_ORDER.filter((k) => groups.has(k)),
    ...[...groups.keys()].filter((k) => !FT_ORDER.includes(k)),
  ];

  const color = c.brand_color ?? "#8A92A3";

  return (
    <div className="mx-auto max-w-5xl">
      <Link href="/admin/companies" className="text-sm text-mute hover:text-gold">← Companies</Link>

      <header className="mt-3 flex items-start gap-4 rounded-xl border border-line bg-panel p-5">
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border border-line bg-white">
          {c.logo_url
            ? <img src={c.logo_url} alt="" className="h-14 w-14 rounded-full object-contain p-1" />
            : <span className="text-lg font-semibold" style={{ color }}>{(c.name || "?").slice(0, 1).toUpperCase()}</span>}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-semibold tracking-tight text-ink">{c.name}</h1>
            {c.verified && (
              <span className="inline-flex h-5 w-5 items-center justify-center rounded-md border border-gold/50 bg-gold/10 text-gold" title="Verified">
                <IconCheck size={12} />
              </span>
            )}
          </div>
          <div className="mt-0.5 flex flex-wrap items-center gap-2 text-xs text-faint">
            <span>{TYPE_LABEL[c.type] ?? c.type}</span>
            <span>·</span>
            <span>{c.id}</span>
            {c.website && (<><span>·</span>
              <a href={c.website} target="_blank" rel="noreferrer" className="text-mute hover:text-gold">
                {c.website.replace(/^https?:\/\//, "")}
              </a></>)}
          </div>
          {c.manager && c.manager !== c.name && (
            <div className="mt-1 text-xs text-mute">Managed by {c.manager}</div>
          )}
        </div>

        <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-right">
          <Stat label="AUM" value={kesShort(c.aum_kes)} />
          <Stat label="Share" value={c.market_share != null ? `${c.market_share}%` : "—"} />
          <Stat label="Rank" value={c.rank != null ? `#${c.rank}` : "—"} />
          <Stat label="Funds" value={String(funds.length)} />
        </div>
      </header>

      {/* AUM-by-fund-type donut — visual summary of the funds below */}
      <AumDonut funds={funds} />

      {/* contact channels — company-level, published to the app fund-detail Contact section */}
      <form action={updateContact} className="mt-4 rounded-xl border border-line bg-panel p-4">
        <input type="hidden" name="id" value={c.id} />
        <div className="mb-3 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-sm font-medium text-ink">Contact</h2>
            <p className="mt-0.5 text-xs text-faint">
              Official website, phone, WhatsApp &amp; email. Published to the app fund-detail Contact section; the app hides any channel left blank.
            </p>
          </div>
          <button className="shrink-0 rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Save</button>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Website</span>
            <input name="website" defaultValue={c.website ?? ""} placeholder="https://…"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Phone</span>
            <input name="phone" defaultValue={c.phone ?? ""} placeholder="+254 7…"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">WhatsApp</span>
            <input name="whatsapp" defaultValue={c.whatsapp ?? ""} placeholder="+254 7…"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Email</span>
            <input name="email" defaultValue={c.email ?? ""} placeholder="invest@domain.com"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
        </div>
      </form>

      {/* governance / custody — manager-level trust signals for the app detail page */}
      <form action={updateCustody} className="mt-4 rounded-xl border border-line bg-panel p-4">
        <input type="hidden" name="id" value={c.id} />
        <div className="mb-3 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-sm font-medium text-ink">Governance &amp; custody</h2>
            <p className="mt-0.5 text-xs text-faint">
              Trustee · custodian · auditor. Surfaced on the app fund detail as trust signals, shared across this manager&rsquo;s funds.
            </p>
          </div>
          <button className="shrink-0 rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Save</button>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Trustee</span>
            <input name="trustee" defaultValue={c.trustee ?? ""} placeholder="KCB Bank"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Custodian</span>
            <input name="custodian" defaultValue={c.custodian ?? ""} placeholder="Stanbic Bank"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-wider text-faint">Auditor</span>
            <input name="auditor" defaultValue={c.auditor ?? ""} placeholder="Grant Thornton"
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
        </div>
      </form>

      {/* inline add fund, scoped to this company */}
      <form action={addFund} className="mt-4 flex flex-wrap items-center gap-2 rounded-xl border border-line bg-panel p-3">
        <input type="hidden" name="company_id" value={c.id} />
        <input name="name" required placeholder="New fund name"
          className="min-w-[200px] flex-1 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
        <select name="fund_type" defaultValue="mmf"
          className="rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm text-mute outline-none focus:border-gold/60">
          {FT_ORDER.map((k) => <option key={k} value={k}>{FT_LABEL[k]}</option>)}
        </select>
        <select name="currency" defaultValue="KES"
          className="rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm text-mute outline-none focus:border-gold/60">
          <option value="KES">KES</option><option value="USD">USD</option>
        </select>
        <input name="min_invest" type="number" min="0" placeholder="Min"
          className="w-20 rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm text-mute outline-none placeholder:text-faint focus:border-gold/60" />
        <input name="mgmt_fee" type="number" step="0.01" min="0" placeholder="Fee %"
          className="w-20 rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm text-mute outline-none placeholder:text-faint focus:border-gold/60" />
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add fund</button>
      </form>

      <div className="mt-4 space-y-5">
        {orderedKeys.map((k) => {
          const list = groups.get(k)!;
          return (
            <section key={k} className="overflow-hidden rounded-xl border border-line bg-panel">
              <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
                <h2 className="text-sm font-medium text-ink">{FT_LABEL[k] ?? LEGACY_LABEL[k] ?? k}</h2>
                <span className="text-xs text-faint">{list.length} {list.length === 1 ? "fund" : "funds"}</span>
              </div>
              <table className="w-full text-sm">
                <tbody>
                  {list.map((f) => (
                    <tr key={f.id} className="border-b border-line/60 last:border-0 hover:bg-panel2/30">
                      <td className="px-4 py-2.5">
                        <div className="font-medium text-ink">{f.name}</div>
                        <div className="text-xs text-faint">
                          {f.currency}{!f.retail ? " · dormant" : ""}{f.aum_kes ? ` · ${kesShort(f.aum_kes)}` : ""}
                        </div>
                      </td>
                      <td className="w-40 px-3 py-2.5">
                        <form action={setRate} className="flex items-center gap-1.5">
                          <input type="hidden" name="id" value={f.id} />
                          <input name="rate" type="number" step="0.01" min="0" max="30"
                            defaultValue={f.current_rate ?? ""} placeholder="—"
                            className="w-20 rounded-md border border-line bg-panel2 px-2 py-1 text-sm tnum text-ink outline-none placeholder:text-faint focus:border-gold/60" />
                          <button className="rounded-md border border-line px-2.5 py-1 text-xs text-mute hover:border-gold/60 hover:text-gold">Set</button>
                        </form>
                      </td>
                      <td className="w-20 px-3 py-2.5">
                        <span className={"text-xs " + (f.status === "live" ? "text-live" : f.status === "stale" ? "text-warn" : "text-faint")}>{f.status}</span>
                      </td>
                      <td className="w-44 px-3 py-2.5 text-right">
                        <div className="flex items-center justify-end gap-2">
                          <form action={toggleRetail}>
                            <input type="hidden" name="id" value={f.id} />
                            <input type="hidden" name="value" value={(!f.retail).toString()} />
                            <button title="Show in the consumer app"
                              className={"rounded-md border px-2 py-1 text-xs " + (f.retail ? "border-gold/40 text-gold" : "border-line text-faint hover:text-mute")}>
                              {f.retail ? "In app" : "Off app"}
                            </button>
                          </form>
                          <Link href={`/admin/funds/${f.id}`} className="text-xs text-mute hover:text-gold">Edit</Link>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
          );
        })}
        {funds.length === 0 && (
          <div className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">
            No funds yet. Add one above.
          </div>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className="tnum text-sm font-medium text-ink">{value}</div>
    </div>
  );
}

// AUM-by-fund-type donut for this company, drawn as inline SVG (no chart lib,
// no glyphs). Only funds with a positive aum_kes count; hidden when the company
// has no AUM data so it never shows an empty or fabricated ring.
const FT_COLOR: Record<string, string> = {
  mmf: "var(--gold)",
  fixed_income: "var(--blue)",
  equity: "var(--violet)",
  balanced: "var(--teal)",
  special: "var(--ok)",
};

function AumDonut({ funds }: { funds: Fund[] }) {
  const byType = new Map<string, number>();
  for (const f of funds) {
    if (f.aum_kes && f.aum_kes > 0) {
      const k = f.fund_type ?? f.category ?? "other";
      byType.set(k, (byType.get(k) ?? 0) + f.aum_kes);
    }
  }
  const total = [...byType.values()].reduce((a, b) => a + b, 0);
  if (total <= 0) return null;

  const segs = [...byType.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => ({ k, v, pct: v / total }));

  let acc = 0;
  const arcs = segs.map((s) => {
    const arc = { ...s, off: acc };
    acc += s.pct * 100;
    return arc;
  });

  return (
    <section className="mt-4 rounded-xl border border-line bg-panel p-4">
      <h2 className="mb-3 text-sm font-medium text-ink">AUM by fund type</h2>
      <div className="flex items-center gap-6">
        <svg width={120} height={120} viewBox="0 0 120 120" className="shrink-0">
          <g transform="rotate(-90 60 60)">
            {arcs.map((a) => (
              <circle
                key={a.k}
                cx={60}
                cy={60}
                r={44}
                fill="none"
                stroke={FT_COLOR[a.k] ?? "var(--muted)"}
                strokeWidth={16}
                pathLength={100}
                strokeDasharray={`${a.pct * 100} 100`}
                strokeDashoffset={-a.off}
              />
            ))}
          </g>
          <text x={60} y={57} textAnchor="middle" style={{ fontSize: 9, fill: "var(--faint)", letterSpacing: "0.06em" }}>AUM</text>
          <text x={60} y={72} textAnchor="middle" style={{ fontSize: 12, fontWeight: 600, fill: "var(--text)", fontFamily: "var(--mono)" }}>{kesShort(total)}</text>
        </svg>
        <div className="flex flex-col gap-2">
          {segs.map((s) => (
            <div key={s.k} className="flex items-center gap-2 text-xs">
              <span className="h-2.5 w-2.5 shrink-0 rounded-sm" style={{ background: FT_COLOR[s.k] ?? "var(--muted)" }} />
              <span className="text-mute">{FT_LABEL[s.k] ?? LEGACY_LABEL[s.k] ?? s.k}</span>
              <span className="tnum ml-6 text-ink">{Math.round(s.pct * 100)}%</span>
              <span className="tnum text-faint">{kesShort(s.v)}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

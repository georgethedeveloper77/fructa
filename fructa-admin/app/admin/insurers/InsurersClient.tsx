"use client";

import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { updateInsurer, deleteInsurer } from "./actions";

type InsClass = { code: string; label: string };
type InsSignal = { tag: string; label: string; text: string };
type TravelRegions = { ea?: number; af?: number; ww?: number; sch?: number };

export type Insurer = {
  id: string;
  name: string;
  company_id: string | null;
  currency: string;
  motor_rate: number | null;
  min_premium: number | null;
  excess_pct: number | null;
  excess_min: number | null;
  claims_days: number | null;
  rating: number | null;
  benefits: string[] | null;
  logo_domain: string | null;
  settle_pct: number | null;
  licensed_since: number | null;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  paybill: string | null;
  website: string | null;
  brand_color: string | null;
  classes: InsClass[] | null;
  signals: InsSignal[] | null;
  travel_regions: TravelRegions | null;
  travel_cover: string | null;
};
export type Company = { id: string; name: string };

const hasMotor = (i: Insurer) => i.motor_rate != null;
const hasTravel = (i: Insurer) =>
  !!i.travel_regions && Object.keys(i.travel_regions).length > 0;
const hasContact = (i: Insurer) => !!(i.phone || i.whatsapp || i.email);
const classCount = (i: Insurer) => (i.classes ?? []).length;
const needsBrand = (i: Insurer) => !i.brand_color;
const needsContact = (i: Insurer) => !hasContact(i);
const incomplete = (i: Insurer) =>
  needsBrand(i) || needsContact(i) || (hasMotor(i) && classCount(i) === 0);

type FilterKey =
  | "all"
  | "motor"
  | "travel"
  | "linked"
  | "standalone"
  | "brand"
  | "contact";

export default function InsurersClient({
  insurers,
  companies,
}: {
  insurers: Insurer[];
  companies: Company[];
}) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<FilterKey>("all");
  const [openId, setOpenId] = useState<string | null>(null);

  const coName = useMemo(() => {
    const m = new Map<string, string>();
    for (const c of companies) m.set(c.id, c.name);
    return m;
  }, [companies]);

  const counts = useMemo(
    () => ({
      all: insurers.length,
      motor: insurers.filter(hasMotor).length,
      travel: insurers.filter(hasTravel).length,
      linked: insurers.filter((i) => !!i.company_id).length,
      standalone: insurers.filter((i) => !i.company_id).length,
      brand: insurers.filter(needsBrand).length,
      contact: insurers.filter(needsContact).length,
    }),
    [insurers],
  );

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    return insurers.filter((i) => {
      if (filter === "motor" && !hasMotor(i)) return false;
      if (filter === "travel" && !hasTravel(i)) return false;
      if (filter === "linked" && !i.company_id) return false;
      if (filter === "standalone" && i.company_id) return false;
      if (filter === "brand" && !needsBrand(i)) return false;
      if (filter === "contact" && !needsContact(i)) return false;
      if (!q) return true;
      const hay = [
        i.name,
        i.id,
        i.logo_domain ?? "",
        i.email ?? "",
        i.company_id ? coName.get(i.company_id) ?? "" : "",
      ]
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [insurers, filter, query, coName]);

  return (
    <div>
      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <Stat label="Insurers" value={counts.all} />
        <Stat label="Motor" value={counts.motor} />
        <Stat label="Travel" value={counts.travel} />
        <Stat label="Linked" value={counts.linked} />
        <Stat label="Needs brand" value={counts.brand} tone="warn" />
        <Stat label="Needs contact" value={counts.contact} tone="warn" />
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <div className="relative min-w-56 flex-1">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-faint">
            <Search />
          </span>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search name, company, domain, email..."
            className="w-full rounded-lg border border-line bg-panel2 py-2 pl-9 pr-3 text-sm text-ink outline-none focus:border-gold/60"
          />
        </div>
        <span className="text-[11px] text-faint">{rows.length} shown</span>
      </div>

      <div className="mb-4 flex flex-wrap gap-1.5">
        <Pill on={filter === "all"} onClick={() => setFilter("all")}>All {counts.all}</Pill>
        <Pill on={filter === "motor"} onClick={() => setFilter("motor")}>Motor {counts.motor}</Pill>
        <Pill on={filter === "travel"} onClick={() => setFilter("travel")}>Travel {counts.travel}</Pill>
        <Pill on={filter === "linked"} onClick={() => setFilter("linked")}>Linked {counts.linked}</Pill>
        <Pill on={filter === "standalone"} onClick={() => setFilter("standalone")}>Standalone {counts.standalone}</Pill>
        <Pill on={filter === "brand"} onClick={() => setFilter("brand")}>Needs brand {counts.brand}</Pill>
        <Pill on={filter === "contact"} onClick={() => setFilter("contact")}>Needs contact {counts.contact}</Pill>
      </div>

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <div className="hidden grid-cols-[1.6rem_1fr_9rem_5rem_5rem_5rem_4rem_2rem] items-center gap-3 border-b border-line px-4 py-2.5 text-[10px] font-semibold uppercase tracking-wider text-faint md:grid">
          <span />
          <span>Insurer</span>
          <span>Company</span>
          <span className="text-right">Motor</span>
          <span className="text-right">Travel</span>
          <span className="text-right">Classes</span>
          <span className="text-center">Reach</span>
          <span />
        </div>

        {rows.map((i) => {
          const open = openId === i.id;
          return (
            <div key={i.id} className="border-b border-line last:border-b-0">
              <button
                type="button"
                onClick={() => setOpenId(open ? null : i.id)}
                className="grid w-full grid-cols-[1.6rem_1fr_auto] items-center gap-3 px-4 py-3 text-left hover:bg-panel2/60 md:grid-cols-[1.6rem_1fr_9rem_5rem_5rem_5rem_4rem_2rem]"
              >
                <span
                  className="h-4 w-4 rounded"
                  style={{ background: i.brand_color ?? "transparent" }}
                >
                  {!i.brand_color && (
                    <span className="block h-4 w-4 rounded border border-line2" />
                  )}
                </span>

                <span className="min-w-0">
                  <span className="flex items-center gap-1.5">
                    <span className="truncate text-sm font-medium text-ink">{i.name}</span>
                    {incomplete(i) && <Dot />}
                  </span>
                  <span className="mt-0.5 block truncate text-[11px] text-faint">{i.id}</span>
                </span>

                <span className="hidden truncate text-xs text-mute md:block">
                  {i.company_id ? coName.get(i.company_id) ?? i.company_id : "standalone"}
                </span>
                <span className="hidden text-right text-xs md:block">
                  {i.motor_rate != null ? (
                    <span className="font-mono text-ink">{i.motor_rate}%</span>
                  ) : (
                    <span className="text-faint">.</span>
                  )}
                </span>
                <span className="hidden text-right text-xs md:block">
                  {hasTravel(i) ? (
                    <span className="font-mono text-ink">{Object.keys(i.travel_regions ?? {}).length}</span>
                  ) : (
                    <span className="text-faint">.</span>
                  )}
                </span>
                <span className="hidden text-right text-xs md:block">
                  {classCount(i) > 0 ? (
                    <span className="font-mono text-ink">{classCount(i)}</span>
                  ) : (
                    <span className="text-faint">.</span>
                  )}
                </span>
                <span className="hidden items-center justify-center gap-1 md:flex">
                  <Reach on={!!i.phone}>P</Reach>
                  <Reach on={!!i.whatsapp}>W</Reach>
                  <Reach on={!!i.email}>E</Reach>
                </span>

                <span className="justify-self-end text-faint">
                  <Caret open={open} />
                </span>
              </button>

              {open && (
                <Editor insurer={i} companies={companies} />
              )}
            </div>
          );
        })}

        {rows.length === 0 && (
          <p className="px-4 py-10 text-center text-sm text-mute">
            No insurers match this view.
          </p>
        )}
      </div>
    </div>
  );
}

function Editor({ insurer: i, companies }: { insurer: Insurer; companies: Company[] }) {
  return (
    <form action={updateInsurer} className="border-t border-line bg-panel2/40 px-4 py-4">
      <input type="hidden" name="id" value={i.id} />

      <div className="mb-3 flex flex-wrap items-end gap-2">
        <Field label="Name" w="w-64">
          <input name="name" defaultValue={i.name} className={inp} />
        </Field>
        <Field label="Company">
          <select name="company_id" defaultValue={i.company_id ?? ""} className={inp}>
            <option value="">no company</option>
            {companies.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </Field>
        <Field label="Currency">
          <select name="currency" defaultValue={i.currency} className={inp}>
            <option>KES</option>
            <option>USD</option>
          </select>
        </Field>
      </div>

      <Legend>Motor</Legend>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Num label="Motor rate %" name="motor_rate" v={i.motor_rate} />
        <Num label="Min premium" name="min_premium" v={i.min_premium} />
        <Num label="Excess %" name="excess_pct" v={i.excess_pct} />
        <Num label="Excess min" name="excess_min" v={i.excess_min} />
        <Num label="Claims (days)" name="claims_days" v={i.claims_days} />
        <Num label="Rating (1-5)" name="rating" v={i.rating} />
      </div>

      <label className="mt-3 flex flex-col gap-1">
        <Cap>Benefits (comma-separated)</Cap>
        <input name="benefits" defaultValue={(i.benefits ?? []).join(", ")} placeholder="Courtesy car 14d, Windscreen 75k, Roadside" className={inp} />
      </label>

      <Legend>Trust &amp; identity</Legend>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Num label="Claims paid % (IRA)" name="settle_pct" v={i.settle_pct} />
        <Num label="Licensed since" name="licensed_since" v={i.licensed_since} />
        <Txt label="Brand colour (hex)" name="brand_color" v={i.brand_color} placeholder="#4E8FE8" />
        <Txt label="Logo domain" name="logo_domain" v={i.logo_domain} placeholder="cic.co.ke" />
      </div>

      <Legend>Reach them</Legend>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Txt label="Phone" name="phone" v={i.phone} placeholder="+254 703 099 000" />
        <Txt label="WhatsApp" name="whatsapp" v={i.whatsapp} placeholder="+254 703 099 120" />
        <Txt label="Email" name="email" v={i.email} placeholder="callc@cic.co.ke" />
        <Txt label="Paybill" name="paybill" v={i.paybill} placeholder="600118" />
        <Txt label="Website" name="website" v={i.website} placeholder="cic.co.ke" />
      </div>

      <label className="mt-3 flex flex-col gap-1">
        <Cap>Licensed classes (one per line: code, label)</Cap>
        <textarea name="classes" rows={3} defaultValue={(i.classes ?? []).map((c) => `${c.code}, ${c.label}`).join("\n")} placeholder={"07, Motor Priv\n08, Motor Comm\n09, Personal Acc"} className={mono} />
      </label>

      <label className="mt-3 flex flex-col gap-1">
        <Cap>Signals (one per line: TAG | text, TAG in STRENGTH/WATCH/NOTE)</Cap>
        <textarea name="signals" rows={3} defaultValue={(i.signals ?? []).map((s) => `${s.tag} | ${s.text}`).join("\n")} placeholder={"STRENGTH | Fastest claims settlement in the set plus a courtesy car.\nWATCH | 3% excess is the trade-off."} className={mono} />
      </label>

      <Legend>Travel (region base price per traveller, standard trip)</Legend>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Num label="East Africa" name="travel_ea" v={i.travel_regions?.ea ?? null} />
        <Num label="Africa" name="travel_af" v={i.travel_regions?.af ?? null} />
        <Num label="Worldwide" name="travel_ww" v={i.travel_regions?.ww ?? null} />
        <Num label="Schengen" name="travel_sch" v={i.travel_regions?.sch ?? null} />
      </div>
      <label className="mt-3 flex flex-col gap-1">
        <Cap>Travel cover headline</Cap>
        <input name="travel_cover" defaultValue={i.travel_cover ?? ""} placeholder="KES 5M med" className={inp} />
      </label>

      <div className="mt-4 flex items-center gap-3">
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Save</button>
        <button formAction={deleteInsurer} className="rounded-md border border-bad/40 px-3 py-1.5 text-xs text-bad hover:bg-bad/10">Delete</button>
      </div>
    </form>
  );
}

const inp =
  "rounded-md border border-line bg-panel px-2.5 py-1.5 text-sm text-ink outline-none focus:border-gold/60";
const mono =
  "rounded-md border border-line bg-panel px-2.5 py-2 font-mono text-xs text-ink outline-none focus:border-gold/60";

function Stat({ label, value, tone }: { label: string; value: number; tone?: "warn" }) {
  const c = tone === "warn" ? "text-gold" : "text-ink";
  return (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${c}`}>{value}</div>
    </div>
  );
}

function Pill({ on, onClick, children }: { on: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        on
          ? "rounded-full border border-gold/50 bg-gold/10 px-3 py-1 text-xs font-medium text-gold"
          : "rounded-full border border-line bg-panel2 px-3 py-1 text-xs text-mute hover:border-line2"
      }
    >
      {children}
    </button>
  );
}

function Reach({ on, children }: { on: boolean; children: ReactNode }) {
  return (
    <span
      className={
        on
          ? "flex h-4 w-4 items-center justify-center rounded text-[9px] font-semibold text-ink"
          : "flex h-4 w-4 items-center justify-center rounded text-[9px] font-semibold text-faint/50"
      }
    >
      {children}
    </span>
  );
}

function Dot() {
  return <span className="inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-gold" title="Needs brand, contact, or classes" />;
}

function Field({ label, w, children }: { label: string; w?: string; children: ReactNode }) {
  return (
    <label className={`flex flex-col gap-1 ${w ?? ""}`}>
      <Cap>{label}</Cap>
      {children}
    </label>
  );
}

function Cap({ children }: { children: ReactNode }) {
  return <span className="text-[11px] uppercase tracking-wider text-faint">{children}</span>;
}

function Legend({ children }: { children: ReactNode }) {
  return <div className="mb-2 mt-4 text-[11px] font-semibold uppercase tracking-wider text-faint">{children}</div>;
}

function Num({ label, name, v }: { label: string; name: string; v: number | null }) {
  return (
    <label className="flex flex-col gap-1">
      <Cap>{label}</Cap>
      <input name={name} defaultValue={v ?? ""} inputMode="decimal" className={inp} />
    </label>
  );
}

function Txt({ label, name, v, placeholder }: { label: string; name: string; v: string | null; placeholder?: string }) {
  return (
    <label className="flex flex-col gap-1">
      <Cap>{label}</Cap>
      <input name={name} defaultValue={v ?? ""} placeholder={placeholder} className={inp} />
    </label>
  );
}

function Search() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" />
      <path d="m21 21-4.3-4.3" />
    </svg>
  );
}

function Caret({ open }: { open: boolean }) {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={open ? "rotate-180 transition-transform" : "transition-transform"}>
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}

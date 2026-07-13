"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { toggleSaccoActive } from "./actions";
import { IconChevronUp, IconChevronDown } from "../_icons";

export type SaccoRow = {
  id: string;
  name: string;
  display_name: string | null;
  county: string | null;
  common_bond: string;
  bond_note: string | null;
  tier: number | null;
  logo_url: string | null;
  brand_color: string | null;
  members: number | null;
  total_assets_kes: number | null;
  active: boolean;
  // The two rates. They are separate columns here for the same reason they are
  // separate fields in the snapshot: one number that could be either one is how
  // the 21%-versus-11.3% confusion gets built into the product.
  deposits: number | null; // interest_on_deposits, latest declared year
  dividend: number | null; // dividend_on_share_capital, same year
  rate_year: number | null;
  rate_count: number; // how many years we hold
};

const TINTS = ["#E7B24C", "#5B8DEF", "#A78BFA", "#3DD6C4", "#3DDC97"];
function hashTint(seed: string) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return TINTS[h % TINTS.length];
}

type SortKey = "name" | "county" | "deposits" | "dividend" | "assets" | "members";

const BOND_LABEL: Record<string, string> = {
  open: "open",
  closed: "closed",
  unknown: "unknown",
};

export function SaccosTable({ rows }: { rows: SaccoRow[] }) {
  const [q, setQ] = useState("");
  const [bond, setBond] = useState<string>("all");
  const [county, setCounty] = useState<string>("all");
  const [sort, setSort] = useState<{ key: SortKey; dir: 1 | -1 }>({
    key: "deposits",
    dir: -1,
  });

  const counties = useMemo(() => {
    const s = new Set<string>();
    for (const r of rows) if (r.county) s.add(r.county);
    return [...s].sort();
  }, [rows]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const base = rows.filter((s) => {
      if (bond !== "all" && s.common_bond !== bond) return false;
      if (county !== "all" && s.county !== county) return false;
      if (needle && !`${s.name} ${s.county ?? ""}`.toLowerCase().includes(needle)) {
        return false;
      }
      return true;
    });

    // A null rate always sinks, in either direction. A society with no declared
    // rate is not the worst payer, it is an unknown, and sorting it to the
    // bottom of an ascending list would be a claim we cannot support.
    const nullsLast = (
      av: number | null,
      bv: number | null,
    ): number | "both" | "a" | "b" => {
      if (av == null && bv == null) return "both";
      if (av == null) return "a";
      if (bv == null) return "b";
      return av - bv;
    };

    base.sort((a, b) => {
      let r = 0;
      switch (sort.key) {
        case "name":
          r = a.name.localeCompare(b.name);
          break;
        case "county":
          r = (a.county ?? "").localeCompare(b.county ?? "");
          break;
        case "deposits": {
          const v = nullsLast(a.deposits, b.deposits);
          if (v === "a") return 1;
          if (v === "b") return -1;
          r = v === "both" ? 0 : v;
          break;
        }
        case "dividend": {
          const v = nullsLast(a.dividend, b.dividend);
          if (v === "a") return 1;
          if (v === "b") return -1;
          r = v === "both" ? 0 : v;
          break;
        }
        case "assets": {
          const v = nullsLast(a.total_assets_kes, b.total_assets_kes);
          if (v === "a") return 1;
          if (v === "b") return -1;
          r = v === "both" ? 0 : v;
          break;
        }
        case "members": {
          const v = nullsLast(a.members, b.members);
          if (v === "a") return 1;
          if (v === "b") return -1;
          r = v === "both" ? 0 : v;
          break;
        }
      }
      return r * sort.dir;
    });
    return base;
  }, [rows, bond, county, q, sort]);

  const by = (key: SortKey) =>
    setSort((s) =>
      s.key === key ? { key, dir: (s.dir * -1) as 1 | -1 } : { key, dir: -1 }
    );

  const Th = ({ k, children }: { k: SortKey; children: React.ReactNode }) => (
    <th className="px-3 py-3">
      <button
        onClick={() => by(k)}
        className="inline-flex items-center gap-1 font-medium uppercase tracking-wider hover:text-mute"
      >
        {children}
        {sort.key === k && (
          <span className="text-gold">
            {sort.dir === 1 ? <IconChevronUp size={12} /> : <IconChevronDown size={12} />}
          </span>
        )}
      </button>
    </th>
  );

  const bondBtn = (key: string, label: string) => (
    <button
      key={key}
      onClick={() => setBond(key)}
      className={"rounded-md px-2.5 py-1 text-sm " +
        (bond === key ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}
    >
      {label}
    </button>
  );

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search name or county"
          className="w-64 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60"
        />

        <div className="flex flex-wrap items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
          {bondBtn("all", "All bonds")}
          {bondBtn("open", "Open")}
          {bondBtn("closed", "Closed")}
          {bondBtn("unknown", "Unknown")}
        </div>

        {counties.length > 0 && (
          <select
            value={county}
            onChange={(e) => setCounty(e.target.value)}
            className="rounded-md border border-line bg-panel2 px-2.5 py-1.5 text-sm text-ink outline-none focus:border-gold/60"
          >
            <option value="all">All counties</option>
            {counties.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        )}

        <span className="tnum ml-auto text-xs text-faint">
          {filtered.length} societies
        </span>
      </div>

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-[11px] text-faint">
              <Th k="name">Society</Th>
              <Th k="county">County</Th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Bond</th>
              <Th k="deposits">On deposits</Th>
              <Th k="dividend">Dividend</Th>
              <Th k="members">Members</Th>
              <Th k="assets">Assets</Th>
              <th className="px-3 py-3 font-medium uppercase tracking-wider">Status</th>
              <th className="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            {filtered.map((s) => {
              const color = s.brand_color ?? hashTint(s.name);
              return (
                <tr
                  key={s.id}
                  className="border-b border-line/60 last:border-0 hover:bg-panel2/30"
                >
                  <td className="px-3 py-3">
                    <div className="flex items-center gap-3">
                      <span
                        className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full border border-line"
                        style={s.logo_url
                          ? { background: "#fff" }
                          : {
                            background: `color-mix(in srgb, ${color} 18%, transparent)`,
                            color,
                          }}
                      >
                        {s.logo_url
                          ? <img src={s.logo_url} alt="" className="h-8 w-8 object-contain p-0.5" />
                          : (
                            <span className="text-xs font-semibold">
                              {(s.name || "?").slice(0, 1).toUpperCase()}
                            </span>
                          )}
                      </span>
                      <div className="min-w-0">
                        <div className="font-medium text-ink">
                          {s.display_name ?? s.name}
                        </div>
                        <div className="text-xs text-faint">
                          {s.tier != null ? `Tier ${s.tier}` : "no tier"}
                        </div>
                      </div>
                    </div>
                  </td>

                  <td className="px-3 py-3 text-mute">{s.county ?? "not set"}</td>

                  {/* Bond. Unknown is called out in warn, not left neutral. It is
                      the field that decides whether a user is shown this society
                      as joinable at all, and every seeded row starts unknown
                      because SASRA does not publish it. */}
                  <td className="px-3 py-3">
                    <span
                      className={"rounded-md border px-2 py-0.5 text-xs " +
                        (s.common_bond === "open"
                          ? "border-live/40 bg-live/10 text-live"
                          : s.common_bond === "closed"
                          ? "border-line bg-panel2 text-faint"
                          : "border-warn/40 bg-warn/10 text-warn")}
                    >
                      {BOND_LABEL[s.common_bond] ?? s.common_bond}
                    </span>
                    {s.bond_note && (
                      <div className="mt-1 text-[10px] text-faint">{s.bond_note}</div>
                    )}
                  </td>

                  {/* The ranked rate. Paid on savings, which are uncapped. This
                      is the number the app sorts on and the number that decides
                      how much money a member actually receives. */}
                  <td className="px-3 py-3">
                    {s.deposits != null
                      ? (
                        <div className="flex flex-col leading-tight">
                          <span className="tnum text-sm text-live">
                            {s.deposits.toFixed(2)}%
                          </span>
                          <span className="text-[10px] text-faint">
                            FY{s.rate_year} {"\u00B7"} {s.rate_count}{" "}
                            {s.rate_count === 1 ? "year" : "years"}
                          </span>
                        </div>
                      )
                      : <span className="text-xs text-faint">no rate yet</span>}
                  </td>

                  {/* Display only. Never sorted on by the app, and never the
                      headline on a tile. It is the bigger percentage and the
                      smaller cheque. */}
                  <td className="px-3 py-3">
                    {s.dividend != null
                      ? (
                        <span className="tnum text-sm text-gold">
                          {s.dividend.toFixed(2)}%
                        </span>
                      )
                      : <span className="text-xs text-faint">not set</span>}
                  </td>

                  <td className="px-3 py-3">
                    {s.members != null
                      ? (
                        <span className="tnum text-xs text-mute">
                          {s.members.toLocaleString("en-KE")}
                        </span>
                      )
                      : <span className="text-xs text-faint">not set</span>}
                  </td>

                  <td className="px-3 py-3">
                    {s.total_assets_kes != null
                      ? (
                        <span className="tnum text-xs text-mute">
                          {(s.total_assets_kes / 1e9).toFixed(2)}B
                        </span>
                      )
                      : <span className="text-xs text-faint">not set</span>}
                  </td>

                  <td className="px-3 py-3">
                    <div className="flex items-center gap-2">
                      <span className={"text-xs " + (s.active ? "text-live" : "text-faint")}>
                        {s.active ? "live" : "hidden"}
                      </span>
                      <form action={toggleSaccoActive}>
                        <input type="hidden" name="id" value={s.id} />
                        <input type="hidden" name="value" value={(!s.active).toString()} />
                        <button className="rounded-md border border-line px-2 py-0.5 text-xs text-mute hover:text-ink">
                          {s.active ? "Hide" : "Show"}
                        </button>
                      </form>
                    </div>
                  </td>

                  <td className="px-3 py-3 text-right">
                    <Link
                      href={`/admin/saccos/${s.id}`}
                      className="text-xs text-mute hover:text-gold"
                    >
                      Edit
                    </Link>
                  </td>
                </tr>
              );
            })}
            {filtered.length === 0 && (
              <tr>
                <td colSpan={9} className="px-4 py-10 text-center text-sm text-mute">
                  No societies match.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

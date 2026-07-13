import Link from "next/link";
import { supabaseAdmin } from "@/lib/supabase/server";
import { SaccosTable, type SaccoRow } from "./SaccosTable";
import { AddSacco } from "./AddSacco";
import { ImportSaccoRates } from "./ImportSaccoRates";

export const dynamic = "force-dynamic";

type RateRow = {
  sacco_id: string;
  financial_year: number;
  interest_on_deposits: number | null;
  dividend_on_share_capital: number | null;
};

export default async function SaccosPage() {
  const db = supabaseAdmin();

  const [
    { data: saccoData, error },
    { data: rateData },
    { data: cfgEnabled },
    { data: cfgAllTab },
  ] = await Promise.all([
    db.from("saccos")
      .select(
        "id,name,display_name,county,common_bond,bond_note,tier,logo_url,brand_color,members,total_assets_kes,active",
      )
      // Credit-only societies (SASRA Schedule III) are seeded so the register is
      // complete, and they are prohibited by law from taking new deposits. They
      // are not part of this lane and the snapshot never publishes them.
      .eq("licence_class", "dt")
      .order("name"),
    db.from("sacco_rates").select(
      "sacco_id,financial_year,interest_on_deposits,dividend_on_share_capital",
    ),
    db.from("app_config").select("value").eq("key", "saccos.enabled").maybeSingle(),
    db.from("app_config").select("value").eq("key", "saccos.in_all_tab").maybeSingle(),
  ]);

  const enabled = cfgEnabled?.value === true;
  const inAllTab = cfgAllTab?.value === true;

  // Latest declared year per society. Mirrors what publish-snapshot computes, so
  // admin and app agree on which year is the headline.
  const bySacco = new Map<string, RateRow[]>();
  for (const r of (rateData ?? []) as RateRow[]) {
    const arr = bySacco.get(r.sacco_id) ?? [];
    arr.push(r);
    bySacco.set(r.sacco_id, arr);
  }

  const rows: SaccoRow[] = ((saccoData ?? []) as Omit<
    SaccoRow,
    "deposits" | "dividend" | "rate_year" | "rate_count"
  >[]).map((s) => {
    const rs = bySacco.get(s.id) ?? [];
    const year = rs.length ? Math.max(...rs.map((r) => r.financial_year)) : null;
    const latest = year == null
      ? null
      : rs.find((r) => r.financial_year === year) ?? null;

    return {
      ...s,
      deposits: latest?.interest_on_deposits == null
        ? null
        : Number(latest.interest_on_deposits),
      dividend: latest?.dividend_on_share_capital == null
        ? null
        : Number(latest.dividend_on_share_capital),
      rate_year: year,
      rate_count: rs.length,
    };
  });

  const total = rows.length;
  const live = rows.filter((s) => s.active).length;
  const withRate = rows.filter((s) => s.deposits != null).length;
  const openBond = rows.filter((s) => s.common_bond === "open").length;
  const unknownBond = rows.filter((s) => s.common_bond === "unknown").length;
  const withTier = rows.filter((s) => s.tier != null).length;

  // The number that actually matters, and the reason it gets its own KPI.
  //
  // A society is only USEFUL to a user when it has both a deposit rate to rank
  // on and a confirmed open bond they can actually join. Counting "has a rate"
  // alone would make the lane look ready while every one of those societies was
  // still marked unknown-bond and therefore hidden as not joinable.
  const usable = rows.filter(
    (s) => s.deposits != null && s.common_bond === "open" && s.active,
  ).length;

  const kpis: {
    label: string;
    value: number | string;
    sub?: string;
    tone?: "warn" | "ok" | "bad";
  }[] = [
    { label: "Societies", value: total, sub: "SASRA deposit taking" },
    { label: "In app", value: live },
    {
      label: "With deposit rate",
      value: withRate,
      sub: withRate === 0 ? "no AGM rates imported" : "from AGM declarations",
      tone: withRate === 0 ? "bad" : withRate < 10 ? "warn" : "ok",
    },
    {
      label: "Open bond",
      value: openBond,
      sub: "anyone can join",
      tone: openBond === 0 ? "warn" : "ok",
    },
    {
      label: "Bond unknown",
      value: unknownBond,
      sub: "hidden as not joinable",
      tone: unknownBond > 0 ? "warn" : "ok",
    },
    {
      label: "Live and joinable",
      value: usable,
      sub: "rate plus open bond",
      tone: usable === 0 ? "bad" : usable < 5 ? "warn" : "ok",
    },
    { label: "Tier set", value: withTier, sub: "from SASRA report" },
  ];

  return (
    <div className="mx-auto max-w-6xl">
      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">
          {error.message}
        </p>
      )}

      {/* The kill switch, stated where someone is actually looking. With it off
          the snapshot builder does not even run the query and the app sees an
          empty array, so the whole surface can be prepared without shipping a
          half-populated SACCO tab to anyone. */}
      {!enabled && (
        <div className="mb-3 rounded-xl border border-warn/30 bg-warn/5 px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-warn">
            SACCOs are switched off
          </div>
          <p className="mt-1 text-sm leading-relaxed text-mute">
            The <code className="text-faint">saccos.enabled</code> switch is off, so
            the snapshot publishes no societies at all and the app shows no SACCO
            tab. Import at least one AGM rate, confirm at least one open bond, then
            turn it on in{" "}
            <Link href="/admin/config" className="text-gold underline underline-offset-2">
              Config
            </Link>{" "}
            and the app picks them up on the next rebuild, with no release.
          </p>
        </div>
      )}

      {/* Turning SACCOs on is one decision. Letting them into the All league
          table, where they get ranked directly against a money market fund, is a
          separate one, so it is a separate switch. A SACCO deposit rate is paid
          on money you cannot withdraw until you resign your membership; an MMF
          yield is paid on money you get back in two working days. They are the
          same shape as numbers and they are not the same shape as promises. */}
      {enabled && !inAllTab && (
        <div className="mb-3 rounded-xl border border-line bg-panel px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-faint">
            SACCOs are live, but not in the All tab
          </div>
          <p className="mt-1 text-sm leading-relaxed text-mute">
            Societies show on their own tab.{" "}
            <code className="text-faint">saccos.in_all_tab</code> is off, so they are
            not yet ranked against money market funds and T-bills. Turn it on only
            when you are happy that the lock badge reads clearly, because in that
            list a SACCO will usually be the top row and its money is the least
            accessible on the page.
          </p>
        </div>
      )}

      {enabled && withRate === 0 && (
        <div className="mb-3 rounded-xl border border-bad/40 bg-bad/10 px-4 py-3">
          <div className="text-[11px] uppercase tracking-wider text-bad">
            Switched on with no rates
          </div>
          <p className="mt-1 text-sm leading-relaxed text-mute">
            No society has a declared deposit rate, so the app is showing a SACCO
            tab that ranks nothing. Import the AGM rates below, or switch{" "}
            <code className="text-faint">saccos.enabled</code> back off.
          </p>
        </div>
      )}

      <div className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
        {kpis.map((k) => (
          <div key={k.label} className="rounded-xl border border-line bg-panel px-4 py-3">
            <div className="text-[10px] uppercase tracking-wider text-faint">
              {k.label}
            </div>
            <div
              className={"mt-0.5 text-2xl font-semibold tnum " +
                (k.tone === "warn"
                  ? "text-warn"
                  : k.tone === "bad"
                  ? "text-bad"
                  : k.tone === "ok"
                  ? "text-live"
                  : "text-ink")}
            >
              {k.value}
            </div>
            {k.sub && <div className="text-[11px] text-faint">{k.sub}</div>}
          </div>
        ))}
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex flex-1 flex-wrap gap-x-5 gap-y-1 rounded-xl border border-line bg-panel px-4 py-2.5 text-xs text-mute">
          <span>
            <span className="tnum font-medium text-ink">
              {new Set(rows.map((s) => s.county).filter(Boolean)).size}
            </span>{" "}
            counties
          </span>
          <span>
            <span className="tnum font-medium text-ink">
              {rows.filter((s) => s.common_bond === "closed").length}
            </span>{" "}
            closed bond
          </span>
          <span>
            <span className="tnum font-medium text-ink">
              {rows.filter((s) => s.dividend != null).length}
            </span>{" "}
            with dividend
          </span>
          <span>
            <span className="tnum font-medium text-ink">
              {rows.filter((s) => s.total_assets_kes != null).length}
            </span>{" "}
            with assets
          </span>
        </div>
        <AddSacco />
      </div>

      <ImportSaccoRates />

      <SaccosTable rows={rows} />
    </div>
  );
}

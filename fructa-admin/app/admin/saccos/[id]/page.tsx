import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase/server";
import {
  updateSaccoProfile,
  updateSaccoBond,
  updateSaccoTerms,
  updateSaccoInstitution,
  saveSaccoRate,
  deleteSaccoRate,
} from "../actions";

export const dynamic = "force-dynamic";

const field =
  "w-full rounded-md border border-line bg-panel2 px-3 py-2 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const label = "mb-1 block text-[11px] uppercase tracking-wider text-faint";
const save =
  "rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20";

function Section(
  { title, note, children }: {
    title: string;
    note?: string;
    children: React.ReactNode;
  },
) {
  return (
    <div className="rounded-xl border border-line bg-panel p-5">
      <div className="mb-4">
        <h2 className="text-base font-semibold text-ink">{title}</h2>
        {note && <p className="mt-1 text-xs leading-relaxed text-mute">{note}</p>}
      </div>
      {children}
    </div>
  );
}

type SaccoRate = {
  id: string;
  financial_year: number;
  interest_on_deposits: number | null;
  dividend_on_share_capital: number | null;
  declared_on: string | null;
  source_url: string | null;
  source_doc: string | null;
};

export default async function SaccoEditPage(
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const db = supabaseAdmin();

  const [{ data: s }, { data: rateData }] = await Promise.all([
    db.from("saccos").select("*").eq("id", id).maybeSingle(),
    db.from("sacco_rates")
      .select(
        "id,financial_year,interest_on_deposits,dividend_on_share_capital,declared_on,source_url,source_doc",
      )
      .eq("sacco_id", id)
      .order("financial_year", { ascending: false }),
  ]);

  if (!s) notFound();
  const rates = (rateData ?? []) as SaccoRate[];
  const nextYear = new Date().getFullYear() - 1;

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <Link href="/admin/saccos" className="text-xs text-faint hover:text-gold">
            Back to SACCOs
          </Link>
          <h1 className="mt-1 text-xl font-semibold text-ink">
            {s.display_name ?? s.name}
          </h1>
          <p className="font-mono text-xs text-faint">{s.id}</p>
        </div>
        <span
          className={"rounded-md border px-2 py-0.5 text-xs " +
            (s.common_bond === "open"
              ? "border-live/40 bg-live/10 text-live"
              : s.common_bond === "closed"
              ? "border-line bg-panel2 text-faint"
              : "border-warn/40 bg-warn/10 text-warn")}
        >
          {s.common_bond} bond
        </span>
      </div>

      {/* ── Rates ─────────────────────────────────────────────────────────── */}
      <Section
        title="Declared rates"
        note="Two rates per year, and they are not interchangeable. Interest on deposits is paid on member savings, which are uncapped, and it is the number the app ranks on. The dividend is paid on share capital, which is capped: it is nearly always the bigger percentage and nearly always the smaller cheque. The financial year is the year that ended, so a March 2026 AGM declaring for the year to 31 December 2025 is 2025."
      >
        {rates.length > 0 && (
          <div className="mb-4 overflow-hidden rounded-lg border border-line">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-line bg-panel2 text-left text-[10px] uppercase tracking-wider text-faint">
                  <th className="px-3 py-2">Year</th>
                  <th className="px-3 py-2">On deposits</th>
                  <th className="px-3 py-2">Dividend</th>
                  <th className="px-3 py-2">Declared</th>
                  <th className="px-3 py-2">Source</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody>
                {rates.map((r) => (
                  <tr key={r.id} className="border-b border-line/60 last:border-0">
                    <td className="tnum px-3 py-2 text-ink">FY{r.financial_year}</td>
                    <td className="tnum px-3 py-2 text-live">
                      {r.interest_on_deposits == null
                        ? "not set"
                        : `${Number(r.interest_on_deposits).toFixed(2)}%`}
                    </td>
                    <td className="tnum px-3 py-2 text-gold">
                      {r.dividend_on_share_capital == null
                        ? "not set"
                        : `${Number(r.dividend_on_share_capital).toFixed(2)}%`}
                    </td>
                    <td className="px-3 py-2 text-faint">{r.declared_on ?? "not set"}</td>
                    <td className="px-3 py-2 text-faint">
                      {r.source_url
                        ? (
                          <a
                            href={r.source_url}
                            target="_blank"
                            rel="noreferrer"
                            className="text-mute underline underline-offset-2 hover:text-gold"
                          >
                            {r.source_doc ?? "link"}
                          </a>
                        )
                        : (r.source_doc ?? "not set")}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <form action={deleteSaccoRate}>
                        <input type="hidden" name="id" value={r.id} />
                        <input type="hidden" name="sacco_id" value={s.id} />
                        <button className="text-xs text-faint hover:text-bad">Delete</button>
                      </form>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <form action={saveSaccoRate} className="space-y-3">
          <input type="hidden" name="sacco_id" value={s.id} />
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Financial year ended</label>
              <input
                name="financial_year"
                type="number"
                defaultValue={nextYear}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Interest on deposits %</label>
              <input
                name="interest_on_deposits"
                type="number"
                step="0.001"
                placeholder="13.0"
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Dividend on shares %</label>
              <input
                name="dividend_on_share_capital"
                type="number"
                step="0.001"
                placeholder="20.0"
                className={field + " tnum"}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Declared on (AGM)</label>
              <input name="declared_on" type="date" className={field} />
            </div>
            <div>
              <label className={label}>Source document</label>
              <input
                name="source_doc"
                placeholder="Audited financial statements FY2025"
                className={field}
              />
            </div>
            <div>
              <label className={label}>Source URL</label>
              <input name="source_url" placeholder="https://" className={field} />
            </div>
          </div>
          <div className="flex justify-end">
            <button className={save}>Save year</button>
          </div>
        </form>
      </Section>

      {/* ── Bond ──────────────────────────────────────────────────────────── */}
      <Section
        title="Common bond"
        note="Whether a user can join at all, which matters more than the rate: a society you cannot join has no business outranking one you can. SASRA does not publish this, so it has to be confirmed against the society's own terms. Unknown is treated as not joinable, never as open."
      >
        <form action={updateSaccoBond} className="space-y-3">
          <input type="hidden" name="id" value={s.id} />
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Bond</label>
              <select
                name="common_bond"
                defaultValue={s.common_bond ?? "unknown"}
                className={field}
              >
                <option value="unknown">Unknown, not yet confirmed</option>
                <option value="open">Open, anyone can join</option>
                <option value="closed">Closed, restricted membership</option>
              </select>
            </div>
            <div className="col-span-2">
              <label className={label}>Who it is restricted to</label>
              <input
                name="bond_note"
                defaultValue={s.bond_note ?? ""}
                placeholder="University of Nairobi staff"
                className={field}
              />
            </div>
          </div>
          <div className="flex justify-end">
            <button className={save}>Save bond</button>
          </div>
        </form>
      </Section>

      {/* ── Profile ───────────────────────────────────────────────────────── */}
      <Section title="Profile">
        <form action={updateSaccoProfile} className="space-y-3">
          <input type="hidden" name="id" value={s.id} />
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={label}>Registered name</label>
              <input name="name" defaultValue={s.name ?? ""} className={field} />
            </div>
            <div>
              <label className={label}>Display name</label>
              <input
                name="display_name"
                defaultValue={s.display_name ?? ""}
                className={field}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>County</label>
              <input name="county" defaultValue={s.county ?? ""} className={field} />
            </div>
            <div className="col-span-2">
              <label className={label}>Head office</label>
              <input
                name="physical_location"
                defaultValue={s.physical_location ?? ""}
                className={field}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="col-span-2">
              <label className={label}>Postal address</label>
              <input
                name="postal_address"
                defaultValue={s.postal_address ?? ""}
                className={field}
              />
            </div>
            <div>
              <label className={label}>Branches</label>
              <input
                name="branches"
                type="number"
                defaultValue={s.branches ?? ""}
                className={field + " tnum"}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Website</label>
              <input name="website" defaultValue={s.website ?? ""} className={field} />
            </div>
            <div>
              <label className={label}>Phone</label>
              <input name="phone" defaultValue={s.phone ?? ""} className={field} />
            </div>
            <div>
              <label className={label}>Email</label>
              <input name="email" defaultValue={s.email ?? ""} className={field} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={label}>Logo URL</label>
              <input name="logo_url" defaultValue={s.logo_url ?? ""} className={field} />
            </div>
            <div>
              <label className={label}>Brand colour</label>
              <input
                name="brand_color"
                defaultValue={s.brand_color ?? ""}
                placeholder="#B08BDD"
                className={field + " font-mono"}
              />
            </div>
          </div>
          <div>
            <label className={label}>About</label>
            <textarea
              name="about"
              rows={3}
              defaultValue={s.about ?? ""}
              className={field}
            />
          </div>
          <div className="flex justify-end">
            <button className={save}>Save profile</button>
          </div>
        </form>
      </Section>

      {/* ── Joining terms ─────────────────────────────────────────────────── */}
      <Section
        title="Joining terms"
        note="From the society's own published terms. The loan multiple is why deposits are locked: they secure your borrowing, so you cannot take them out and keep the loan."
      >
        <form action={updateSaccoTerms} className="space-y-3">
          <input type="hidden" name="id" value={s.id} />
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Registration fee KES</label>
              <input
                name="registration_fee_kes"
                type="number"
                step="1"
                defaultValue={s.registration_fee_kes ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Min share capital KES</label>
              <input
                name="min_share_capital_kes"
                type="number"
                step="1"
                defaultValue={s.min_share_capital_kes ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Min monthly deposit KES</label>
              <input
                name="min_monthly_deposit_kes"
                type="number"
                step="1"
                defaultValue={s.min_monthly_deposit_kes ?? ""}
                className={field + " tnum"}
              />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Loan multiple</label>
              <input
                name="loan_multiple"
                type="number"
                step="0.1"
                placeholder="4"
                defaultValue={s.loan_multiple ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Deposit notice days</label>
              <input
                name="deposit_notice_days"
                type="number"
                placeholder="60"
                defaultValue={s.deposit_notice_days ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Runs a FOSA</label>
              <select
                name="has_fosa"
                defaultValue={s.has_fosa === true ? "yes" : s.has_fosa === false ? "no" : ""}
                className={field}
              >
                <option value="">Not checked</option>
                <option value="yes">Yes</option>
                <option value="no">No</option>
              </select>
            </div>
          </div>
          <div className="flex justify-end">
            <button className={save}>Save terms</button>
          </div>
        </form>
      </Section>

      {/* ── Institution ───────────────────────────────────────────────────── */}
      <Section
        title="The institution"
        note="From the SASRA Sacco Supervision Annual Report, published each October for the prior year. Always set the as-of date: an asset figure with no year attached is a number pretending to be current."
      >
        <form action={updateSaccoInstitution} className="space-y-3">
          <input type="hidden" name="id" value={s.id} />
          <div className="grid grid-cols-3 gap-3">
            <div>
              <label className={label}>Tier</label>
              <select name="tier" defaultValue={s.tier ?? ""} className={field}>
                <option value="">Not set</option>
                <option value="1">Tier 1</option>
                <option value="2">Tier 2</option>
                <option value="3">Tier 3</option>
              </select>
            </div>
            <div>
              <label className={label}>Total assets KES</label>
              <input
                name="total_assets_kes"
                type="number"
                step="1"
                defaultValue={s.total_assets_kes ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Member deposits KES</label>
              <input
                name="deposits_kes"
                type="number"
                step="1"
                defaultValue={s.deposits_kes ?? ""}
                className={field + " tnum"}
              />
            </div>
          </div>
          <div className="grid grid-cols-4 gap-3">
            <div>
              <label className={label}>Members</label>
              <input
                name="members"
                type="number"
                defaultValue={s.members ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Registered</label>
              <input
                name="registered_year"
                type="number"
                placeholder="1976"
                defaultValue={s.registered_year ?? ""}
                className={field + " tnum"}
              />
            </div>
            <div>
              <label className={label}>Figures as of</label>
              <input
                name="financials_as_of"
                type="date"
                defaultValue={s.financials_as_of ?? ""}
                className={field}
              />
            </div>
            <div>
              <label className={label}>Licensed until</label>
              <input
                name="sasra_licensed_until"
                type="date"
                defaultValue={s.sasra_licensed_until ?? ""}
                className={field}
              />
            </div>
          </div>
          <div className="flex justify-end">
            <button className={save}>Save institution</button>
          </div>
        </form>
      </Section>
    </div>
  );
}

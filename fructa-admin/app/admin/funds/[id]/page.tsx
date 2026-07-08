import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase/server";
import { updateFund, setRate } from "../actions";

export const dynamic = "force-dynamic";

const CATS = ["mmf_kes", "mmf_usd", "tbill", "bond", "sacco", "stock"];

export default async function FundDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const db = supabaseAdmin();

  const [{ data: fund }, { data: history }] = await Promise.all([
    db.from("funds").select("*").eq("id", id).maybeSingle(),
    db.from("rate_history").select("as_of,rate,source").eq("fund_id", id).order("as_of", { ascending: false }).limit(20),
  ]);
  if (!fund) notFound();

  return (
    <>
      <div style={{ marginBottom: 14 }}>
        <Link href="/admin/funds" className="text-mute hover:text-gold" style={{ fontSize: 13 }}>← Funds</Link>
        <h2 style={{ fontFamily: "var(--mono)", fontSize: 22, fontWeight: 600, letterSpacing: "-0.5px", marginTop: 6 }}>{fund.name}</h2>
        <p className="num" style={{ fontSize: 11.5, color: "var(--faint)", marginTop: 2 }}>{fund.id}</p>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1.7fr 1fr", gap: 14, alignItems: "start" }}>
        {/* metadata */}
        <form action={updateFund} className="panelc">
          <input type="hidden" name="id" value={fund.id} />
          <div className="ph"><h3>Details</h3><span className="sub">metadata · publishes to snapshot</span></div>
          <div className="pb" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field name="name" label="Name" defaultValue={fund.name} />
            <Field name="manager" label="Manager" defaultValue={fund.manager} />
            <Select name="category" label="Category" defaultValue={fund.category} options={CATS} />
            <Select name="currency" label="Currency" defaultValue={fund.currency} options={["KES", "USD"]} />
            <Field name="min_invest" label="Min invest" type="number" defaultValue={fund.min_invest ?? ""} />
            <Field name="mgmt_fee" label="Mgmt fee %" type="number" defaultValue={fund.mgmt_fee ?? ""} />
            <Field name="aum" label="AUM" defaultValue={fund.aum ?? ""} />
            <Field name="withdraw_note" label="Withdraw note" defaultValue={fund.withdraw_note ?? ""} />
            <Field name="site_url" label="Site URL" defaultValue={fund.site_url ?? ""} />
            <Field name="invest_url" label="Invest URL" defaultValue={fund.invest_url ?? ""} />
            <Field name="contact_url" label="Contact URL" defaultValue={fund.contact_url ?? ""} />
            <Field name="logo_domain" label="Logo domain" defaultValue={fund.logo_domain ?? ""} />
            <Field name="rate_source_url" label="Rate source URL" defaultValue={fund.rate_source_url ?? ""} />
            <Select name="source_type" label="Sourcing" defaultValue={fund.source_type ?? "auto"} options={["auto", "manual"]} />
            <Select name="status" label="Status" defaultValue={fund.status} options={["live", "stale", "hidden"]} />
            <label className="field" style={{ flexDirection: "row", alignItems: "center", gap: 8, alignSelf: "end" }}>
              <input type="checkbox" name="tax_free" defaultChecked={fund.tax_free} style={{ accentColor: "var(--gold)", width: 16, height: 16 }} />
              <span style={{ textTransform: "none", letterSpacing: 0, fontSize: 14, color: "var(--text)", fontWeight: 400 }}>Tax-free</span>
            </label>

            {/* ── Profile & terms (fact-sheet fields; snapshot 0026) ──────── */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
              <span style={{ fontFamily: "var(--mono)", fontSize: 10.5, letterSpacing: "1.4px", textTransform: "uppercase", color: "var(--faint)" }}>
                Profile &amp; terms
              </span>
              <p style={{ fontSize: 11.5, color: "var(--faint)", marginTop: 4 }}>
                Static facts from the fund fact sheet. Custody chain (trustee · custodian · auditor) is manager-level — set on the company.
              </p>
            </div>

            <Field name="inception_date" label="Inception date" type="date" defaultValue={fund.inception_date ?? ""} />
            <label className="field">
              <span>Benchmark</span>
              <select name="benchmark_key" defaultValue={fund.benchmark_key ?? ""} className="select">
                <option value="">None</option>
                <option value="tbill_91">91-day T-bill</option>
                <option value="tbill_182">182-day T-bill</option>
                <option value="tbill_364">364-day T-bill</option>
                <option value="cbr">Central Bank Rate</option>
              </select>
            </label>
            <Field name="expense_ratio" label="Expense ratio % (TER)" type="number" defaultValue={fund.expense_ratio ?? ""} />
            <Field name="redemption_fee" label="Redemption fee %" type="number" defaultValue={fund.redemption_fee ?? ""} />
            <Field name="lock_in_months" label="Lock-in (months)" type="number" defaultValue={fund.lock_in_months ?? ""} />
            <Field name="top_up_min" label="Top-up min" type="number" defaultValue={fund.top_up_min ?? ""} />
            <label className="field" style={{ gridColumn: "1 / -1" }}>
              <span>Objective</span>
              <textarea
                name="objective"
                defaultValue={fund.objective ?? ""}
                rows={2}
                className="input"
                style={{ resize: "vertical" }}
                placeholder="Capital preservation with above-inflation returns and same-day access."
              />
            </label>
          </div>
          <div className="pb" style={{ paddingTop: 0 }}>
            <button className="btn gold">Save changes</button>
          </div>
        </form>

        {/* rate + history */}
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div className="panelc">
            <div className="ph"><h3>Rate today</h3></div>
            <div className="pb">
              <p className="num" style={{ fontSize: 32, fontWeight: 600, color: "var(--gold)", margin: "0 0 12px", letterSpacing: "-1px" }}>
                {fund.current_rate != null ? `${Number(fund.current_rate).toFixed(2)}%` : "—"}
              </p>
              <form action={setRate} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <input type="hidden" name="id" value={fund.id} />
                <input name="rate" type="number" step="0.01" min="0" max="30" placeholder="Override"
                  className="input num-input" style={{ width: 110 }} />
                <button className="btn xs">Set</button>
              </form>
              <p style={{ marginTop: 8, fontSize: 12, color: "var(--faint)" }}>Logged as a manual point and pushed to the app.</p>
            </div>
          </div>

          <div className="panelc">
            <div className="ph"><h3>History</h3><span className="sub">last 20</span></div>
            {(history ?? []).length === 0 ? (
              <div className="pb" style={{ color: "var(--muted)", fontSize: 13.5 }}>No history yet.</div>
            ) : (
              <table className="tbl">
                <tbody>
                  {(history ?? []).map((h: { as_of: string; rate: number; source: string | null }) => (
                    <tr key={h.as_of}>
                      <td style={{ color: "var(--faint)" }}>{h.as_of}</td>
                      <td className="r num">{Number(h.rate).toFixed(2)}%</td>
                      <td className="r" style={{ fontSize: 11, color: "var(--faint)" }}>
                        <span className={"method " + (h.source === "manual" ? "manual" : "auto")}>{h.source ?? "—"}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

function Field({ name, label, defaultValue, type = "text" }: { name: string; label: string; defaultValue: string | number; type?: string }) {
  return (
    <label className="field">
      <span>{label}</span>
      <input name={name} type={type} step={type === "number" ? "any" : undefined} defaultValue={defaultValue}
        className={"input" + (type === "number" ? " num-input" : "")} />
    </label>
  );
}

function Select({ name, label, defaultValue, options }: { name: string; label: string; defaultValue: string; options: string[] }) {
  return (
    <label className="field">
      <span>{label}</span>
      <select name={name} defaultValue={defaultValue} className="select">
        {options.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
    </label>
  );
}

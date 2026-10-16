import { supabaseAdmin } from "@/lib/supabase/server";
import {
  approveReview,
  approveSelected,
  deleteReview,
  rejectOlderThan,
  rejectReview,
  rejectSelected,
  updateReview,
} from "./actions";
import { SelectAll } from "./SelectAll";

export const dynamic = "force-dynamic";

// Held rate changes. Tick rows and approve or reject them together, correct a
// rate or date before deciding, or clear out anything too old to matter.
//
// The change column says what the hold is about. A jump shows the move from
// the fund's last rate. A conflict shows how far apart the two sources were,
// which is a disagreement between sources, not a move.

type Row = {
  id: number;
  fund_id: string;
  source: string;
  old_rate: number | null;
  new_rate: number;
  delta_bps: number | null;
  as_of: string;
  reason: string;
};

const BULK = "bulk";
const STALE_DAYS = 30;

function daysOld(asOf: string): number {
  return Math.floor((Date.now() - Date.parse(asOf + "T00:00:00Z")) / 86_400_000);
}

export default async function ReviewPage() {
  const db = supabaseAdmin();
  const { data } = await db
    .from("rate_review")
    .select("id,fund_id,source,old_rate,new_rate,delta_bps,as_of,reason")
    .eq("status", "pending")
    .order("fund_id", { ascending: true })
    .order("as_of", { ascending: false });
  const rows = (data ?? []) as Row[];

  const ids = [...new Set(rows.map((r) => r.fund_id))];
  const { data: funds } = ids.length
    ? await db.from("funds").select("id,name").in("id", ids)
    : { data: [] as { id: string; name: string }[] };
  const nameById = new Map((funds ?? []).map((f) => [f.id, f.name]));
  const stale = rows.filter((r) => daysOld(r.as_of) > STALE_DAYS).length;

  return (
    <>
      <form id={BULK} />
      <div className="toolrow" style={{ gap: 8 }}>
        <button form={BULK} formAction={approveSelected} className="btn xs"
          style={{ background: "var(--gold-soft)", borderColor: "var(--gold)", color: "var(--gold)" }}>
          Approve selected
        </button>
        <button form={BULK} formAction={rejectSelected} className="btn xs">Reject selected</button>
        {stale > 0 && (
          <form action={rejectOlderThan}>
            <input type="hidden" name="days" value={STALE_DAYS} />
            <button className="btn xs" style={{ color: "var(--warn)" }}>
              Reject {stale} older than {STALE_DAYS} days
            </button>
          </form>
        )}
        <div className="spacer" />
        <span style={{ fontSize: 12, color: "var(--faint)", fontFamily: "var(--mono)" }}>
          {rows.length} pending
        </span>
      </div>

      <div className="panelc">
        <table className="tbl">
          <thead>
            <tr>
              <th style={{ width: 32 }}><SelectAll form={BULK} /></th>
              <th>Fund</th>
              <th>Change</th>
              <th>Source</th>
              <th>Reason</th>
              <th className="r" />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const conflict = r.reason === "conflict";
              const move = r.old_rate == null ? null : r.new_rate - r.old_rate;
              const old = daysOld(r.as_of);
              return (
                <tr key={r.id}>
                  <td>
                    <input type="checkbox" name="ids" value={r.id} form={BULK} className="accent-gold"
                      aria-label={`Select ${nameById.get(r.fund_id) ?? r.fund_id} ${r.as_of}`} />
                  </td>
                  <td>
                    <div className="fn">{nameById.get(r.fund_id) ?? r.fund_id}</div>
                    <div className="fm">
                      {r.as_of}
                      {old > STALE_DAYS && <span className="tick warn" style={{ marginLeft: 8 }}>{old} days old</span>}
                    </div>
                  </td>
                  <td style={{ fontFamily: "var(--mono)" }}>
                    <span style={{ color: "var(--mute)" }}>{r.old_rate ?? "none"}</span>
                    <span style={{ color: "var(--faint)" }}> to </span>
                    <span>{r.new_rate}</span>
                    {conflict ? (
                      <div style={{ color: "var(--gold)", fontSize: 12 }}>
                        sources {Math.abs(r.delta_bps ?? 0)} bps apart
                      </div>
                    ) : move != null && (
                      <span style={{ color: move >= 0 ? "var(--ok)" : "var(--bad)", marginLeft: 8 }}>
                        {move >= 0 ? "+" : ""}{Math.round(move * 100)} bps
                      </span>
                    )}
                  </td>
                  <td><span className="tick mut">{r.source}</span></td>
                  <td><span className="tick mut">{r.reason}</span></td>
                  <td className="r">
                    <div style={{ display: "flex", gap: 6, justifyContent: "flex-end", alignItems: "flex-start" }}>
                      <details>
                        <summary className="btn xs" style={{ listStyle: "none", cursor: "pointer" }}>Edit</summary>
                        <form action={updateReview} style={{ display: "flex", gap: 6, marginTop: 6, alignItems: "flex-end" }}>
                          <input type="hidden" name="id" value={r.id} />
                          <label className="field">
                            <span>Rate</span>
                            <input className="input num-input" type="number" step="0.01" name="new_rate" defaultValue={r.new_rate} style={{ width: 90 }} />
                          </label>
                          <label className="field">
                            <span>Date</span>
                            <input className="input" type="date" name="as_of" defaultValue={r.as_of} />
                          </label>
                          <button className="btn xs">Save</button>
                        </form>
                      </details>
                      <form action={approveReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs"
                          style={{ background: "var(--gold-soft)", borderColor: "var(--gold)", color: "var(--gold)" }}>
                          Approve
                        </button>
                      </form>
                      <form action={rejectReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs" style={{ color: "var(--faint)" }}>Reject</button>
                      </form>
                      <form action={deleteReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs" style={{ color: "var(--bad)" }}>Delete</button>
                      </form>
                    </div>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && (
              <tr>
                <td colSpan={6}>
                  <div className="ph-empty" style={{ border: "none", padding: "28px 0" }}>
                    Nothing waiting. Scraped rates within tolerance apply automatically.
                  </div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

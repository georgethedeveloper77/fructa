import { supabaseAdmin } from "@/lib/supabase/server";
import { approveReview, rejectReview } from "./actions";

export const dynamic = "force-dynamic";

type Row = {
  id: number; fund_id: string; source: string;
  old_rate: number | null; new_rate: number; delta_bps: number | null;
  as_of: string; reason: string;
};

export default async function ReviewPage() {
  const db = supabaseAdmin();
  const { data } = await db
    .from("rate_review")
    .select("id,fund_id,source,old_rate,new_rate,delta_bps,as_of,reason")
    .eq("status", "pending")
    .order("created_at", { ascending: false });
  const rows = (data ?? []) as Row[];

  const ids = [...new Set(rows.map((r) => r.fund_id))];
  const { data: funds } = ids.length
    ? await db.from("funds").select("id,name").in("id", ids)
    : { data: [] as { id: string; name: string }[] };
  const nameById = new Map((funds ?? []).map((f) => [f.id, f.name]));

  return (
    <>
      <div className="toolrow">
        <div className="spacer" />
        <span style={{ fontSize: 12, color: "var(--faint)", fontFamily: "var(--mono)" }}>
          {rows.length} pending
        </span>
      </div>

      <div className="panelc">
        <table className="tbl">
          <thead>
            <tr>
              <th>Fund</th>
              <th>Change</th>
              <th>Source</th>
              <th>Reason</th>
              <th className="r" />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const up = (r.delta_bps ?? 0) >= 0;
              return (
                <tr key={r.id}>
                  <td>
                    <div className="fn">{nameById.get(r.fund_id) ?? r.fund_id}</div>
                    <div className="fm">{r.as_of}</div>
                  </td>
                  <td style={{ fontFamily: "var(--mono)" }}>
                    <span style={{ color: "var(--mute)" }}>
                      {r.old_rate ?? "—"}
                    </span>
                    <span style={{ color: "var(--faint)" }}> → </span>
                    <span>{r.new_rate}</span>
                    {r.delta_bps != null && (
                      <span style={{ color: up ? "var(--ok)" : "var(--bad)", marginLeft: 8 }}>
                        {up ? "+" : ""}{r.delta_bps} bps
                      </span>
                    )}
                  </td>
                  <td><span className="tick mut">{r.source}</span></td>
                  <td><span className="tick mut">{r.reason}</span></td>
                  <td className="r">
                    <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
                      <form action={approveReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button
                          className="btn xs"
                          style={{ background: "var(--gold-soft)", borderColor: "var(--gold)", color: "var(--gold)" }}
                        >
                          Approve
                        </button>
                      </form>
                      <form action={rejectReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs" style={{ color: "var(--faint)" }}>Reject</button>
                      </form>
                    </div>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && (
              <tr>
                <td colSpan={5}>
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

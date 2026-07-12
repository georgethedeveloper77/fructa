import { supabaseAdmin } from "@/lib/supabase/server";
import {
  approveBody,
  rejectBody,
  hideReview,
  unhideReview,
  clearReports,
  blockAuthor,
  unblockAuthor,
} from "./actions";

export const dynamic = "force-dynamic";

type Review = {
  id: string;
  insurer_id: string;
  author_id: string;
  rating: number;
  body: string | null;
  body_status: string;
  reject_reason: string | null;
  claims_holder: boolean;
  hidden: boolean;
  created_at: string;
};
type Report = { review_id: string; reason: string };
type Blocked = { author_id: string; reason: string | null; blocked_at: string };

// Numeric, never a glyph. House rule: no Unicode symbols as icons, and the
// admin has no star SVG in _icons.tsx. "4 / 5" is unambiguous and sorts.
function stars(n: number) {
  return `${n} / 5`;
}

function shortId(id: string) {
  return id.slice(0, 8);
}

export default async function ModerationPage() {
  const db = supabaseAdmin();

  const [{ data: pending }, { data: reported }, { data: reports }, { data: blocked }] =
    await Promise.all([
      db
        .from("insurer_reviews")
        .select(
          "id,insurer_id,author_id,rating,body,body_status,reject_reason,claims_holder,hidden,created_at",
        )
        .eq("body_status", "pending")
        .order("created_at", { ascending: true }),
      db
        .from("insurer_reviews")
        .select(
          "id,insurer_id,author_id,rating,body,body_status,reject_reason,claims_holder,hidden,created_at",
        )
        .eq("hidden", true)
        .order("created_at", { ascending: false }),
      db.from("review_reports").select("review_id,reason"),
      db
        .from("blocked_authors")
        .select("author_id,reason,blocked_at")
        .order("blocked_at", { ascending: false }),
    ]);

  const queue = (pending ?? []) as Review[];
  const hidden = (reported ?? []) as Review[];
  const blocks = (blocked ?? []) as Blocked[];

  const reportsBy = new Map<string, string[]>();
  for (const r of (reports ?? []) as Report[]) {
    reportsBy.set(r.review_id, [...(reportsBy.get(r.review_id) ?? []), r.reason]);
  }

  // Resolve insurer names. Insurers are rows in `funds` where kind='insurance'.
  const ids = [...new Set([...queue, ...hidden].map((r) => r.insurer_id))];
  const { data: funds } = ids.length
    ? await db.from("funds").select("id,name").in("id", ids)
    : { data: [] as { id: string; name: string }[] };
  const nameById = new Map((funds ?? []).map((f) => [f.id, f.name]));

  return (
    <>
      <div className="toolrow">
        <div className="spacer" />
        <span style={{ fontSize: 12, color: "var(--faint)", fontFamily: "var(--mono)" }}>
          {queue.length} pending &middot; {hidden.length} hidden &middot; {blocks.length} blocked
        </span>
      </div>

      <p
        style={{
          fontSize: 12,
          color: "var(--mute)",
          lineHeight: 1.7,
          margin: "0 0 18px",
          maxWidth: 760,
        }}
      >
        Star ratings publish the moment they are written and never reach this page. Only the written
        body waits here. Nothing you do below changes a rating.
      </p>

      {/* ── pending bodies ─────────────────────────────────────────────── */}
      <div className="panelc" style={{ marginBottom: 22 }}>
        <table className="tbl">
          <thead>
            <tr>
              <th>Insurer</th>
              <th>Rating</th>
              <th>Body</th>
              <th className="r" />
            </tr>
          </thead>
          <tbody>
            {queue.map((r) => (
              <tr key={r.id}>
                <td>
                  <div className="fn">{nameById.get(r.insurer_id) ?? r.insurer_id}</div>
                  <div className="fm">
                    {r.created_at.slice(0, 10)}
                    {r.claims_holder ? " \u00b7 says they hold this" : ""}
                  </div>
                </td>
                <td style={{ fontFamily: "var(--mono)", color: "var(--gold)", whiteSpace: "nowrap" }}>
                  {stars(r.rating)}
                </td>
                <td style={{ maxWidth: 420 }}>
                  <div style={{ fontSize: 12.5, color: "var(--mute)", lineHeight: 1.6 }}>
                    {r.body}
                  </div>
                </td>
                <td className="r">
                  <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
                    <form action={approveBody}>
                      <input type="hidden" name="id" value={r.id} />
                      <button
                        className="btn xs"
                        style={{
                          background: "var(--gold-soft)",
                          borderColor: "var(--gold)",
                          color: "var(--gold)",
                        }}
                      >
                        Publish body
                      </button>
                    </form>
                    <form action={rejectBody}>
                      <input type="hidden" name="id" value={r.id} />
                      <button className="btn xs" style={{ color: "var(--faint)" }}>
                        Reject
                      </button>
                    </form>
                    <form action={blockAuthor}>
                      <input type="hidden" name="author_id" value={r.author_id} />
                      <button className="btn xs" style={{ color: "var(--bad)" }}>
                        Block
                      </button>
                    </form>
                  </div>
                </td>
              </tr>
            ))}
            {queue.length === 0 && (
              <tr>
                <td colSpan={4}>
                  <div className="ph-empty" style={{ border: "none", padding: "28px 0" }}>
                    Nothing waiting. Ratings are already live.
                  </div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* ── hidden / reported ──────────────────────────────────────────── */}
      <h2
        style={{
          fontSize: 12,
          fontWeight: 600,
          letterSpacing: "0.06em",
          textTransform: "uppercase",
          color: "var(--faint)",
          margin: "0 0 10px",
        }}
      >
        Hidden and reported
      </h2>
      <div className="panelc" style={{ marginBottom: 22 }}>
        <table className="tbl">
          <thead>
            <tr>
              <th>Insurer</th>
              <th>Reports</th>
              <th>Body</th>
              <th className="r" />
            </tr>
          </thead>
          <tbody>
            {hidden.map((r) => {
              const rs = reportsBy.get(r.id) ?? [];
              return (
                <tr key={r.id}>
                  <td>
                    <div className="fn">{nameById.get(r.insurer_id) ?? r.insurer_id}</div>
                    <div className="fm" style={{ fontFamily: "var(--mono)" }}>
                      {stars(r.rating)}
                    </div>
                  </td>
                  <td>
                    {rs.length === 0 ? (
                      <span className="tick mut">admin</span>
                    ) : (
                      <span className="tick mut">
                        {rs.length}: {[...new Set(rs)].join(", ")}
                      </span>
                    )}
                  </td>
                  <td style={{ maxWidth: 380 }}>
                    <div style={{ fontSize: 12.5, color: "var(--mute)", lineHeight: 1.6 }}>
                      {r.body ?? "Rating only"}
                    </div>
                  </td>
                  <td className="r">
                    <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
                      <form action={clearReports}>
                        <input type="hidden" name="id" value={r.id} />
                        <button className="btn xs" style={{ color: "var(--faint)" }}>
                          Clear and restore
                        </button>
                      </form>
                      <form action={blockAuthor}>
                        <input type="hidden" name="author_id" value={r.author_id} />
                        <button className="btn xs" style={{ color: "var(--bad)" }}>
                          Block author
                        </button>
                      </form>
                    </div>
                  </td>
                </tr>
              );
            })}
            {hidden.length === 0 && (
              <tr>
                <td colSpan={4}>
                  <div className="ph-empty" style={{ border: "none", padding: "28px 0" }}>
                    Nothing hidden. Three reports auto-hide a review.
                  </div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* ── blocked authors ───────────────────────────────────────────── */}
      <h2
        style={{
          fontSize: 12,
          fontWeight: 600,
          letterSpacing: "0.06em",
          textTransform: "uppercase",
          color: "var(--faint)",
          margin: "0 0 10px",
        }}
      >
        Blocked devices
      </h2>
      <div className="panelc">
        <table className="tbl">
          <thead>
            <tr>
              <th>Device</th>
              <th>Reason</th>
              <th>Blocked</th>
              <th className="r" />
            </tr>
          </thead>
          <tbody>
            {blocks.map((b) => (
              <tr key={b.author_id}>
                <td style={{ fontFamily: "var(--mono)", fontSize: 12 }}>
                  {shortId(b.author_id)}
                </td>
                <td>
                  <span className="tick mut">{b.reason ?? "Not stated"}</span>
                </td>
                <td style={{ fontFamily: "var(--mono)", fontSize: 12, color: "var(--faint)" }}>
                  {b.blocked_at.slice(0, 10)}
                </td>
                <td className="r">
                  <form action={unblockAuthor}>
                    <input type="hidden" name="author_id" value={b.author_id} />
                    <button className="btn xs" style={{ color: "var(--faint)" }}>
                      Unblock
                    </button>
                  </form>
                </td>
              </tr>
            ))}
            {blocks.length === 0 && (
              <tr>
                <td colSpan={4}>
                  <div className="ph-empty" style={{ border: "none", padding: "28px 0" }}>
                    Nobody blocked. A blocked device can still read, it just cannot write.
                  </div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <p
        style={{
          fontSize: 11,
          color: "var(--faint)",
          lineHeight: 1.8,
          margin: "22px 0 0",
          maxWidth: 760,
        }}
      >
        Identity is an anonymous Supabase device UUID. There is no name, email or phone behind these
        rows, which is exactly why blocking a device is the strongest lever available and why it is
        enough for Apple Guideline 1.2. A blocked author&apos;s existing reviews leave the public view
        the moment the block lands, because the view filters on blocked_authors rather than on a flag
        copied onto each row.
      </p>
    </>
  );
}

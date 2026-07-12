import { supabaseAdmin } from "@/lib/supabase/server";
import {
  approveBody,
  rejectBody,
  hideReview,
  unhideReview,
  blockAuthor,
  unblockAuthor,
  dismissReports,
} from "./actions";

export const dynamic = "force-dynamic";

type Row = {
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

type Blocked = { author_id: string; reason: string | null; created_at: string };

function when(iso: string) {
  const d = new Date(iso);
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 60) return `${mins}m ago`;
  if (mins < 1440) return `${Math.round(mins / 60)}h ago`;
  return `${Math.round(mins / 1440)}d ago`;
}

export default async function ModerationPage() {
  const db = supabaseAdmin();

  const [{ data: pending }, { data: reported }, { data: blocked }, { data: names }] =
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
      db
        .from("blocked_authors")
        .select("author_id,reason,created_at")
        .order("created_at", { ascending: false }),
      db.from("funds").select("id,name").eq("kind", "insurance"),
    ]);

  const queue = (pending ?? []) as Row[];
  const hidden = (reported ?? []) as Row[];
  const blocks = (blocked ?? []) as Blocked[];
  const nameOf = new Map(
    ((names ?? []) as { id: string; name: string }[]).map((n) => [n.id, n.name]),
  );

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Moderation</h1>
        <p className="mt-1 text-sm text-mute">
          Ratings publish the moment they are written. Only the words wait here.
          Nothing on this page can change a score, so the histogram in the app
          stays honest even when this queue is backed up.
        </p>
      </header>

      <div className="mb-6 grid grid-cols-3 gap-3">
        <Kpi label="Awaiting review" value={queue.length} tone={queue.length > 0 ? "gold" : undefined} />
        <Kpi label="Hidden or reported" value={hidden.length} tone={hidden.length > 0 ? "bad" : undefined} />
        <Kpi label="Blocked devices" value={blocks.length} />
      </div>

      {/* ── pending bodies ────────────────────────────────────────────── */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold tracking-tight">Words awaiting a human</h2>

        {queue.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-8 text-center text-xs text-mute">
            Nothing queued. Every submitted review has been read.
          </p>
        )}

        <div className="space-y-3">
          {queue.map((r) => (
            <article key={r.id} className="rounded-xl border border-line bg-panel p-4">
              <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                <span className="font-medium text-ink">
                  {nameOf.get(r.insurer_id) ?? r.insurer_id}
                </span>
                <Stars n={r.rating} />
                {r.claims_holder && (
                  <span className="rounded border border-line bg-panel2 px-1.5 py-0.5 text-[10px] text-mute">
                    says they hold this
                  </span>
                )}
                <span className="text-faint">{when(r.created_at)}</span>
                <span className="ml-auto font-mono text-[10px] text-faint">
                  {r.author_id.slice(0, 8)}
                </span>
              </div>

              <p className="whitespace-pre-wrap rounded-lg border border-line bg-panel2 p-3 text-sm leading-relaxed text-ink">
                {r.body}
              </p>

              <div className="mt-3 flex flex-wrap items-end gap-2">
                <form action={approveBody}>
                  <input type="hidden" name="id" value={r.id} />
                  <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">
                    Publish
                  </button>
                </form>

                <form action={rejectBody} className="flex items-end gap-2">
                  <input type="hidden" name="id" value={r.id} />
                  <input
                    name="reason"
                    placeholder="Reason shown to the author"
                    className="w-64 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60"
                  />
                  <button className="rounded-md border border-bad/40 px-3 py-1.5 text-sm text-bad hover:bg-bad/10">
                    Refuse words
                  </button>
                </form>

                <form action={blockAuthor} className="ml-auto">
                  <input type="hidden" name="author_id" value={r.author_id} />
                  <button className="rounded-md border border-bad/40 px-3 py-1.5 text-xs text-bad hover:bg-bad/10">
                    Block device
                  </button>
                </form>
              </div>

              <p className="mt-2 text-[11px] text-faint">
                Refusing the words keeps the {r.rating}-star rating counted. That is
                deliberate: dropping the row would quietly shrink the sample and
                change the average.
              </p>
            </article>
          ))}
        </div>
      </section>

      {/* ── hidden / reported ─────────────────────────────────────────── */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold tracking-tight">Hidden or reported</h2>
        <p className="mb-3 text-xs text-mute">
          Three separate reporters auto-hides a review. That is a trigger for a
          human to look, not a verdict: a coordinated group can bury a true
          review, so reinstating is a normal outcome here, not an admission of
          error.
        </p>

        {hidden.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-8 text-center text-xs text-mute">
            Nothing hidden.
          </p>
        )}

        <div className="space-y-3">
          {hidden.map((r) => (
            <article key={r.id} className="rounded-xl border border-bad/30 bg-panel p-4">
              <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                <span className="font-medium text-ink">
                  {nameOf.get(r.insurer_id) ?? r.insurer_id}
                </span>
                <Stars n={r.rating} />
                <span className="text-faint">{when(r.created_at)}</span>
                <span className="ml-auto font-mono text-[10px] text-faint">
                  {r.author_id.slice(0, 8)}
                </span>
              </div>

              {r.body && (
                <p className="whitespace-pre-wrap rounded-lg border border-line bg-panel2 p-3 text-sm leading-relaxed text-mute">
                  {r.body}
                </p>
              )}

              <div className="mt-3 flex flex-wrap items-end gap-2">
                <form action={dismissReports}>
                  <input type="hidden" name="id" value={r.id} />
                  <button className="rounded-md border border-line px-3 py-1.5 text-sm text-mute hover:bg-panel2">
                    Reinstate, clear reports
                  </button>
                </form>

                <form action={unhideReview}>
                  <input type="hidden" name="id" value={r.id} />
                  <button className="rounded-md border border-line px-3 py-1.5 text-sm text-mute hover:bg-panel2">
                    Unhide only
                  </button>
                </form>

                <form action={hideReview} className="flex items-end gap-2">
                  <input type="hidden" name="id" value={r.id} />
                  <input
                    name="reason"
                    placeholder="Reason"
                    className="w-48 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60"
                  />
                  <button className="rounded-md border border-bad/40 px-3 py-1.5 text-sm text-bad hover:bg-bad/10">
                    Confirm takedown
                  </button>
                </form>

                <form action={blockAuthor} className="ml-auto">
                  <input type="hidden" name="author_id" value={r.author_id} />
                  <button className="rounded-md border border-bad/40 px-3 py-1.5 text-xs text-bad hover:bg-bad/10">
                    Block device
                  </button>
                </form>
              </div>
            </article>
          ))}
        </div>
      </section>

      {/* ── blocked ───────────────────────────────────────────────────── */}
      <section>
        <h2 className="mb-3 text-sm font-semibold tracking-tight">Blocked devices</h2>
        <p className="mb-3 text-xs text-mute">
          Anonymous auth means these are devices, not people. A determined abuser
          reinstalls and returns. This is a speed bump, not a wall, and it should
          not be relied on as one.
        </p>

        {blocks.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-8 text-center text-xs text-mute">
            No blocked devices.
          </p>
        )}

        <div className="space-y-2">
          {blocks.map((b) => (
            <form
              key={b.author_id}
              action={unblockAuthor}
              className="flex items-center gap-3 rounded-lg border border-line bg-panel2 px-4 py-2.5"
            >
              <input type="hidden" name="author_id" value={b.author_id} />
              <span className="font-mono text-xs text-ink">
                {b.author_id.slice(0, 12)}
              </span>
              <span className="text-xs text-mute">{b.reason}</span>
              <span className="text-[11px] text-faint">{when(b.created_at)}</span>
              <button className="ml-auto rounded-md border border-line px-3 py-1 text-xs text-mute hover:bg-panel">
                Unblock
              </button>
            </form>
          ))}
        </div>
      </section>
    </div>
  );
}

function Kpi({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone?: "gold" | "bad";
}) {
  const color =
    tone === "gold" ? "text-gold" : tone === "bad" ? "text-bad" : "text-ink";
  return (
    <div className="rounded-xl border border-line bg-panel p-4">
      <div className="text-[11px] uppercase tracking-wider text-faint">{label}</div>
      <div className={`mt-1.5 font-mono text-2xl font-semibold ${color}`}>
        {value}
      </div>
    </div>
  );
}

/** Filled and empty stars as inline SVG. No Unicode glyphs anywhere in admin. */
function Stars({ n }: { n: number }) {
  return (
    <span className="inline-flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((s) => (
        <svg
          key={s}
          width="11"
          height="11"
          viewBox="0 0 24 24"
          fill={s <= n ? "currentColor" : "none"}
          stroke="currentColor"
          strokeWidth="1.8"
          className={s <= n ? "text-gold" : "text-faint"}
        >
          <path d="M12 2.5l2.9 5.9 6.6.9-4.8 4.6 1.2 6.5L12 17.4l-5.9 3 1.2-6.5L2.5 9.3l6.6-.9z" />
        </svg>
      ))}
    </span>
  );
}

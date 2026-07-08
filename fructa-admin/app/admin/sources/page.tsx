import { supabaseAdmin } from "@/lib/supabase/server";
import { setRate, setSourceType } from "../funds/actions";
import { IconExternal } from "../_icons";

export const dynamic = "force-dynamic";

type Src = {
  id: string; name: string; manager: string; category: string;
  current_rate: number | null; updated_at: string; status: string;
  source_type: "auto" | "manual"; rate_source_url: string | null; site_url: string | null;
};

const CATS: Record<string, string> = {
  mmf_kes: "MMF · KES", mmf_usd: "MMF · USD", tbill: "T-Bills",
  bond: "Bonds", sacco: "SACCO", stock: "NSE",
};
const STALE_DAYS = 7;

function daysSince(iso: string): number {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000);
}
function ago(iso: string): string {
  const d = daysSince(iso);
  if (d <= 0) return "today";
  return `${d}d ago`;
}

export default async function SourcesPage() {
  const db = supabaseAdmin();
  const { data, error } = await db
    .from("funds")
    .select("id,name,manager,category,current_rate,updated_at,status,source_type,rate_source_url,site_url")
    .neq("status", "hidden");

  const rows = (data ?? []) as Src[];
  const isStale = (r: Src) => r.status === "stale" || daysSince(r.updated_at) >= STALE_DAYS;

  // Manual first, then stale, then most-recently-updated last.
  rows.sort((a, b) => {
    if (a.source_type !== b.source_type) return a.source_type === "manual" ? -1 : 1;
    return new Date(a.updated_at).getTime() - new Date(b.updated_at).getTime();
  });

  const attention = rows.filter((r) => r.source_type === "manual" || isStale(r)).length;

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-5">
        <h1 className="text-2xl font-semibold tracking-tight">Sources</h1>
        <p className="mt-1 text-sm text-mute">
          Where each rate comes from. Open the official page, read the number, update it here.
          {attention > 0 && <> <span className="text-warn">{attention} need a look.</span></>}
        </p>
      </header>

      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">
          {error.message.includes("source_type") ? "Run migration 0006 first — the source columns don't exist yet." : error.message}
        </p>
      )}

      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line text-left text-[11px] uppercase tracking-wider text-faint">
              <th className="px-4 py-3 font-medium">Source</th>
              <th className="px-3 py-3 font-medium">Type</th>
              <th className="px-3 py-3 font-medium">Value</th>
              <th className="px-3 py-3 font-medium">Official page</th>
              <th className="px-3 py-3 font-medium">Update</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const stale = isStale(r);
              const url = r.rate_source_url ?? r.site_url;
              return (
                <tr key={r.id} className="border-b border-line/60 last:border-0 hover:bg-panel2/40">
                  <td className="px-4 py-3">
                    <div className="font-medium text-ink">{r.name}</div>
                    <div className="text-xs text-faint">{CATS[r.category] ?? r.category} · {r.manager}</div>
                  </td>
                  <td className="px-3 py-3">
                    <form action={setSourceType}>
                      <input type="hidden" name="id" value={r.id} />
                      <input type="hidden" name="type" value={r.source_type === "manual" ? "auto" : "manual"} />
                      <button
                        title="Toggle auto / manual"
                        className={
                          "rounded-md border px-2 py-0.5 text-xs " +
                          (r.source_type === "manual"
                            ? "border-warn/50 bg-warn/10 text-warn"
                            : "border-line text-mute hover:text-ink")
                        }
                      >
                        {r.source_type}
                      </button>
                    </form>
                  </td>
                  <td className="px-3 py-3">
                    <div className="tnum text-ink">
                      {r.current_rate != null ? `${Number(r.current_rate).toFixed(2)}%` : "—"}
                    </div>
                    <div className={"text-xs " + (stale ? "text-bad" : "text-faint")}>{ago(r.updated_at)}</div>
                  </td>
                  <td className="px-3 py-3">
                    {url ? (
                      <a href={url} target="_blank" rel="noreferrer"
                         className="inline-flex items-center gap-1 text-mute hover:text-gold">Open <IconExternal size={12} /></a>
                    ) : (
                      <span className="text-faint">—</span>
                    )}
                  </td>
                  <td className="px-3 py-3">
                    <form action={setRate} className="flex items-center gap-1.5">
                      <input type="hidden" name="id" value={r.id} />
                      <input name="rate" type="number" step="0.01" min="0" max="30" placeholder="—"
                        className="tnum w-16 rounded-md border border-line bg-panel2 px-2 py-1 text-ink outline-none focus:border-gold/60" />
                      <button className="rounded-md border border-line px-2 py-1 text-xs text-mute hover:border-gold/60 hover:text-gold">Set</button>
                    </form>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && !error && (
              <tr><td colSpan={5} className="px-4 py-10 text-center text-sm text-mute">No sources yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <p className="mt-3 text-xs text-faint">
        Manual sources sort to the top. A value older than {STALE_DAYS} days is flagged red — that&apos;s your weekly to-do.
      </p>
    </div>
  );
}

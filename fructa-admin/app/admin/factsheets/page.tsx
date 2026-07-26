import { supabaseAdmin } from "@/lib/supabase/server";
import { rejectFactsheet } from "./actions";
import { ExtractForm } from "./ExtractForm";
import { StageForm } from "./StageForm";
import { ApplyButton } from "./ApplyButton";

export const dynamic = "force-dynamic";

type Figure = { value?: unknown; caption?: string; reason?: string };

type QueueRow = {
  id: number;
  fund_id: string | null;
  fund_name: string | null;
  currency: string | null;
  current_basis: string | null;
  current_rate: number | null;
  current_net_of: string | null;
  source_label: string;
  as_of: string;
  status: string;
  confidence: number | null;
  proposed_basis: string | null;
  fund_has_newer_rate: boolean;
  fund_is_manual: boolean;
};

const fig = (f: Figure | undefined) =>
  f && f.value !== undefined && f.value !== null ? String(f.value) : null;

export default async function FactsheetsPage() {
  const db = supabaseAdmin();

  const [{ data: queue }, { data: payloads }, { data: funds }] = await Promise.all([
    db.from("factsheet_import_queue")
      .select("*")
      .eq("status", "pending")
      .order("created_at", { ascending: false }),
    db.from("factsheet_imports")
      .select("id,payload")
      .eq("status", "pending"),
    db.from("funds")
      .select("id,name,currency")
      .eq("kind", "fund")
      .order("name"),
  ]);

  const rows = (queue ?? []) as QueueRow[];
  const byId = new Map(
    (payloads ?? []).map((p) => [p.id as number, p.payload as Record<string, Figure & Figure[]>]),
  );

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Fact sheets</h1>
        <p className="mt-1 text-sm text-mute">
          Extracted sheets waiting on a decision. Nothing here has touched a fund. Every figure
          shows the caption printed beside it on the PDF, because approving{" "}
          <span className="tnum text-ink">4.74%</span> is a guess and approving{" "}
          <span className="tnum text-ink">4.74%</span> captioned{" "}
          <span className="text-ink">Q1 2026</span> is a decision.
        </p>
      </header>

      {/* Extraction is the front door; pasting a payload stays available for a
          sheet the model cannot read, and for testing the gate by hand. */}
      <div className="flex flex-wrap items-center gap-2">
        <ExtractForm funds={funds ?? []} />
        <StageForm funds={funds ?? []} />
      </div>

      <div className="flex items-center gap-2">
        <h2 className="text-sm font-medium text-ink">Queue</h2>
        <span className="tnum text-xs text-faint">{rows.length} pending</span>
      </div>

      {rows.length === 0 ? (
        <div className="rounded-xl border border-line bg-panel p-8 text-center text-sm text-mute">
          Nothing waiting.
        </div>
      ) : (
        <div className="space-y-4">
          {rows.map((r) => {
            const p = byId.get(r.id) ?? {};
            const terms = (p.terms ?? {}) as unknown as Record<string, Figure>;
            const periods = (Array.isArray(p.periods) ? p.periods : []) as unknown as Record<string, unknown>[];
            const rates = (Array.isArray(p.rates) ? p.rates : []) as unknown as Record<string, unknown>[];
            const excluded = (Array.isArray(p.excluded) ? p.excluded : []) as unknown as Figure[];
            const basisChanges =
              r.proposed_basis != null && r.proposed_basis !== r.current_basis;

            return (
              <div key={r.id} className="rounded-xl border border-line bg-panel">
                {/* header */}
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-line px-5 py-3">
                  <span className="font-medium text-ink">
                    {r.fund_name ?? "Unassigned"}
                  </span>
                  <span className="text-xs text-faint">{r.source_label}</span>
                  <span className="tnum text-xs text-faint">sheet dated {r.as_of}</span>
                  {r.confidence != null && (
                    <span className="tnum text-xs text-faint">
                      confidence {(r.confidence * 100).toFixed(0)}%
                    </span>
                  )}
                </div>

                {/* the two warnings a reviewer must not have to go looking for */}
                {(r.fund_is_manual || r.fund_has_newer_rate) && (
                  <div className="space-y-2 border-b border-line px-5 py-3">
                    {r.fund_is_manual && (
                      <div className="rounded-md border border-bad/40 bg-bad/10 px-3 py-2 text-xs text-bad">
                        This fund is set to manual sourcing. Applying is blocked. Somebody took it
                        off the pipeline deliberately.
                      </div>
                    )}
                    {r.fund_has_newer_rate && (
                      <div className="rounded-md border border-warn/40 bg-warn/5 px-3 py-2 text-xs text-warn">
                        The fund already holds a rate newer than {r.as_of}. Rate points will be
                        skipped; terms will still apply. A sheet is only authoritative as at its
                        own date.
                      </div>
                    )}
                  </div>
                )}

                {/* basis: the highest-consequence edit, so it gets its own row */}
                {basisChanges && (
                  <div className="border-b border-line px-5 py-3">
                    <div className="text-[10px] uppercase tracking-wider text-faint">
                      Changes what kind of number this fund quotes
                    </div>
                    <div className="mt-1 flex items-center gap-2 text-sm">
                      <span className="tnum text-mute">{r.current_basis ?? "unset"}</span>
                      <span className="text-faint">to</span>
                      <span className="tnum font-semibold text-gold">{r.proposed_basis}</span>
                    </div>
                    {(p.basis as Figure)?.caption && (
                      <div className="mt-1 text-xs text-faint">
                        sheet says: {(p.basis as Figure).caption}
                      </div>
                    )}
                    {(p.basis as Figure)?.reason && (
                      <div className="text-xs text-faint">
                        because: {(p.basis as Figure).reason}
                      </div>
                    )}
                  </div>
                )}

                {/* proposed vs current */}
                <div className="grid gap-x-6 gap-y-2 px-5 py-3 sm:grid-cols-2">
                  {(p.net_of as Figure) && (
                    <Field
                      label="Quoted net of"
                      now={r.current_net_of ?? "unset"}
                      next={fig(p.net_of as Figure)}
                      caption={(p.net_of as Figure).caption}
                    />
                  )}
                  {Object.entries(terms).map(([k, f]) => (
                    <Field
                      key={k}
                      label={k.replace(/_/g, " ")}
                      next={fig(f)}
                      caption={f?.caption}
                    />
                  ))}
                </div>

                {/* series */}
                {(periods.length > 0 || rates.length > 0) && (
                  <div className="border-t border-line px-5 py-3">
                    {periods.length > 0 && (
                      <div className="mb-2">
                        <div className="text-[10px] uppercase tracking-wider text-faint">
                          {periods.length} period return{periods.length === 1 ? "" : "s"}
                        </div>
                        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1">
                          {periods.map((x, i) => {
                            const v = Number(x.net_pct);
                            return (
                              <span key={i} className="tnum text-xs">
                                <span className="text-faint">{String(x.period_end)} </span>
                                <span className={v < 0 ? "text-bad" : "text-ink"}>
                                  {v >= 0 ? "+" : ""}{v}%
                                </span>
                                <span className="text-faint"> {String(x.period)}</span>
                              </span>
                            );
                          })}
                        </div>
                      </div>
                    )}
                    {rates.length > 0 && (
                      <div>
                        <div className="text-[10px] uppercase tracking-wider text-faint">
                          {rates.length} rate point{rates.length === 1 ? "" : "s"}
                        </div>
                        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1">
                          {rates.map((x, i) => (
                            <span key={i} className="tnum text-xs">
                              <span className="text-faint">{String(x.as_of)} </span>
                              <span className="text-ink">{String(x.rate)}%</span>
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {/* what the extractor chose NOT to use */}
                <div className="border-t border-line px-5 py-3">
                  <div className="text-[10px] uppercase tracking-wider text-faint">
                    Seen on the sheet and not used
                  </div>
                  {excluded.length === 0 ? (
                    <div className="mt-1 text-xs text-warn">
                      Nothing excluded. Every sheet reviewed so far printed at least one figure
                      that is not a return, so an empty list is worth a second look at the PDF.
                    </div>
                  ) : (
                    <ul className="mt-1 space-y-1">
                      {excluded.map((x, i) => (
                        <li key={i} className="text-xs text-faint">
                          <span className="tnum text-mute">{String(x.value)}</span>
                          {x.caption && <span> captioned &ldquo;{x.caption}&rdquo;</span>}
                          {x.reason && <span>, {x.reason}</span>}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>

                {/* decide */}
                <div className="flex items-center justify-end gap-2 border-t border-line px-5 py-3">
                  <form action={rejectFactsheet}>
                    <input type="hidden" name="id" value={r.id} />
                    <button className="rounded-md border border-line px-3 py-1.5 text-xs text-faint hover:text-mute">
                      Reject
                    </button>
                  </form>
                  <ApplyButton id={r.id} disabled={r.fund_is_manual || !r.fund_id} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function Field({
  label, now, next, caption,
}: { label: string; now?: string; next: string | null; caption?: string }) {
  if (next === null) return null;
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className="flex items-baseline gap-2 text-sm">
        {now !== undefined && now !== next && (
          <>
            <span className="tnum text-mute line-through decoration-faint/40">{now}</span>
            <span className="text-faint">to</span>
          </>
        )}
        <span className="tnum text-ink">{next}</span>
      </div>
      {caption && <div className="text-xs text-faint">sheet says: {caption}</div>}
    </div>
  );
}

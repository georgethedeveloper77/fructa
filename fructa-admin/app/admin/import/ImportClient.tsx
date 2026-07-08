"use client";

import { useMemo, useState, useTransition } from "react";
import {
  importRates, importCmaComposition, importReturns,
  type ImportResult, type CmaImportResult, type ReturnsImportResult,
} from "./actions";

function today() {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}
function lastQuarterEnd() {
  const d = new Date();
  const q = Math.floor(d.getMonth() / 3);
  const end = new Date(d.getFullYear(), q * 3, 0);
  return new Date(end.getTime() - end.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}
// Fact sheets are published for a completed month, so default the statement
// month to the end of last month.
function lastMonthEnd() {
  const d = new Date();
  const end = new Date(d.getFullYear(), d.getMonth(), 0);
  return new Date(end.getTime() - end.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}
      strokeLinecap="round" strokeLinejoin="round"
      className={"transition-transform " + (open ? "rotate-90" : "")}><path d="M9 6l6 6-6 6" /></svg>
  );
}
function ArrowRight() {
  return (
    <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}
      strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg>
  );
}
function Stat({ label, value, tone }: { label: string; value: string; tone?: "ok" | "warn" | "faint" }) {
  const c = tone === "ok" ? "text-live" : tone === "warn" ? "text-warn" : tone === "faint" ? "text-faint" : "text-ink";
  return (
    <div className="rounded-lg border border-line bg-panel2 px-3 py-2">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={"tnum text-lg font-semibold " + c}>{value}</div>
    </div>
  );
}
type Tone = "ok" | "warn" | "bad";
function Preflight({ msg, tone }: { msg: string; tone: Tone }) {
  const s = tone === "ok" ? "border-live/30 bg-live/5 text-live"
    : tone === "warn" ? "border-warn/40 bg-warn/5 text-warn"
    : "border-bad/40 bg-bad/10 text-bad";
  return <div className={"rounded-md border px-3 py-2 text-xs " + s}>{msg}</div>;
}
const inputCls = "rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const fileCls = "text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute";

export function ImportClient() {
  const [tab, setTab] = useState<"rates" | "cma" | "returns">("rates");
  const label = (t: "rates" | "cma" | "returns") =>
    t === "rates" ? "Weekly rates" : t === "cma" ? "CMA report" : "Fund returns";
  return (
    <div className="space-y-5">
      <div className="inline-flex items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
        {(["rates", "cma", "returns"] as const).map((t) => (
          <button key={t} onClick={() => setTab(t)}
            className={"rounded-md px-3 py-1.5 text-sm " + (tab === t ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>
            {label(t)}
          </button>
        ))}
      </div>
      {tab === "rates" ? <RatesTab /> : tab === "cma" ? <CmaTab /> : <ReturnsTab />}
    </div>
  );
}

// ── Weekly rates ───────────────────────────────────────────────────────────
function RatesTab() {
  const [result, setResult] = useState<ImportResult | null>(null);
  const [showMatched, setShowMatched] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileName, setFileName] = useState("");
  const [pending, start] = useTransition();
  const submit = (fd: FormData) => start(async () => setResult(await importRates(fd)));

  // live count of parseable name,rate rows (mirrors the server parser)
  const parsed = useMemo(() => {
    let n = 0;
    for (const raw of paste.split(/\r?\n/)) {
      const cols = raw.trim().split(/[,\t]/);
      if (cols.length < 2) continue;
      const rate = Number(String(cols[1]).replace(/[^0-9.]/g, ""));
      if (cols[0].trim() && Number.isFinite(rate) && rate > 0) n++;
    }
    return n;
  }, [paste]);

  const total = result ? result.matched + result.unmatched.length : 0;
  const rate = total ? Math.round((result!.matched / total) * 100) : 0;

  return (
    <div className="space-y-5">
      <form action={submit} className="space-y-4 rounded-xl border border-line bg-panel p-5">
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Rate date</span>
            <input type="date" name="as_of" defaultValue={today()} className={inputCls} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">CSV file (optional)</span>
            <input type="file" name="file" accept=".csv,.tsv,text/csv"
              onChange={(e) => setFileName(e.target.files?.[0]?.name ?? "")} className={fileCls} />
          </label>
        </div>
        {fileName && <p className="text-xs text-mute">Loaded <code className="text-gold">{fileName}</code> — file takes precedence over pasted rows.</p>}
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">…or paste rows</span>
          <textarea name="pasted" rows={8} value={paste} onChange={(e) => setPaste(e.target.value)}
            placeholder={"Nabo Africa Money Market Fund,12.77\nEtica Money Market Fund,11.28\nGulfCap Money Market Fund,10.11"}
            className={"w-full font-mono " + inputCls} />
        </label>
        {!fileName && paste.trim() && (
          <Preflight tone={parsed ? "ok" : "warn"}
            msg={parsed ? `${parsed} rate row${parsed === 1 ? "" : "s"} detected.` : "No parseable rows yet — each line needs name,rate (comma or tab)."} />
        )}
        <div className="flex items-center gap-3">
          <button disabled={pending}
            className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:opacity-50">
            {pending ? "Importing…" : "Import rates"}
          </button>
          <span className="text-xs text-faint">Columns: <code>name,rate</code>. Names matched loosely — GulfCap→GCIB, Absa MMF→ABSA Shilling, currency-aware.</span>
        </div>
      </form>

      {result && (
        <div className="rounded-xl border border-line bg-panel p-5">
          {result.error ? <p className="text-sm text-bad">{result.error}</p> : (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3">
                <Stat label="Written" value={String(result.matched)} tone="ok" />
                <Stat label="Unmatched" value={String(result.unmatched.length)} tone={result.unmatched.length ? "warn" : "faint"} />
                <Stat label="Match rate" value={`${rate}%`} tone={rate >= 90 ? "ok" : rate >= 60 ? "warn" : "faint"} />
              </div>
              <p className="text-xs text-faint">for {result.asOf} · source <code>admin-import</code></p>

              {result.matches.length > 0 && (
                <div>
                  <button onClick={() => setShowMatched((s) => !s)}
                    className="inline-flex items-center gap-1.5 text-[11px] uppercase tracking-wider text-faint hover:text-mute">
                    <Chevron open={showMatched} /> Matched {result.matches.length}
                  </button>
                  {showMatched && (
                    <div className="mt-2 max-h-56 space-y-1 overflow-y-auto">
                      {result.matches.map((m, i) => (
                        <div key={i} className="flex items-center gap-2 text-xs">
                          <span className="w-48 shrink-0 truncate text-mute">{m.name}</span>
                          <span className="text-faint"><ArrowRight /></span>
                          <span className="flex-1 truncate text-ink">{m.fund}</span>
                          <span className="tnum text-gold">{m.rate}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {result.unmatched.length > 0 && (
                <div>
                  <p className="mb-1.5 text-[11px] uppercase tracking-wider text-warn">Unmatched — no fund resolved</p>
                  <div className="flex flex-wrap gap-1.5">
                    {result.unmatched.map((n) => (
                      <span key={n} className="rounded-md border border-warn/30 bg-warn/5 px-2 py-0.5 text-xs text-mute">{n}</span>
                    ))}
                  </div>
                  <p className="mt-2 text-xs text-faint">Rename in your sheet to match the fund, or add the fund first, then re-import (idempotent).</p>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── CMA report ─────────────────────────────────────────────────────────────
type PreState = { status: "empty" | "invalid" | "wrong" | "ok"; msg: string; tone: Tone };

function validateCma(text: string): PreState {
  if (!text.trim()) return { status: "empty", msg: "", tone: "warn" };
  let doc: unknown;
  try { doc = JSON.parse(text); } catch {
    return { status: "invalid", msg: "Not valid JSON — check for a trailing comma or unquoted key.", tone: "bad" };
  }
  const d = doc as Record<string, unknown>;
  const list = Array.isArray(doc) ? doc : (d.funds as unknown[] | undefined);
  if (!Array.isArray(list)) {
    if (d.aum_by_fund_type || d.market_asset_classes) {
      return {
        status: "wrong",
        msg: "This is a market-level aggregates file (aum_by_fund_type / market_asset_classes). Those belong in Config keys (e.g. market.*), NOT here — this importer needs per-fund rows in a funds:[…] array.",
        tone: "warn",
      };
    }
    return { status: "wrong", msg: "Expected { \"funds\": [ … ] } (or a bare array) of per-fund rows.", tone: "warn" };
  }
  let valid = 0; let first = "";
  for (const raw of list) {
    const r = raw as Record<string, unknown>;
    const name = String(r.fund ?? r.name ?? "").trim();
    const comp = r.comp_kes ?? r.classes ?? r.comp;
    if (name && comp && typeof comp === "object") { valid++; if (!first) first = name; }
  }
  if (valid === 0) return { status: "wrong", msg: "The funds array has no rows with both fund and comp_kes.", tone: "warn" };
  return { status: "ok", msg: `${valid} fund composition row${valid === 1 ? "" : "s"} detected · e.g. ${first}`, tone: "ok" };
}

function CmaTab() {
  const [result, setResult] = useState<CmaImportResult | null>(null);
  const [showSkipped, setShowSkipped] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileText, setFileText] = useState("");
  const [fileName, setFileName] = useState("");
  const [pending, start] = useTransition();
  const submit = (fd: FormData) => start(async () => setResult(await importCmaComposition(fd)));

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) { setFileName(""); setFileText(""); return; }
    setFileName(f.name);
    try { setFileText(await f.text()); } catch { setFileText(""); }
  }

  const content = fileText || paste;
  const pre = useMemo(() => validateCma(content), [content]);
  const blocked = pre.status === "invalid" || pre.status === "wrong";

  return (
    <div className="space-y-5">
      <Preflight tone="warn"
        msg="This lane writes PER-FUND composition (funds.composition + AUM) from import-cma-cis.ts / Table 18. Market-level splits (fund-type share, market asset classes) are Config keys, not this." />

      <form action={submit} className="space-y-4 rounded-xl border border-line bg-panel p-5">
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Quarter end</span>
            <input type="date" name="period" defaultValue={lastQuarterEnd()} className={inputCls} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Source URL</span>
            <input name="source_url" defaultValue="https://cmarcp.or.ke" className={"w-64 " + inputCls} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Extraction JSON</span>
            <input type="file" name="file" accept=".json,application/json" onChange={onFile} className={fileCls} />
          </label>
        </div>
        {fileName && <p className="text-xs text-mute">Loaded <code className="text-gold">{fileName}</code>.</p>}
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">…or paste the JSON</span>
          <textarea name="pasted" rows={8} value={fileText ? "" : paste} onChange={(e) => setPaste(e.target.value)}
            disabled={!!fileText}
            placeholder='{"period":"2026-03-31","funds":[{"fund":"CIC Money Market Fund","aum":75057623124,"comp_kes":{"cash":16845179547,"gok":49164540288}}]}'
            className={"w-full font-mono disabled:opacity-40 " + inputCls} />
        </label>
        {pre.status !== "empty" && <Preflight tone={pre.tone} msg={pre.msg} />}
        <div className="flex items-center gap-3">
          <button disabled={pending || blocked}
            className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:opacity-50">
            {pending ? "Applying…" : "Apply composition"}
          </button>
          <span className="text-xs text-faint">Writes <code>funds.composition</code> + AUM, then republishes the snapshot.</span>
        </div>
      </form>

      {result && (
        <div className="rounded-xl border border-line bg-panel p-5">
          {result.error ? <p className="text-sm text-bad">{result.error}</p> : (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3">
                <Stat label="Funds updated" value={String(result.matched)} tone="ok" />
                <Stat label="Yours uncovered" value={String(result.uncovered.length)} tone={result.uncovered.length ? "warn" : "faint"} />
                <Stat label="CMA skipped" value={String(result.unmatchedCma.length)} tone="faint" />
              </div>
              <p className="text-xs text-faint">for {result.period}</p>

              {result.uncovered.length > 0 && (
                <div>
                  <p className="mb-1.5 text-[11px] uppercase tracking-wider text-warn">Your funds without composition — likely name mismatches</p>
                  <div className="space-y-1">
                    {result.uncovered.map((f) => (
                      <div key={f.id} className="flex items-center gap-2 text-xs">
                        <span className="flex-1 truncate text-mute">{f.name}</span>
                        <a href={`/admin/funds/${f.id}`} className="text-faint hover:text-gold">Edit</a>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {result.unmatchedCma.length > 0 && (
                <div>
                  <button onClick={() => setShowSkipped((s) => !s)}
                    className="inline-flex items-center gap-1.5 text-[11px] uppercase tracking-wider text-faint hover:text-mute">
                    <Chevron open={showSkipped} /> Skipped CMA funds (not tracked)
                  </button>
                  {showSkipped && (
                    <div className="mt-1.5 flex max-h-48 flex-wrap gap-1.5 overflow-y-auto">
                      {result.unmatchedCma.map((n) => (
                        <span key={n} className="rounded-md border border-line bg-panel2 px-2 py-0.5 text-xs text-faint">{n}</span>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── Fund returns ───────────────────────────────────────────────────────────
function ReturnsTab() {
  const [result, setResult] = useState<ReturnsImportResult | null>(null);
  const [showMatched, setShowMatched] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileName, setFileName] = useState("");
  const [pending, start] = useTransition();
  const submit = (fd: FormData) => start(async () => setResult(await importReturns(fd)));

  // live count: a line with a name and at least one numeric in cols 1..9
  const parsed = useMemo(() => {
    let n = 0;
    for (const raw of paste.split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || /^name/i.test(line)) continue;
      const cols = line.split(/[,\t]/);
      if (cols.length < 2 || !cols[0].trim()) continue;
      const anyNum = cols.slice(1, 10).some((c) => {
        const v = Number(String(c).replace(/[^0-9.\-]/g, ""));
        return c.trim() !== "" && Number.isFinite(v);
      });
      if (anyNum) n++;
    }
    return n;
  }, [paste]);

  const total = result ? result.matched + result.unmatched.length : 0;
  const rate = total ? Math.round((result!.matched / total) * 100) : 0;

  return (
    <div className="space-y-5">
      <Preflight tone="warn"
        msg="Trailing performance from each MANAGER's monthly fund fact sheet (not CMA — that's quarterly composition). Blank cells are left untouched, so a partial sheet never wipes an existing figure and a young fund with no 5Y simply stays empty." />

      <form action={submit} className="space-y-4 rounded-xl border border-line bg-panel p-5">
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Statement month</span>
            <input type="date" name="as_of" defaultValue={lastMonthEnd()} className={inputCls} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">CSV file (optional)</span>
            <input type="file" name="file" accept=".csv,.tsv,text/csv"
              onChange={(e) => setFileName(e.target.files?.[0]?.name ?? "")} className={fileCls} />
          </label>
        </div>
        {fileName && <p className="text-xs text-mute">Loaded <code className="text-gold">{fileName}</code> — file takes precedence over pasted rows.</p>}
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">…or paste rows</span>
          <textarea name="pasted" rows={8} value={paste} onChange={(e) => setPaste(e.target.value)}
            placeholder={"Nabo Money Market Fund,12.5,13.8,15.1,14.6,10.9,12.0,10.0,1.30,0.80\nNabo Fixed Income Fund,12.8,13.8,14.3,15.3,11.8,12.9,11.3,1.2,0.8"}
            className={"w-full font-mono " + inputCls} />
        </label>
        {!fileName && paste.trim() && (
          <Preflight tone={parsed ? "ok" : "warn"}
            msg={parsed ? `${parsed} return row${parsed === 1 ? "" : "s"} detected.` : "No parseable rows yet — each line needs a name and at least one number."} />
        )}
        <div className="flex items-center gap-3">
          <button disabled={pending}
            className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:opacity-50">
            {pending ? "Importing…" : "Import returns"}
          </button>
        </div>
        <p className="text-xs text-faint">
          Columns: <code>name, ytd, 1y, 3y, 5y, bench1y, bench3y, bench5y, best, worst</code>. Leave a cell blank to skip it. An optional 11th column (<code>YYYY-MM-DD</code>) overrides the statement month for that row.
        </p>
      </form>

      {result && (
        <div className="rounded-xl border border-line bg-panel p-5">
          {result.error ? <p className="text-sm text-bad">{result.error}</p> : (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-3">
                <Stat label="Updated" value={String(result.matched)} tone="ok" />
                <Stat label="Unmatched" value={String(result.unmatched.length)} tone={result.unmatched.length ? "warn" : "faint"} />
                <Stat label="Match rate" value={`${rate}%`} tone={rate >= 90 ? "ok" : rate >= 60 ? "warn" : "faint"} />
              </div>
              <p className="text-xs text-faint">as of {result.asOf}</p>

              {result.matches.length > 0 && (
                <div>
                  <button onClick={() => setShowMatched((s) => !s)}
                    className="inline-flex items-center gap-1.5 text-[11px] uppercase tracking-wider text-faint hover:text-mute">
                    <Chevron open={showMatched} /> Matched {result.matches.length}
                  </button>
                  {showMatched && (
                    <div className="mt-2 max-h-56 space-y-1 overflow-y-auto">
                      {result.matches.map((m, i) => (
                        <div key={i} className="flex items-start gap-2 text-xs">
                          <span className="w-48 shrink-0 text-mute">{m.name}</span>
                          <span className="mt-0.5 text-faint"><ArrowRight /></span>
                          <span className="flex-1 text-ink">{m.fund}</span>
                          <span className="tnum text-gold">{m.y1 != null ? `${m.y1}% 1y` : "—"}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {result.unmatched.length > 0 && (
                <div>
                  <p className="mb-1.5 text-[11px] uppercase tracking-wider text-warn">Unmatched — no fund resolved</p>
                  <div className="flex flex-wrap gap-1.5">
                    {result.unmatched.map((n) => (
                      <span key={n} className="rounded-md border border-warn/30 bg-warn/5 px-2 py-0.5 text-xs text-mute">{n}</span>
                    ))}
                  </div>
                  <p className="mt-2 text-xs text-faint">Rename in your sheet to match the fund, or add the fund first, then re-import (idempotent).</p>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

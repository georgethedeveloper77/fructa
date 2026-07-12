"use client";

import { useMemo, useState, useTransition } from "react";
import {
  previewDividendImport,
  applyDividendImport,
  type DivImportRow,
  type DivMatchRow,
} from "./actions";
import { IconChevronRight, IconArrowRight } from "../_icons";

// Dividends are DECLARED, once or twice a year at results season. That is why
// this is an import and not a scraper: there is no continuously-quoted number
// to poll, and building 60 bespoke IR-page parsers to catch an event that
// happens twice a year would be fragile for no gain.
//
// Rows: ticker,financial_year,kind,dps_kes[,payment_date][,source_url]
// Matched on ticker, which is exact. A row either lands on the right company or
// is listed as unmatched. Nothing is guessed.

const KINDS = ["interim", "final", "special"];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function parseNum(s: string | undefined): number | null {
  const t = (s ?? "").replace(/kes/i, "").replace(/,/g, "").trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function parseRows(text: string): DivImportRow[] {
  const out: DivImportRow[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const p = line.split(",").map((x) => x.trim());
    if (p.length < 4) continue;
    if (/^ticker$/i.test(p[0])) continue; // header

    const year = parseNum(p[1]);
    const kindRaw = (p[2] || "final").toLowerCase();
    out.push({
      ticker: p[0].toUpperCase(),
      financialYear: year == null ? null : Math.round(year),
      kind: KINDS.includes(kindRaw) ? kindRaw : kindRaw, // kept raw so preview can flag it
      dpsKes: parseNum(p[3]),
      paymentDate: p[4] && ISO_DATE.test(p[4]) ? p[4] : null,
      sourceUrl: p[5] || null,
    });
  }
  return out;
}

const fileCls =
  "text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute";

export function ImportDividends() {
  const [open, setOpen] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileText, setFileText] = useState("");
  const [fileName, setFileName] = useState("");
  const [matched, setMatched] = useState<DivMatchRow[]>([]);
  const [unmatched, setUnmatched] = useState<string[]>([]);
  const [invalid, setInvalid] = useState<string[]>([]);
  const [skip, setSkip] = useState<Set<string>>(new Set());
  const [previewed, setPreviewed] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const content = fileText || paste;
  const rows = useMemo(() => parseRows(content), [content]);

  const keyOf = (m: DivMatchRow) => `${m.stockId}|${m.financialYear}|${m.kind}`;

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setPreviewed(false);
    setDone(null);
    if (!f) {
      setFileName("");
      setFileText("");
      return;
    }
    setFileName(f.name);
    try {
      setFileText(await f.text());
    } catch {
      setFileText("");
    }
  }

  function preview() {
    setDone(null);
    start(async () => {
      const r = await previewDividendImport(rows);
      setMatched(r.matched);
      setUnmatched(r.unmatched);
      setInvalid(r.invalid);
      setSkip(new Set());
      setPreviewed(true);
    });
  }

  function toggleSkip(k: string) {
    setSkip((s) => {
      const n = new Set(s);
      n.has(k) ? n.delete(k) : n.add(k);
      return n;
    });
  }

  const applyRows = useMemo(
    () => matched.filter((m) => !skip.has(keyOf(m))),
    [matched, skip],
  );

  function apply() {
    start(async () => {
      const r = await applyDividendImport(applyRows);
      setDone(
        `Wrote ${r.written} ${r.written === 1 ? "dividend" : "dividends"} and republished the snapshot.`,
      );
      setPreviewed(false);
      setMatched([]);
      setUnmatched([]);
      setInvalid([]);
    });
  }

  const field =
    "w-full rounded-md border border-line bg-panel2 px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-faint focus:border-gold/60 disabled:opacity-40";

  return (
    <div className="mb-4 rounded-xl border border-line bg-panel">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center gap-2 px-4 py-3 text-left text-sm font-medium text-ink"
      >
        <span className={"text-faint transition-transform " + (open ? "rotate-90" : "")}>
          <IconChevronRight size={13} />
        </span>
        Import dividends
        <span className="ml-2 text-xs font-normal text-faint">
          declared per share, matched by ticker
        </span>
      </button>

      {open && (
        <div className="space-y-3 border-t border-line px-4 py-4">
          <p className="text-xs leading-relaxed text-mute">
            Attach a <code className="text-faint">ticker,financial_year,kind,dps_kes,payment_date,source_url</code>{" "}
            CSV (or paste rows). Kind is <code className="text-faint">interim</code>,{" "}
            <code className="text-faint">final</code> or <code className="text-faint">special</code>. Dates are
            YYYY-MM-DD. Re-importing the same year and kind corrects that record rather than duplicating it. Preview
            shows what changes; nothing is written until you apply.
          </p>

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">CSV file</span>
            <input type="file" accept=".csv,.tsv,text/csv" onChange={onFile} className={fileCls} />
          </label>
          {fileName && (
            <p className="text-xs text-mute">
              Loaded <code className="text-gold">{fileName}</code>. File takes precedence over pasted rows.
            </p>
          )}

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">or paste rows</span>
            <textarea
              rows={6}
              value={fileText ? "" : paste}
              disabled={!!fileText}
              onChange={(e) => {
                setPaste(e.target.value);
                setPreviewed(false);
                setDone(null);
              }}
              placeholder={"SCOM,2025,final,1.20,2025-08-31\nEQTY,2025,interim,0.50"}
              className={field}
              spellCheck={false}
            />
          </label>

          <div className="flex flex-wrap items-center gap-3">
            <span className="tnum text-xs text-faint">{rows.length} rows parsed</span>
            <button
              disabled={pending || rows.length === 0}
              onClick={preview}
              className="ml-auto rounded-md border border-line bg-panel2 px-3 py-1.5 text-xs text-mute hover:text-ink disabled:opacity-40"
            >
              {pending && !previewed ? "Matching" : "Preview"}
            </button>
          </div>

          {done && (
            <p className="rounded-md border border-live/40 bg-live/10 px-3 py-2 text-xs text-live">{done}</p>
          )}

          {previewed && (
            <div className="space-y-3">
              {matched.length > 0 && (
                <div className="overflow-hidden rounded-lg border border-line">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-line bg-panel2 text-left text-[10px] uppercase tracking-wider text-faint">
                        <th className="w-8 px-2 py-2" />
                        <th className="px-2 py-2">Company</th>
                        <th className="px-2 py-2">Year</th>
                        <th className="px-2 py-2">Kind</th>
                        <th className="px-2 py-2">DPS</th>
                        <th className="px-2 py-2">Paid</th>
                      </tr>
                    </thead>
                    <tbody>
                      {matched.map((m) => {
                        const k = keyOf(m);
                        const on = !skip.has(k);
                        const isNew = m.dpsFrom == null;
                        const changed = !isNew && m.dpsFrom !== m.dpsTo;
                        return (
                          <tr key={k} className="border-b border-line/60 last:border-0">
                            <td className="px-2 py-2">
                              <input
                                type="checkbox"
                                checked={on}
                                onChange={() => toggleSkip(k)}
                                className="accent-gold"
                              />
                            </td>
                            <td className="px-2 py-2">
                              <div className="font-medium text-ink">{m.stockName}</div>
                              <div className="font-mono text-[10px] text-faint">{m.ticker}</div>
                            </td>
                            <td className="tnum px-2 py-2 text-mute">FY{m.financialYear}</td>
                            <td className="px-2 py-2 text-mute">{m.kind}</td>
                            <td className="px-2 py-2">
                              {isNew ? (
                                <span className="font-medium text-gold">{m.dpsTo.toFixed(2)}</span>
                              ) : changed ? (
                                <span className="inline-flex items-center gap-1">
                                  <span className="text-faint">{m.dpsFrom!.toFixed(2)}</span>
                                  <IconArrowRight size={12} className="text-gold" />
                                  <span className="font-medium text-gold">{m.dpsTo.toFixed(2)}</span>
                                </span>
                              ) : (
                                <span className="text-ink">
                                  {m.dpsTo.toFixed(2)}
                                  <span className="ml-1 text-[10px] text-faint">keep</span>
                                </span>
                              )}
                            </td>
                            <td className="px-2 py-2 text-faint">{m.paymentDate ?? "not set"}</td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}

              {unmatched.length > 0 && (
                <div className="rounded-lg border border-warn/30 bg-warn/5 px-3 py-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wider text-warn">
                    {unmatched.length} unknown {unmatched.length === 1 ? "ticker" : "tickers"}. Add the company first,
                    or fix the ticker.
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {unmatched.map((n) => (
                      <span
                        key={n}
                        className="rounded border border-line bg-panel2 px-2 py-0.5 font-mono text-[11px] text-mute"
                      >
                        {n}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {invalid.length > 0 && (
                <div className="rounded-lg border border-bad/30 bg-bad/5 px-3 py-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wider text-bad">
                    {invalid.length} unusable {invalid.length === 1 ? "row" : "rows"}, skipped
                  </div>
                  <div className="space-y-0.5">
                    {invalid.map((n, i) => (
                      <div key={i} className="font-mono text-[11px] text-mute">
                        {n}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div className="flex items-center gap-3">
                <button
                  disabled={pending || applyRows.length === 0}
                  onClick={apply}
                  className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40"
                >
                  {pending
                    ? "Writing"
                    : `Apply ${applyRows.length} ${applyRows.length === 1 ? "dividend" : "dividends"}`}
                </button>
                <span className="text-xs text-faint">A republish follows.</span>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

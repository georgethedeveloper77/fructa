"use client";

import { useMemo, useState, useTransition } from "react";
import {
  previewSaccoRateImport,
  applySaccoRateImport,
  type SaccoImportRow,
  type SaccoMatchRow,
} from "./actions";
import { IconChevronRight, IconArrowRight } from "../_icons";

// SACCO rates are DECLARED at the AGM, once a year, between January and April.
// There is nothing to poll: the number does not move for the other eight months.
// So this is an import, like the dividends lane, and not a scraper.
//
// Rows: sacco,financial_year,interest_on_deposits,dividend_on_share_capital[,declared_on][,source_url]
// The first column takes either the slug id or the society's name. Matching is
// exact on id, then on a normalised name, and it never guesses: a name that hits
// two societies is reported as ambiguous, a name that hits none as unmatched.

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function parseNum(s: string | undefined): number | null {
  const t = (s ?? "").replace(/%/g, "").replace(/,/g, "").trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function parseRows(text: string): SaccoImportRow[] {
  const out: SaccoImportRow[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const p = line.split(",").map((x) => x.trim());
    if (p.length < 3) continue;
    if (/^sacco$/i.test(p[0]) || /^id$/i.test(p[0]) || /^name$/i.test(p[0])) {
      continue; // header
    }

    const year = parseNum(p[1]);
    out.push({
      key: p[0],
      financialYear: year == null ? null : Math.round(year),
      deposits: parseNum(p[2]),
      dividend: parseNum(p[3]),
      declaredOn: p[4] && ISO_DATE.test(p[4]) ? p[4] : null,
      sourceUrl: p[5] || null,
    });
  }
  return out;
}

const pct = (v: number | null) => v == null ? "not set" : `${v.toFixed(2)}%`;

const fileCls =
  "text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute";

export function ImportSaccoRates() {
  const [open, setOpen] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileText, setFileText] = useState("");
  const [fileName, setFileName] = useState("");
  const [matched, setMatched] = useState<SaccoMatchRow[]>([]);
  const [unmatched, setUnmatched] = useState<string[]>([]);
  const [ambiguous, setAmbiguous] = useState<string[]>([]);
  const [invalid, setInvalid] = useState<string[]>([]);
  const [skip, setSkip] = useState<Set<string>>(new Set());
  const [previewed, setPreviewed] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const content = fileText || paste;
  const rows = useMemo(() => parseRows(content), [content]);

  const keyOf = (m: SaccoMatchRow) => `${m.saccoId}|${m.financialYear}`;

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
      const r = await previewSaccoRateImport(rows);
      setMatched(r.matched);
      setUnmatched(r.unmatched);
      setAmbiguous(r.ambiguous);
      setInvalid(r.invalid);
      setSkip(new Set());
      setPreviewed(true);
    });
  }

  function toggleSkip(k: string) {
    setSkip((s) => {
      const n = new Set(s);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  }

  const applyRows = useMemo(
    () => matched.filter((m) => !skip.has(keyOf(m))),
    [matched, skip],
  );
  const warnCount = useMemo(
    () => applyRows.filter((m) => m.warn).length,
    [applyRows],
  );

  function apply() {
    start(async () => {
      const r = await applySaccoRateImport(applyRows);
      setDone(
        `Wrote ${r.written} ${r.written === 1 ? "year" : "years"} of rates and republished the snapshot.`,
      );
      setPreviewed(false);
      setMatched([]);
      setUnmatched([]);
      setAmbiguous([]);
      setInvalid([]);
    });
  }

  const field =
    "w-full rounded-md border border-line bg-panel2 px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-faint focus:border-gold/60 disabled:opacity-40";

  // One cell, two states: a fresh value, or a correction with the old value
  // shown next to it. Same pattern as the dividends importer.
  const Cell = (
    { from, to, tone }: {
      from: number | null;
      to: number | null;
      tone: "live" | "gold";
    },
  ) => {
    const cls = tone === "live" ? "text-live" : "text-gold";
    if (to == null) return <span className="text-[11px] text-faint">not set</span>;
    if (from == null) {
      return <span className={"tnum font-medium " + cls}>{pct(to)}</span>;
    }
    if (from === to) {
      return (
        <span className="tnum text-ink">
          {pct(to)}
          <span className="ml-1 text-[10px] text-faint">keep</span>
        </span>
      );
    }
    return (
      <span className="inline-flex items-center gap-1">
        <span className="tnum text-faint">{pct(from)}</span>
        <IconArrowRight size={12} className="text-gold" />
        <span className={"tnum font-medium " + cls}>{pct(to)}</span>
      </span>
    );
  };

  return (
    <div className="mb-4 rounded-xl border border-line bg-panel">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center gap-2 px-4 py-3 text-left text-sm font-medium text-ink"
      >
        <span
          className={"text-faint transition-transform " + (open ? "rotate-90" : "")}
        >
          <IconChevronRight size={13} />
        </span>
        Import AGM rates
        <span className="ml-2 text-xs font-normal text-faint">
          deposit interest and share dividend, declared once a year
        </span>
      </button>

      {open && (
        <div className="space-y-3 border-t border-line px-4 py-4">
          <p className="text-xs leading-relaxed text-mute">
            Attach a{" "}
            <code className="text-faint">
              sacco,financial_year,interest_on_deposits,dividend_on_share_capital,declared_on,source_url
            </code>{" "}
            CSV (or paste rows). The first column takes the slug id or the
            society&apos;s name. The financial year is the year that{" "}
            <span className="text-ink">ended</span>: a March 2026 AGM declaring for
            the year to 31 December 2025 is <code className="text-faint">2025</code>.
            Re-importing a year corrects it rather than duplicating it. Nothing is
            written until you apply.
          </p>

          {/* The column order is stated once, loudly, because getting it wrong is
              the single most damaging import error in this lane. The deposit rate
              is the number the app RANKS on. A swapped row puts a society at the
              top of the league table on the strength of a percentage paid on a
              capped pot of shares. */}
          <div className="rounded-lg border border-gold/30 bg-gold/5 px-3 py-2">
            <div className="text-[10px] uppercase tracking-wider text-gold">
              Column order matters
            </div>
            <p className="mt-1 text-xs leading-relaxed text-mute">
              Third column is{" "}
              <span className="text-live">interest on deposits</span>, paid on
              savings. Fourth is{" "}
              <span className="text-gold">dividend on share capital</span>, paid on
              shares. The dividend is nearly always the bigger percentage and the
              smaller cheque, and the deposit rate is the one the app ranks on.
              Preview flags any row where they look swapped.
            </p>
          </div>

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">
              CSV file
            </span>
            <input
              type="file"
              accept=".csv,.tsv,text/csv"
              onChange={onFile}
              className={fileCls}
            />
          </label>
          {fileName && (
            <p className="text-xs text-mute">
              Loaded <code className="text-gold">{fileName}</code>. File takes
              precedence over pasted rows.
            </p>
          )}

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">
              or paste rows
            </span>
            <textarea
              rows={6}
              value={fileText ? "" : paste}
              disabled={!!fileText}
              onChange={(e) => {
                setPaste(e.target.value);
                setPreviewed(false);
                setDone(null);
              }}
              placeholder={"tower-sacco,2025,13.0,20.0,2026-03-21\nNyati Sacco Society Ltd,2025,11.3,21.0"}
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
            <p className="rounded-md border border-live/40 bg-live/10 px-3 py-2 text-xs text-live">
              {done}
            </p>
          )}

          {previewed && (
            <div className="space-y-3">
              {matched.length > 0 && (
                <div className="overflow-hidden rounded-lg border border-line">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-line bg-panel2 text-left text-[10px] uppercase tracking-wider text-faint">
                        <th className="w-8 px-2 py-2" />
                        <th className="px-2 py-2">Society</th>
                        <th className="px-2 py-2">Year</th>
                        <th className="px-2 py-2">On deposits</th>
                        <th className="px-2 py-2">Dividend</th>
                        <th className="px-2 py-2">Declared</th>
                      </tr>
                    </thead>
                    <tbody>
                      {matched.map((m) => {
                        const k = keyOf(m);
                        const on = !skip.has(k);
                        return (
                          <tr
                            key={k}
                            className={"border-b border-line/60 last:border-0 " +
                              (m.warn ? "bg-warn/5" : "")}
                          >
                            <td className="px-2 py-2 align-top">
                              <input
                                type="checkbox"
                                checked={on}
                                onChange={() => toggleSkip(k)}
                                className="accent-gold"
                              />
                            </td>
                            <td className="px-2 py-2">
                              <div className="font-medium text-ink">{m.saccoName}</div>
                              <div className="font-mono text-[10px] text-faint">
                                {m.saccoId}
                              </div>
                              {m.warn && (
                                <div className="mt-1 text-[10px] leading-relaxed text-warn">
                                  {m.warn}
                                </div>
                              )}
                            </td>
                            <td className="tnum px-2 py-2 align-top text-mute">
                              FY{m.financialYear}
                            </td>
                            <td className="px-2 py-2 align-top">
                              <Cell from={m.depositsFrom} to={m.depositsTo} tone="live" />
                            </td>
                            <td className="px-2 py-2 align-top">
                              <Cell from={m.dividendFrom} to={m.dividendTo} tone="gold" />
                            </td>
                            <td className="px-2 py-2 align-top text-faint">
                              {m.declaredOn ?? "not set"}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}

              {ambiguous.length > 0 && (
                <div className="rounded-lg border border-bad/30 bg-bad/5 px-3 py-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wider text-bad">
                    {ambiguous.length}{" "}
                    {ambiguous.length === 1 ? "name matches" : "names match"} more than
                    one society, skipped. Use the slug id instead.
                  </div>
                  <div className="space-y-0.5">
                    {ambiguous.map((n, i) => (
                      <div key={i} className="font-mono text-[11px] text-mute">{n}</div>
                    ))}
                  </div>
                </div>
              )}

              {unmatched.length > 0 && (
                <div className="rounded-lg border border-warn/30 bg-warn/5 px-3 py-2">
                  <div className="mb-1 text-[10px] uppercase tracking-wider text-warn">
                    {unmatched.length} unknown{" "}
                    {unmatched.length === 1 ? "society" : "societies"}. Add it first,
                    or use the slug id.
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
                    {invalid.length} unusable {invalid.length === 1 ? "row" : "rows"},
                    skipped
                  </div>
                  <div className="space-y-0.5">
                    {invalid.map((n, i) => (
                      <div key={i} className="font-mono text-[11px] text-mute">{n}</div>
                    ))}
                  </div>
                </div>
              )}

              <div className="flex flex-wrap items-center gap-3">
                <button
                  disabled={pending || applyRows.length === 0}
                  onClick={apply}
                  className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40"
                >
                  {pending
                    ? "Writing"
                    : `Apply ${applyRows.length} ${applyRows.length === 1 ? "year" : "years"}`}
                </button>
                {warnCount > 0 && (
                  <span className="text-xs text-warn">
                    {warnCount} flagged {warnCount === 1 ? "row is" : "rows are"} still
                    ticked. Untick to leave them out.
                  </span>
                )}
                <span className="text-xs text-faint">A republish follows.</span>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

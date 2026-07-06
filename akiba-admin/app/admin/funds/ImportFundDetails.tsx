"use client";

import { useMemo, useState, useTransition } from "react";
import {
  previewFundImport,
  applyFundImport,
  type ImportRow,
  type MatchRow,
  type ApplyRow,
} from "./actions";
import { IconChevronRight, IconArrowRight } from "../_icons";

// ── parsing ─────────────────────────────────────────────────────────────────
// Accepts "name,rate,min,fee,aum" lines. Numbers tolerate a "KES" prefix and
// K/M/B suffixes on min/AUM. A header row (starts with "name") is skipped.

function parseAmount(s: string | undefined): number | null {
  const t = (s ?? "").replace(/kes/i, "").replace(/\s/g, "").replace(/,/g, "").trim();
  if (!t) return null;
  const m = t.match(/^([\d.]+)\s*([kmb])?$/i);
  if (!m) {
    const n = Number(t);
    return Number.isFinite(n) ? n : null;
  }
  let n = parseFloat(m[1]);
  const suf = (m[2] || "").toLowerCase();
  if (suf === "k") n *= 1e3;
  else if (suf === "m") n *= 1e6;
  else if (suf === "b") n *= 1e9;
  return Number.isFinite(n) ? n : null;
}
function parsePct(s: string | undefined): number | null {
  const t = (s ?? "").replace("%", "").trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}
function parseRows(text: string): ImportRow[] {
  const out: ImportRow[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const p = line.split(",").map((s) => s.trim());
    if (p.length < 2) continue;
    if (/^name$/i.test(p[0])) continue; // header
    out.push({
      name: p[0],
      rate: parsePct(p[1]),
      min: parseAmount(p[2]),
      fee: parsePct(p[3]),
      aumKes: parseAmount(p[4]),
    });
  }
  return out;
}

// ── formatting ──────────────────────────────────────────────────────────────
function fmtKes(v: number | null): string {
  if (v == null) return "—";
  if (v >= 1e9) {
    const b = v / 1e9;
    return `${b >= 10 ? Math.round(b) : b.toFixed(1)}B`;
  }
  if (v >= 1e6) return `${Math.round(v / 1e6)}M`;
  if (v >= 1e3) return `${Math.round(v / 1e3)}K`;
  return `${v}`;
}
const fmtPct = (v: number | null) => (v == null ? "—" : `${v}%`);

const fileCls =
  "text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute";

export function ImportFundDetails() {
  const [open, setOpen] = useState(false);
  const [paste, setPaste] = useState("");
  const [fileText, setFileText] = useState("");
  const [fileName, setFileName] = useState("");
  const [fillOnly, setFillOnly] = useState(true);
  const [matched, setMatched] = useState<MatchRow[]>([]);
  const [unmatched, setUnmatched] = useState<string[]>([]);
  const [skip, setSkip] = useState<Set<string>>(new Set());
  const [previewed, setPreviewed] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [pending, start] = useTransition();

  // A loaded file takes precedence over pasted rows (mirrors the Import page).
  const content = fileText || paste;
  const rows = useMemo(() => parseRows(content), [content]);

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
      const r = await previewFundImport(rows, fillOnly);
      setMatched(r.matched);
      setUnmatched(r.unmatched);
      setSkip(new Set());
      setPreviewed(true);
    });
  }

  function toggleSkip(id: string) {
    setSkip((s) => {
      const n = new Set(s);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });
  }

  // rows that will actually write something, minus explicitly skipped ones
  const applyRows: ApplyRow[] = useMemo(() => {
    const out: ApplyRow[] = [];
    for (const m of matched) {
      if (skip.has(m.fundId)) continue;
      const a: ApplyRow = { fundId: m.fundId };
      if (m.rate.write && m.rate.to != null) a.rate = m.rate.to;
      if (m.min.write && m.min.to != null) a.min = m.min.to;
      if (m.fee.write && m.fee.to != null) a.fee = m.fee.to;
      if (m.aum.write && m.aum.to != null) a.aumKes = m.aum.to;
      if (a.rate != null || a.min != null || a.fee != null || a.aumKes != null) out.push(a);
    }
    return out;
  }, [matched, skip]);

  function apply() {
    start(async () => {
      const r = await applyFundImport(applyRows);
      setDone(`Wrote ${r.written} ${r.written === 1 ? "fund" : "funds"} and republished the snapshot.`);
      setPreviewed(false);
      setMatched([]);
      setUnmatched([]);
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
        Bulk import fund details
        <span className="ml-2 text-xs font-normal text-faint">rate · minimum · fee · AUM, matched by name</span>
      </button>

      {open && (
        <div className="space-y-3 border-t border-line px-4 py-4">
          <p className="text-xs leading-relaxed text-mute">
            Attach a <code className="text-faint">name,rate,min,fee,aum</code> CSV (or paste rows). Min/AUM accept
            K/M/B, e.g. <code className="text-faint">100K</code>, <code className="text-faint">6.2B</code>. Preview shows
            which fund each row lands on and what changes — nothing is written until you apply.
          </p>

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">CSV file</span>
            <input type="file" accept=".csv,.tsv,text/csv" onChange={onFile} className={fileCls} />
          </label>
          {fileName && (
            <p className="text-xs text-mute">
              Loaded <code className="text-gold">{fileName}</code> — file takes precedence over pasted rows.
            </p>
          )}

          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">…or paste rows</span>
            <textarea
              rows={6}
              value={fileText ? "" : paste}
              disabled={!!fileText}
              onChange={(e) => {
                setPaste(e.target.value);
                setPreviewed(false);
                setDone(null);
              }}
              placeholder={"Nabo KES Money Market Fund,13.74,100K,2.25,6.2B\nCytonn Money Market Fund,11.72,1K,2.00,2.0B"}
              className={field}
              spellCheck={false}
            />
          </label>

          <div className="flex flex-wrap items-center gap-3">
            <label className="flex cursor-pointer items-center gap-2 text-xs text-mute">
              <input
                type="checkbox"
                checked={fillOnly}
                onChange={(e) => {
                  setFillOnly(e.target.checked);
                  setPreviewed(false);
                }}
                className="accent-gold"
              />
              Only fill blank fields (don&rsquo;t overwrite existing values)
            </label>
            <span className="tnum text-xs text-faint">{rows.length} rows parsed</span>
            <button
              disabled={pending || rows.length === 0}
              onClick={preview}
              className="ml-auto rounded-md border border-line bg-panel2 px-3 py-1.5 text-xs text-mute hover:text-ink disabled:opacity-40"
            >
              {pending && !previewed ? "Matching…" : "Preview"}
            </button>
          </div>

          {done && <p className="rounded-md border border-live/40 bg-live/10 px-3 py-2 text-xs text-live">{done}</p>}

          {previewed && (
            <div className="space-y-3">
              {matched.length > 0 && (
                <div className="overflow-hidden rounded-lg border border-line">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-line bg-panel2 text-left text-[10px] uppercase tracking-wider text-faint">
                        <th className="w-8 px-2 py-2" />
                        <th className="px-2 py-2">Fund</th>
                        <th className="px-2 py-2">Rate</th>
                        <th className="px-2 py-2">Min</th>
                        <th className="px-2 py-2">Fee</th>
                        <th className="px-2 py-2">AUM</th>
                      </tr>
                    </thead>
                    <tbody>
                      {matched.map((m) => {
                        const on = !skip.has(m.fundId);
                        return (
                          <tr key={m.fundId} className="border-b border-line/60 last:border-0">
                            <td className="px-2 py-2">
                              <input
                                type="checkbox"
                                checked={on}
                                onChange={() => toggleSkip(m.fundId)}
                                className="accent-gold"
                              />
                            </td>
                            <td className="px-2 py-2">
                              <div className="font-medium text-ink">{m.fundName}</div>
                              <div className="text-[10px] text-faint">
                                {m.currency}
                                {m.fundType ? ` · ${m.fundType}` : ""}
                                {!m.retail ? " · dormant" : ""}
                              </div>
                            </td>
                            <Cell d={m.rate} fmt={fmtPct} />
                            <Cell d={m.min} fmt={fmtKes} />
                            <Cell d={m.fee} fmt={fmtPct} />
                            <Cell d={m.aum} fmt={fmtKes} />
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
                    {unmatched.length} unmatched — rename to the exact fund and re-preview
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {unmatched.map((n) => (
                      <span key={n} className="rounded border border-line bg-panel2 px-2 py-0.5 text-[11px] text-mute">
                        {n}
                      </span>
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
                  {pending ? "Writing…" : `Apply to ${applyRows.length} ${applyRows.length === 1 ? "fund" : "funds"}`}
                </button>
                <span className="text-xs text-faint">Rates append to history; a republish follows.</span>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** One before→after cell. Gold when it will write, faint "keep" otherwise. */
function Cell({
  d,
  fmt,
}: {
  d: { from: number | null; to: number | null; write: boolean };
  fmt: (v: number | null) => string;
}) {
  if (d.to == null) return <td className="px-2 py-2 text-faint">—</td>;
  if (!d.write) {
    return (
      <td className="px-2 py-2">
        <span className="text-ink">{fmt(d.from)}</span>
        <span className="ml-1 text-[10px] text-faint">keep</span>
      </td>
    );
  }
  return (
    <td className="px-2 py-2">
      <span className="inline-flex items-center gap-1">
        <span className="text-faint">{fmt(d.from)}</span>
        <IconArrowRight size={12} className="text-gold" />
        <span className="font-medium text-gold">{fmt(d.to)}</span>
      </span>
    </td>
  );
}

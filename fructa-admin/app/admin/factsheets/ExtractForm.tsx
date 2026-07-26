"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { extractAndStage, type ExtractActionResult } from "./extract-action";
import { detectFromPdf, type DetectResult } from "./detect-action";
import { tooBig, MAX_PDF_LABEL } from "@/lib/factsheet/limits";

const inputCls =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";

type Fund = { id: string; name: string; currency: string };

/// Drop a PDF, get the fund.
///
/// The old version opened with a dropdown of every fund in the database and
/// asked the operator to find the right one. That is the wrong way round: the
/// answer is printed at the top of page one, and making a person scroll two
/// hundred options to retype it is both slow and the single easiest way to
/// apply a dollar sheet to a shilling fund.
///
/// Detection runs the moment a file is chosen and costs nothing. What the
/// operator does now is CONFIRM rather than search, with the words the
/// detector matched shown beside each candidate so the suggestion can be
/// checked rather than trusted.
export function ExtractForm({ funds }: { funds: Fund[] }) {
  const [open, setOpen] = useState(false);
  const [fundId, setFundId] = useState("");
  const [det, setDet] = useState<DetectResult | null>(null);
  const [res, setRes] = useState<ExtractActionResult | null>(null);
  const [fileName, setFileName] = useState("");
  const [url, setUrl] = useState("");
  const [query, setQuery] = useState("");
  const [sizeError, setSizeError] = useState<string | null>(null);
  const [detecting, start] = useTransition();
  const [pending, startExtract] = useTransition();
  const formRef = useRef<HTMLFormElement>(null);

  // Detection reads the file the form already holds, so it borrows the form's
  // own FormData rather than keeping a second copy of the bytes in state.
  const detect = () => {
    const f = formRef.current;
    if (!f) return;
    const fd = new FormData(f);
    setDet(null);
    setRes(null);
    start(async () => {
      const d = await detectFromPdf(fd);
      setDet(d);
      if (d.autoId) setFundId(d.autoId);
    });
  };

  useEffect(() => { if (!open) { setDet(null); setRes(null); setFundId(""); } }, [open]);

  // Searchable, because 200 options in a native select is a scroll, not a
  // choice. Matches on manager as well as fund name: people think "the Cytonn
  // one" before they think of the full registered title.
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return funds.slice(0, 40);
    return funds.filter((f) => f.name.toLowerCase().includes(q) || f.id.includes(q)).slice(0, 40);
  }, [funds, query]);

  const chosen = funds.find((f) => f.id === fundId) ?? null;

  const submit = (fd: FormData) => startExtract(async () => setRes(await extractAndStage(fd)));

  if (!open) {
    return (
      <button onClick={() => setOpen(true)}
        className="rounded-md border border-gold/60 bg-gold/10 px-3 py-1.5 text-sm text-gold hover:bg-gold/20">
        Extract a PDF
      </button>
    );
  }

  return (
    <form ref={formRef} action={submit} className="space-y-4 rounded-xl border border-line bg-panel p-5">
      {/* 1. the document */}
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">PDF</span>
          <input type="file" name="file" accept="application/pdf,.pdf"
            onChange={(e) => {
              const f = e.target.files?.[0];
              setUrl("");
              setFileName(f?.name ?? "");
              // Checked HERE, before the upload starts.
              //
              // The server action's body limit fires as a stack trace naming a
              // React component, with no mention of file size, after the whole
              // file has already been sent. Catching it in the browser costs
              // nothing and can say what is actually wrong.
              const err = f ? tooBig(f.size) : null;
              setSizeError(err);
              setDet(null);
              setRes(null);
              if (!err && f) detect();
            }}
            className="text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute" />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">or URL</span>
          <div className="flex gap-2">
            <input name="source_url" value={url} onChange={(e) => setUrl(e.target.value)}
              placeholder="https://cytonn.com/uploads/downloads/chyf-fact-sheet-jun-26.pdf"
              className={inputCls} />
            <button type="button" onClick={detect} disabled={!url.trim() || detecting}
              className="shrink-0 rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:text-ink disabled:opacity-40">
              Read
            </button>
          </div>
        </label>
      </div>

      {sizeError && (
        <div className="rounded-md border border-bad/40 bg-bad/10 px-3 py-2 text-xs text-bad">{sizeError}</div>
      )}

      {detecting && (
        <div className="text-xs text-mute">Reading {fileName || "the PDF"}. This is free, no model involved.</div>
      )}

      {/* 2. what it found */}
      {det && !det.ok && (
        <div className="rounded-md border border-warn/40 bg-warn/5 px-3 py-2 text-xs text-warn">{det.error}</div>
      )}

      {det?.ok && (
        <div className="space-y-2">
          <div className="flex flex-wrap items-baseline gap-x-3 text-[11px] text-faint">
            <span className="uppercase tracking-wider">
              {det.candidates.length === 0 ? "No fund recognised" : `${det.candidates.length} possible`}
            </span>
            <span>{det.pages} page{det.pages === 1 ? "" : "s"}</span>
            {det.detectedCurrency && <span>reads as {det.detectedCurrency}</span>}
            {det.autoId && <span className="text-live">top match selected for you</span>}
            {!det.autoId && det.candidates.length > 0 && (
              <span className="text-warn">too close to call, pick one</span>
            )}
          </div>

          {det.preview && (
            <div className="rounded-md border border-line bg-panel2 px-3 py-2 text-[11px] text-faint">
              {det.preview}
            </div>
          )}

          <div className="grid gap-2 sm:grid-cols-2">
            {det.candidates.map((c) => {
              const on = c.id === fundId;
              return (
                <button key={c.id} type="button" onClick={() => setFundId(c.id)}
                  className={"rounded-lg border px-3 py-2 text-left " +
                    (on ? "border-gold/60 bg-gold/10" : "border-line bg-panel2 hover:border-line2")}>
                  <div className="flex items-baseline gap-2">
                    <span className={"text-sm " + (on ? "text-gold" : "text-ink")}>{c.name}</span>
                    <span className="tnum text-[10px] text-faint">{c.currency}</span>
                    <span className="tnum ml-auto text-[10px] text-faint">{Math.round(c.score * 100)}%</span>
                  </div>
                  {/* WHY, not just how much. A percentage is a claim; the words
                      it matched are checkable against the page. */}
                  <div className="mt-0.5 text-[10px] text-faint">
                    {c.exact && <span className="text-live">name on the page</span>}
                    {c.exact && c.matched.length > 0 && <span> &middot; </span>}
                    {c.matched.length > 0 && <span>matched {c.matched.slice(0, 6).join(", ")}</span>}
                    {!c.currencyAgrees && <span className="text-warn"> &middot; currency disagrees</span>}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* 3. override, always available */}
      <div className="space-y-1">
        <span className="text-[11px] uppercase tracking-wider text-faint">
          {det?.ok && det.candidates.length ? "Or pick another fund" : "Fund on the sheet"}
        </span>
        <input value={query} onChange={(e) => setQuery(e.target.value)}
          placeholder="Search by fund name" className={inputCls} />
        <select name="fund_id" value={fundId} onChange={(e) => setFundId(e.target.value)}
          size={query ? 6 : 1} className={inputCls} required>
          <option value="" disabled>{chosen ? chosen.name : "Choose"}</option>
          {(chosen && !filtered.some((f) => f.id === chosen.id)) && (
            <option value={chosen.id}>{chosen.name} ({chosen.currency})</option>
          )}
          {filtered.map((f) => (
            <option key={f.id} value={f.id}>{f.name} ({f.currency})</option>
          ))}
        </select>
      </div>

      <label className="flex flex-col gap-1">
        <span className="text-[11px] uppercase tracking-wider text-faint">Note to the extractor, optional</span>
        <input name="hint" placeholder="Sheet covers six funds; this one is on page 3" className={inputCls} />
      </label>

      {res && !res.ok && (
        <div className="space-y-1 rounded-md border border-bad/40 bg-bad/10 px-3 py-2 text-xs text-bad">
          {res.errors.map((e, i) => <div key={i}>{e}</div>)}
          {res.tier === "needs_model" && (
            <div className="text-mute">Nothing was spent. Press Extract again to pay for the model.</div>
          )}
        </div>
      )}

      {res?.ok && (
        <div className="space-y-2">
          <div className="rounded-md border border-live/30 bg-live/5 px-3 py-2 text-xs text-live">
            Staged as #{res.id} via {res.model}.{" "}
            {res.cents === 0 ? "Cost nothing." : `Cost ${(res.cents / 100).toFixed(2)} dollars.`}{" "}
            It has changed nothing yet.
          </div>
          {res.excluded.length > 0 && (
            <div className="rounded-md border border-line bg-panel2 px-3 py-2">
              <div className="text-[10px] uppercase tracking-wider text-faint">Seen and not used</div>
              <ul className="mt-1 space-y-0.5">
                {res.excluded.map((x, i) => (
                  <li key={i} className="text-xs text-faint">
                    <span className="tnum text-mute">{String(x.value)}</span>
                    {x.caption && <span> captioned &ldquo;{x.caption}&rdquo;</span>}
                    {x.reason && <span>, {x.reason}</span>}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {res.warnings.map((w, i) => (
            <div key={i} className="rounded-md border border-warn/40 bg-warn/5 px-3 py-2 text-xs text-warn">{w}</div>
          ))}
        </div>
      )}

      <div className="flex items-center gap-2">
        <button disabled={pending || !fundId || !!sizeError}
          className="rounded-md border border-gold bg-gold/10 px-3 py-1.5 text-xs text-gold hover:bg-gold/20 disabled:opacity-40">
          {pending ? "Working" : "Extract and stage"}
        </button>
        <button type="button" onClick={() => setOpen(false)}
          className="rounded-md border border-line px-3 py-1.5 text-xs text-faint">Close</button>
        {!fundId && !sizeError && <span className="text-[11px] text-faint">Pick a fund first.</span>}
        <span className="ml-auto text-[11px] text-faint">Up to {MAX_PDF_LABEL}</span>
      </div>
    </form>
  );
}

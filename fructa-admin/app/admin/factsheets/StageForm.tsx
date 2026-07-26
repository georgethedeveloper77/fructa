"use client";

import { useMemo, useState, useTransition } from "react";
import { stageFactsheet, type StageResult } from "./actions";

const inputCls =
  "rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";

/// Paste an extraction and stage it. Phase 1 has no extractor, so this is where
/// a payload written by hand or by a model in another window comes in.
///
/// The counts below update as you type, deliberately. Pasting several hundred
/// lines of JSON and pressing a button is how a payload for the wrong fund gets
/// staged; seeing "3 periods, 5 rates, 2 excluded" before submitting is a cheap
/// check that the thing in the box is the thing you meant.
export function StageForm({ funds }: { funds: { id: string; name: string; currency: string }[] }) {
  const [open, setOpen] = useState(false);
  const [payload, setPayload] = useState("");
  const [res, setRes] = useState<StageResult | null>(null);
  const [pending, start] = useTransition();

  const peek = useMemo(() => {
    try {
      const d = JSON.parse(payload) as Record<string, unknown>;
      const n = (k: string) => (Array.isArray(d[k]) ? (d[k] as unknown[]).length : 0);
      return {
        ok: true as const,
        basis: (d.basis as { value?: string })?.value ?? null,
        terms: d.terms ? Object.keys(d.terms as object).length : 0,
        periods: n("periods"),
        rates: n("rates"),
        excluded: Array.isArray(d.excluded) ? n("excluded") : null,
      };
    } catch {
      return { ok: false as const };
    }
  }, [payload]);

  const submit = (fd: FormData) => start(async () => setRes(await stageFactsheet(fd)));

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="rounded-md border border-line px-3 py-1.5 text-sm text-mute hover:border-gold/60 hover:text-gold"
      >
        Stage a sheet
      </button>
    );
  }

  return (
    <form action={submit} className="space-y-4 rounded-xl border border-line bg-panel p-5">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Fund</span>
          <select name="fund_id" className={inputCls} defaultValue="">
            <option value="">Assign later</option>
            {funds.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name} ({f.currency})
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Sheet label</span>
          <input name="source_label" placeholder="MansaX Q1 2026" className={inputCls} required />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Date ON the sheet</span>
          <input type="date" name="as_of" className={inputCls} required />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Source URL</span>
          <input name="source_url" placeholder="https://" className={inputCls} />
        </label>
      </div>

      <label className="flex flex-col gap-1">
        <span className="text-[11px] uppercase tracking-wider text-faint">Payload JSON</span>
        <textarea
          name="payload"
          rows={10}
          value={payload}
          onChange={(e) => setPayload(e.target.value)}
          placeholder='{"basis":{"value":"return","caption":"Q1 2026 net returns of 4.74%"},"excluded":[]}'
          className={inputCls + " font-mono text-xs"}
        />
      </label>

      {payload.trim() !== "" && (
        <div className="text-xs">
          {!peek.ok ? (
            <span className="text-bad">Not valid JSON yet.</span>
          ) : (
            <span className="text-faint">
              basis <span className="text-ink">{peek.basis ?? "none"}</span>, {peek.terms} terms,{" "}
              {peek.periods} periods, {peek.rates} rates,{" "}
              {peek.excluded === null ? (
                <span className="text-bad">no excluded array</span>
              ) : (
                <span className={peek.excluded === 0 ? "text-warn" : "text-ink"}>
                  {peek.excluded} excluded
                </span>
              )}
            </span>
          )}
        </div>
      )}

      {res?.error && <div className="text-xs text-bad">{res.error}</div>}
      {res?.ok && <div className="text-xs text-live">Staged as #{res.id}. Review it below.</div>}

      <div className="flex gap-2">
        <button
          disabled={pending}
          className="rounded-md border border-gold bg-gold/10 px-3 py-1.5 text-xs text-gold hover:bg-gold/20"
        >
          {pending ? "Staging" : "Stage for review"}
        </button>
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="rounded-md border border-line px-3 py-1.5 text-xs text-faint"
        >
          Close
        </button>
      </div>
    </form>
  );
}

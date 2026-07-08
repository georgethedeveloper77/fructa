"use client";

import { useState, useTransition } from "react";
import { importLearn, type ImportResult } from "./actions";
import { IconDownload } from "../_icons";

// A real, importable example — doubles as the format spec and fills the
// "inflation" gap. Stringified so the newline escapes are valid JSON.
const EXAMPLE = {
  units: [
    {
      title: "Inflation & real returns",
      subtitle: "Why 10% earned can still lose to rising prices.",
      accent: "emerald",
      unlock_after: "u_rate",
      lessons: [
        {
          title: "What is inflation?",
          xp: 20,
          steps: [
            {
              kind: "explainer",
              payload: {
                title: "What is inflation?",
                body:
                  "Inflation is the rate at which prices rise over time. If a loaf costs KES 60 today and KES 66 next year, that's about 10% inflation.\n\nIt matters because the same shilling buys less over time. Kenya's inflation has recently hovered around 6–7%.",
                note: "fructa shows current inflation as a benchmark next to fund rates.",
              },
            },
            {
              kind: "chart",
              payload: {
                chart: "bars",
                title: "A top MMF vs inflation, today",
                unit: "%",
                caption:
                  "The fund's yield clears inflation — the gap is your real gain.",
                series: [
                  { label: "Etica MMF", value: 10.67, highlight: true },
                  { label: "Inflation", value: 6.7 },
                ],
              },
            },
            {
              kind: "quiz",
              payload: {
                prompt:
                  "Prices rose from KES 100 to KES 107 over a year. Roughly what was inflation?",
                options: [
                  { text: "About 7%", correct: true },
                  { text: "About 107%", correct: false },
                  { text: "Prices don't measure inflation", correct: false },
                ],
                explain_ok: "Right — a 7-shilling rise on 100 is about 7%.",
                explain_no: "Inflation is the percent change: 7 on 100 ≈ 7%.",
              },
            },
          ],
        },
        {
          title: "Real vs nominal return",
          xp: 30,
          steps: [
            {
              kind: "explainer",
              payload: {
                title: "Real vs nominal return",
                body:
                  "Your nominal return is the headline yield — say 10%. Your real return is what's left after inflation takes its share.\n\nIf a fund pays 10% and inflation is 7%, your real return is only about 3% — the true growth in what your money can buy.",
                note: "A high rate in a high-inflation year can still be a small real gain.",
              },
            },
            {
              kind: "quiz",
              payload: {
                prompt: "A fund pays 10% and inflation is 7%. Your real return is about…",
                options: [
                  { text: "About 3%", correct: true },
                  { text: "17%", correct: false },
                  { text: "10%", correct: false },
                ],
                explain_ok: "Right — 10% earned minus ~7% inflation ≈ 3% real.",
                explain_no: "Subtract inflation from the yield: 10% − 7% ≈ 3%.",
              },
            },
          ],
        },
      ],
    },
  ],
};
const EXAMPLE_TEXT = JSON.stringify(EXAMPLE, null, 2);

const field =
  "w-full rounded-md border border-line bg-panel2 px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-faint focus:border-gold/60";
const btnGold =
  "rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40";
const btnGhost =
  "flex items-center gap-1 rounded-md border border-line bg-panel2 px-2.5 py-1 text-xs text-mute hover:text-ink";

export function LearnImport() {
  const [json, setJson] = useState("");
  const [replace, setReplace] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [pending, start] = useTransition();

  function run() {
    const fd = new FormData();
    fd.set("json", json);
    fd.set("replace", String(replace));
    start(async () => setResult(await importLearn(fd)));
  }

  return (
    <details className="mb-4 rounded-xl border border-line bg-panel [&_summary::-webkit-details-marker]:hidden">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3">
        <IconDownload size={15} />
        <span className="text-sm font-semibold text-ink">Import</span>
        <span className="text-[11px] text-faint">
          paste a JSON document — great for AI-generated content
        </span>
      </summary>

      <div className="space-y-3 px-4 pb-4">
        <p className="text-xs leading-relaxed text-mute">
          Paste a <code className="text-faint">{`{ "units": [ … ] }`}</code>{" "}
          document. Ids and order are optional — generated from titles and
          array position when absent — so a minimal doc still imports.
        </p>

        <textarea
          rows={10}
          value={json}
          onChange={(e) => setJson(e.target.value)}
          spellCheck={false}
          placeholder='{ "units": [ … ] }'
          className={field}
        />

        <div className="flex flex-wrap items-center gap-3">
          <button onClick={run} disabled={pending || !json.trim()} className={btnGold}>
            {pending ? "Importing…" : "Import & republish"}
          </button>
          <label className="flex items-center gap-2 text-xs text-mute">
            <input
              type="checkbox"
              checked={replace}
              onChange={(e) => setReplace(e.target.checked)}
              className="accent-gold"
            />
            Replace all existing content
          </label>
          {result?.ok && (
            <span className="text-xs text-gold">
              Imported {result.units} units · {result.lessons} lessons ·{" "}
              {result.steps} steps.
            </span>
          )}
          {result && !result.ok && (
            <span className="text-xs text-bad">{result.error}</span>
          )}
        </div>

        <div className="rounded-lg border border-dashed border-line bg-panel2 p-3">
          <div className="mb-2 flex items-center gap-2">
            <span className="text-[11px] uppercase tracking-wider text-faint">
              Format &amp; example
            </span>
            <button
              onClick={() => setJson(EXAMPLE_TEXT)}
              className={btnGhost + " ml-auto"}
            >
              Use this example
            </button>
            <button
              onClick={() => navigator.clipboard.writeText(EXAMPLE_TEXT)}
              className={btnGhost}
            >
              Copy
            </button>
          </div>
          <p className="mb-2 text-[11px] leading-relaxed text-mute">
            Prompt your AI to output exactly this shape. Step{" "}
            <code className="text-faint">kind</code> is{" "}
            <code className="text-faint">explainer</code>,{" "}
            <code className="text-faint">interactive</code>,{" "}
            <code className="text-faint">quiz</code>,{" "}
            <code className="text-faint">image</code> or{" "}
            <code className="text-faint">chart</code> (bars · line · growth); an
            explainer may also carry an inline{" "}
            <code className="text-faint">image</code> or{" "}
            <code className="text-faint">chart</code>. A lesson&rsquo;s{" "}
            <code className="text-faint">fund_id</code> (optional) lights up the
            live badge.
          </p>
          <pre className="max-h-64 overflow-auto rounded-md bg-panel px-3 py-2 font-mono text-[11px] leading-relaxed text-mute">
{EXAMPLE_TEXT}
          </pre>
        </div>
      </div>
    </details>
  );
}

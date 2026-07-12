"use client";

import { useState } from "react";
import {
  type Field,
  type Model,
  type RateModel,
  type TableModel,
  validate,
} from "./schema";
import { CADENCE, CONSTANT_KEYS, CONSUMERS, freshness, groupTone, KIND_LABEL } from "./config-meta";
import { computeImpact, type Board } from "./impact";
import { IconPlus, IconX } from "../_icons";

const fieldCls =
  "w-full rounded-lg border border-line bg-panel2 px-3 py-2 text-[12.5px] text-ink outline-none focus:border-gold";
const microLabel = "mb-1.5 block text-[10px] font-semibold uppercase tracking-wider text-faint";

function Arrow() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}
function Phone() {
  return (
    <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}>
      <rect x="5" y="2" width="14" height="20" rx="3" />
      <path d="M11 18h2" />
    </svg>
  );
}
function Window() {
  return (
    <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M2 9h20" />
    </svg>
  );
}

function SectionHead({ title, note, tone }: { title: string; note: string; tone: string }) {
  return (
    <div className="mb-3 flex items-center gap-2.5">
      <span className={"text-[10px] font-bold uppercase tracking-widest " + tone}>{title}</span>
      <span className="text-[11.5px] text-faint">{note}</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

/* ── editors ──────────────────────────────────────────────────────────── */

function RateEditor({
  field,
  model,
  published,
  tone,
  onChange,
}: {
  field: Field;
  model: RateModel;
  published: RateModel;
  tone: { text: string; bg: string; border: string; solid: string };
  onChange: (m: Model) => void;
}) {
  const dated = field.kind === "rate" && field.showMeta !== false;
  const changed = model.rate.trim() !== published.rate.trim();

  return (
    <div
      className={
        "grid gap-6 rounded-xl border p-5 md:grid-cols-[auto_1fr] md:items-end " +
        (changed ? `${tone.border} ${tone.bg}` : "border-line bg-panel")
      }
    >
      <div>
        <div className="flex items-baseline gap-1.5">
          <input
            inputMode="decimal"
            value={model.rate}
            onChange={(e) => onChange({ ...model, rate: e.target.value })}
            className={
              "w-[150px] border-0 border-b-2 border-line2 bg-transparent pb-1 font-mono text-[40px] font-semibold tracking-tight tnum text-ink outline-none focus:" +
              tone.border.replace("border-", "border-b-")
            }
          />
          <span className={"font-mono text-[22px] font-semibold " + tone.text}>%</span>
        </div>
        <div className="mt-2 font-mono text-[11.5px] text-faint">
          {changed ? (
            <>
              published <span className="line-through">{published.rate || "unset"}</span>, staged{" "}
              <b className={"font-semibold " + tone.text}>{model.rate || "empty"}</b>
            </>
          ) : (
            <>published {published.rate || "unset"}, unchanged</>
          )}
        </div>
      </div>

      {dated && (
        <div className="grid gap-3 md:grid-cols-2">
          <div>
            <label className={microLabel}>As of</label>
            <input
              type="date"
              value={model.as_of}
              onChange={(e) => onChange({ ...model, as_of: e.target.value })}
              className={fieldCls + " font-mono"}
            />
          </div>
          <div>
            <label className={microLabel}>Source</label>
            <input
              value={model.source}
              onChange={(e) => onChange({ ...model, source: e.target.value })}
              placeholder="CBK auction"
              className={fieldCls}
            />
          </div>
        </div>
      )}
    </div>
  );
}

function FlagEditor({ model, onChange }: { model: boolean; onChange: (m: Model) => void }) {
  return (
    <div className="flex items-center gap-4 rounded-xl border border-line bg-panel p-5">
      <button
        type="button"
        role="switch"
        aria-checked={model}
        onClick={() => onChange(!model)}
        className={
          "relative h-7 w-12 flex-none rounded-full border transition-colors " +
          (model ? "border-violet/60 bg-violet/80" : "border-line bg-panel2")
        }
      >
        <span
          className={
            "absolute top-[3px] h-5 w-5 rounded-full transition-all " +
            (model ? "left-[25px] bg-ink" : "left-[3px] bg-faint")
          }
        />
      </button>
      <div>
        <div className={"text-sm font-semibold " + (model ? "text-ink" : "text-mute")}>
          {model ? "On" : "Off"}
        </div>
        <div className="text-[11.5px] text-faint">
          {model ? "The surfaces below are visible in the app." : "The surfaces below are hidden."}
        </div>
      </div>
    </div>
  );
}

function TextEditor({ field, model, onChange }: { field: Field; model: string; onChange: (m: Model) => void }) {
  const multi = field.kind === "text" && field.multiline;
  return (
    <div className="rounded-xl border border-line bg-panel p-5">
      {multi ? (
        <textarea rows={3} value={model} onChange={(e) => onChange(e.target.value)} className={fieldCls} />
      ) : (
        <input value={model} onChange={(e) => onChange(e.target.value)} className={fieldCls + " text-[15px]"} />
      )}
    </div>
  );
}

function ChipsEditor({ model, onChange }: { model: string[]; onChange: (m: Model) => void }) {
  const [draft, setDraft] = useState("");
  const add = () => {
    const t = draft.trim();
    if (!t) return;
    onChange([...model, t]);
    setDraft("");
  };
  return (
    <div className="rounded-xl border border-line bg-panel p-5">
      <div className="mb-3 flex flex-wrap gap-2">
        {model.length === 0 && <span className="text-xs text-faint">No chips yet.</span>}
        {model.map((s, i) => (
          <span
            key={`${s}-${i}`}
            className="flex items-center gap-2 rounded-full border border-line bg-panel2 py-1 pl-3 pr-2 text-xs text-ink"
          >
            {s}
            <button
              type="button"
              onClick={() => onChange(model.filter((_, j) => j !== i))}
              aria-label={`Remove ${s}`}
              className="text-faint hover:text-bad"
            >
              <IconX size={12} />
            </button>
          </span>
        ))}
      </div>
      <div className="flex gap-2">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              add();
            }
          }}
          placeholder="Add a chip, press Enter"
          className={fieldCls + " max-w-[240px]"}
        />
        <button
          type="button"
          onClick={add}
          className="flex items-center gap-1.5 rounded-lg border border-line bg-panel2 px-3 text-xs text-mute hover:text-ink"
        >
          <IconPlus size={13} /> Add
        </button>
      </div>
    </div>
  );
}

function TableEditor({
  field,
  model,
  onChange,
}: {
  field: Field & { kind: "table" };
  model: TableModel;
  onChange: (m: Model) => void;
}) {
  const cols = field.columns;
  const setCell = (i: number, k: string, v: string) =>
    onChange({ ...model, rows: model.rows.map((r, j) => (j === i ? { ...r, [k]: v } : r)) });
  const addRow = () => {
    const blank: Record<string, string> = {};
    for (const c of cols) blank[c.key] = "";
    onChange({ ...model, rows: [...model.rows, blank] });
  };

  return (
    <div className="overflow-hidden rounded-xl border border-line bg-panel">
      <div className="grid gap-3 border-b border-line p-4 md:grid-cols-2">
        <div>
          <label className={microLabel}>As of</label>
          <input
            type="date"
            value={model.as_of}
            onChange={(e) => onChange({ ...model, as_of: e.target.value })}
            className={fieldCls + " font-mono"}
          />
        </div>
        <div>
          <label className={microLabel}>Source</label>
          <input
            value={model.source}
            onChange={(e) => onChange({ ...model, source: e.target.value })}
            placeholder="CMA CIS Quarterly Report Q1 2026"
            className={fieldCls}
          />
        </div>
      </div>

      <table className="w-full">
        <thead>
          <tr className="bg-raise">
            {cols.map((c) => (
              <th
                key={c.key}
                className={
                  "border-b border-line px-3 py-2 text-[10px] font-semibold uppercase tracking-wider text-faint " +
                  (c.type === "number" ? "text-right" : "text-left")
                }
              >
                {c.label}
              </th>
            ))}
            <th className="w-9 border-b border-line" />
          </tr>
        </thead>
        <tbody>
          {model.rows.map((r, i) => (
            <tr key={i} className="border-b border-line last:border-0">
              {cols.map((c) => (
                <td key={c.key} className="p-1">
                  <input
                    inputMode={c.type === "number" ? "decimal" : "text"}
                    value={r[c.key] ?? ""}
                    onChange={(e) => setCell(i, c.key, e.target.value)}
                    className={
                      "w-full rounded-md border border-transparent bg-transparent px-2 py-1.5 text-ink outline-none hover:border-line focus:border-gold focus:bg-panel2 " +
                      (c.type === "number" ? "text-right font-mono text-xs tnum" : "text-[13px]")
                    }
                  />
                </td>
              ))}
              <td className="text-center">
                <button
                  type="button"
                  onClick={() => onChange({ ...model, rows: model.rows.filter((_, j) => j !== i) })}
                  aria-label={`Remove row ${i + 1}`}
                  className="text-faint hover:text-bad"
                >
                  <IconX size={12} />
                </button>
              </td>
            </tr>
          ))}
          {model.rows.length === 0 && (
            <tr>
              <td colSpan={cols.length + 1} className="px-3 py-4 text-center text-xs text-faint">
                No rows yet.
              </td>
            </tr>
          )}
        </tbody>
      </table>

      <div className="border-t border-line bg-raise px-4 py-2.5">
        <button
          type="button"
          onClick={addRow}
          className="flex items-center gap-1.5 rounded-md border border-line bg-panel2 px-2.5 py-1 text-xs text-mute hover:text-ink"
        >
          <IconPlus size={13} /> {field.addLabel}
        </button>
      </div>
    </div>
  );
}

function JsonEditor({ model, onChange }: { model: string; onChange: (m: Model) => void }) {
  return (
    <div className="rounded-xl border border-line bg-panel p-5">
      <textarea
        rows={7}
        spellCheck={false}
        value={model}
        onChange={(e) => onChange(e.target.value)}
        className={fieldCls + " font-mono text-xs"}
      />
    </div>
  );
}

/* ── detail pane ──────────────────────────────────────────────────────── */

export function Detail({
  configKey,
  field,
  published,
  model,
  isNew,
  updatedAt,
  board,
  onChange,
  onReset,
  onDelete,
}: {
  configKey: string;
  field: Field;
  published: unknown;
  model: Model;
  isNew: boolean;
  updatedAt: string | null;
  board: Board;
  onChange: (m: Model) => void;
  onReset: () => void;
  onDelete: () => void;
}) {
  const tone = groupTone(field.group);
  const asOf =
    field.kind === "rate" || field.kind === "table"
      ? ((model as RateModel | TableModel).as_of || null)
      : null;
  const fresh = freshness(configKey, asOf);
  const cad = CADENCE[configKey];
  const v = validate(field, model);
  const impact = computeImpact(configKey, field, published, model, board);
  const consumers = CONSUMERS[configKey] ?? [];

  const freshBadge = () => {
    if (fresh.kind === "constant")
      return <span className="rounded-md border border-line px-2 py-1 font-mono text-[11px] text-faint">policy constant</span>;
    if (fresh.kind === "undated") return null;
    const tone =
      fresh.kind === "stale" ? "border-bad/40 text-bad" : fresh.kind === "due" ? "border-warn/40 text-warn" : "border-line text-mute";
    const dotTone = fresh.kind === "stale" ? "bg-bad" : fresh.kind === "due" ? "bg-warn" : "bg-live";
    return (
      <span className={"inline-flex items-center gap-1.5 rounded-md border px-2 py-1 font-mono text-[11px] " + tone}>
        <span className={"h-1.5 w-1.5 rounded-full " + dotTone} />
        {fresh.days} days old
      </span>
    );
  };

  return (
    <div className="max-w-[820px] px-7 py-6 pb-16">
      <div className="mb-6 flex items-start gap-4">
        <div className="min-w-0">
          <div className="mb-2 flex items-center gap-2">
            <span
              className={
                "inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider " +
                `${tone.border} ${tone.bg} ${tone.text}`
              }
            >
              <span className={"h-1.5 w-1.5 rounded-full " + tone.solid} />
              {field.group}
            </span>
            <span className="rounded-md border border-line bg-panel2 px-2 py-0.5 font-mono text-[10px] text-faint">
              {KIND_LABEL[field.kind] ?? field.kind}
            </span>
          </div>
          <h2 className="text-xl font-semibold tracking-tight text-ink">{field.label}</h2>
          <div className="mt-1 font-mono text-[11.5px] text-faint">{configKey}</div>
          {field.help && <p className="mt-3 max-w-[62ch] text-[13px] leading-relaxed text-mute">{field.help}</p>}
          {cad && <p className="mt-1.5 text-[11.5px] text-faint">{cad.note}.</p>}
        </div>
        <div className="ml-auto flex flex-none flex-col items-end gap-2">
          {freshBadge()}
          {isNew && (
            <span className="rounded-md border border-line px-2 py-1 font-mono text-[11px] text-faint">not set</span>
          )}
        </div>
      </div>

      {field.kind === "rate" && (
        <RateEditor
          field={field}
          tone={tone}
          model={model as RateModel}
          published={
            (published && typeof published === "object"
              ? { rate: String((published as { rate?: unknown }).rate ?? ""), as_of: "", source: "" }
              : { rate: "", as_of: "", source: "" }) as RateModel
          }
          onChange={onChange}
        />
      )}
      {field.kind === "flag" && <FlagEditor model={model as boolean} onChange={onChange} />}
      {field.kind === "text" && <TextEditor field={field} model={model as string} onChange={onChange} />}
      {field.kind === "stringList" && <ChipsEditor model={model as string[]} onChange={onChange} />}
      {field.kind === "table" && <TableEditor field={field} model={model as TableModel} onChange={onChange} />}
      {field.kind === "json" && <JsonEditor model={model as string} onChange={onChange} />}

      {!v.ok && <p className="mt-2.5 text-xs text-bad">{v.msg}</p>}
      {v.warn && <p className="mt-2.5 text-xs text-warn">{v.warn}</p>}

      {impact.length > 0 && (
        <section className="mt-7">
          <SectionHead title="Impact" note="What this value recomputes, live, as you type" tone={tone.text} />
          <div className="overflow-hidden rounded-xl border border-line bg-panel">
            {impact.map((r) => (
              <div
                key={r.label}
                className="grid grid-cols-[1fr_100px_20px_100px] items-center gap-3 border-b border-line px-4 py-2.5 last:border-0"
              >
                <div className="min-w-0">
                  <div className="text-[12.5px] font-medium text-ink">{r.label}</div>
                  <div className="mt-0.5 text-[11px] text-faint">{r.sub}</div>
                </div>
                <div className="text-right font-mono text-sm text-faint">{r.before}</div>
                <div className="grid place-items-center text-line2">
                  <Arrow />
                </div>
                <div
                  className={
                    "text-right font-mono text-sm font-semibold " +
                    (r.dir === "up" ? "text-live" : r.dir === "down" ? "text-bad" : "text-mute")
                  }
                >
                  {r.after}
                </div>
              </div>
            ))}
            <div className="flex items-center gap-2 border-t border-line bg-raise px-4 py-2.5 text-[11.5px] text-faint">
              Recomputed against the live board. Nothing changes for users until you publish.
            </div>
          </div>
        </section>
      )}

      {consumers.length > 0 && (
        <section className="mt-7">
          <SectionHead title="Read by" note="Every surface that changes when this publishes" tone="text-blue" />
          <div className="flex flex-wrap gap-2">
            {consumers.map((c) => (
              <span
                key={c.surface + c.where}
                className={
                  "inline-flex items-center gap-2 rounded-lg border bg-panel px-2.5 py-1.5 text-xs text-mute " +
                  (c.surface === "App" ? "border-violet/30" : "border-blue/30")
                }
              >
                <span className={c.surface === "App" ? "text-violet" : "text-blue"}>
                  {c.surface === "App" ? <Phone /> : <Window />}
                </span>
                {c.surface} <b className="font-medium text-ink">{c.where}</b>
              </span>
            ))}
          </div>
        </section>
      )}

      <div className="mt-7 flex items-center gap-3 rounded-xl border border-line px-4 py-3">
        <span className="flex-1 text-xs text-mute">
          {isNew
            ? "This key is not in the database, so the app uses the value baked into the build."
            : "Deleting this key makes the app fall back to the value baked into the build."}
          {updatedAt && !isNew && (
            <span className="ml-1.5 font-mono text-[11px] text-faint">
              last published {new Date(updatedAt).toLocaleDateString()}
            </span>
          )}
        </span>
        <button
          type="button"
          onClick={onReset}
          className="rounded-md border border-line2 px-2.5 py-1.5 text-[11.5px] text-faint hover:text-ink"
        >
          Reset
        </button>
        {!isNew && (
          <button
            type="button"
            onClick={onDelete}
            className="rounded-md border border-line2 px-2.5 py-1.5 text-[11.5px] text-faint hover:border-bad hover:text-bad"
          >
            Delete key
          </button>
        )}
      </div>
    </div>
  );
}

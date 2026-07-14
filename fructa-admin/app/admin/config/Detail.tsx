"use client";

import { useState } from "react";
import {
  type Field,
  type Model,
  type RateModel,
  type TableModel,
  validate,
} from "./schema";
import {
  CONSUMERS,
  KIND_LABEL,
  agePosition,
  cadenceRule,
  freshPill,
  freshness,
} from "./config-meta";
import { computeImpact, type Board } from "./impact";
import { IconPlus, IconX } from "../_icons";

/* The detail pane answers the operator's questions in the order they actually
 * arrive: what is this, can I trust it, what is it, what breaks, who reads it,
 * how do I back out. Provenance sits ABOVE the value on purpose. You should not
 * be able to read 8.71% without first reading that the print is 27 days old. */

const fieldCls =
  "w-full rounded-lg border border-line bg-panel2 px-3 py-2 text-[12.5px] text-ink outline-none placeholder:text-faint focus:border-gold";
const microLabel = "mb-1.5 block text-[10px] font-semibold uppercase tracking-wider text-faint";

function Arrow() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}
function PhoneIcon() {
  return (
    <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}>
      <rect x="5" y="2" width="14" height="20" rx="3" />
      <path d="M11 18h2" />
    </svg>
  );
}
function WindowIcon() {
  return (
    <svg width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M2 9h20" />
    </svg>
  );
}

/** The one mark that means "staged". A bar, never a dot, so it can never be
 *  mistaken for a freshness state. */
function StagedTag() {
  return (
    <span className="inline-flex flex-none items-center gap-1.5 rounded-md bg-gold px-1.5 py-0.5 font-mono text-[10px] font-bold uppercase tracking-wider text-[#191204]">
      <span className="h-2.5 w-[3px] rounded-sm bg-[#191204]" />
      staged
    </span>
  );
}

function SectionHead({ title, note }: { title: string; note: string }) {
  return (
    <div className="mb-2.5 flex items-center gap-2.5">
      <span className="text-[10px] font-bold uppercase tracking-widest text-mute">{title}</span>
      <span className="text-[11.5px] text-faint">{note}</span>
      <span className="h-px flex-1 bg-line" />
    </div>
  );
}

/* ── editors ──────────────────────────────────────────────────────────── */

function RateEditor({
  model,
  publishedRate,
  onChange,
}: {
  model: RateModel;
  publishedRate: string;
  onChange: (m: Model) => void;
}) {
  const changed = model.rate.trim() !== publishedRate.trim();
  return (
    <div className={"rounded-xl border p-5 " + (changed ? "border-gold/45 bg-panel" : "border-line bg-panel")}>
      <div className="flex items-start gap-5">
        <div>
          <div className="flex items-baseline gap-1">
            <input
              inputMode="decimal"
              value={model.rate}
              onChange={(e) => onChange({ ...model, rate: e.target.value })}
              className="w-[150px] border-0 border-b-2 border-line2 bg-transparent pb-1 font-mono text-[42px] font-semibold tracking-tight tnum text-ink outline-none focus:border-b-gold"
            />
            <span className="font-mono text-[22px] font-semibold text-faint">%</span>
          </div>
          <div className="mt-2 font-mono text-[11.5px] text-faint">
            {changed ? (
              <>
                published <span className="line-through">{publishedRate || "unset"}</span>, staged{" "}
                <b className="font-semibold text-gold">{model.rate || "empty"}</b>
              </>
            ) : (
              <>published {publishedRate || "unset"}, unchanged</>
            )}
          </div>
        </div>
        {changed && <span className="ml-auto"><StagedTag /></span>}
      </div>
    </div>
  );
}

function FlagEditor({
  model,
  changed,
  onChange,
}: {
  model: boolean;
  changed: boolean;
  onChange: (m: Model) => void;
}) {
  return (
    <div className={"flex items-center gap-4 rounded-xl border p-5 " + (changed ? "border-gold/45 bg-panel" : "border-line bg-panel")}>
      <button
        type="button"
        role="switch"
        aria-checked={model}
        onClick={() => onChange(!model)}
        className={
          "relative h-7 w-12 flex-none rounded-full border transition-colors " +
          (model ? "border-live/50 bg-live/75" : "border-line bg-panel2")
        }
      >
        <span
          className={
            "absolute top-[3px] h-5 w-5 rounded-full transition-all " +
            (model ? "left-[23px] bg-ink" : "left-[3px] bg-faint")
          }
        />
      </button>
      <div>
        <div className={"text-sm font-semibold " + (model ? "text-ink" : "text-mute")}>{model ? "On" : "Off"}</div>
        <div className="text-[11.5px] text-faint">
          {model ? "The surfaces below are visible in the app." : "The surfaces below are hidden."}
        </div>
      </div>
      {changed && <span className="ml-auto"><StagedTag /></span>}
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

  const shareCol = cols.find((c) => c.suffix === "%");
  const shareSum = shareCol ? model.rows.reduce((s, r) => s + Number(r[shareCol.key] || 0), 0) : null;
  const total = field.totalFromColumn
    ? model.rows.reduce((s, r) => s + Number(r[field.totalFromColumn!] || 0), 0)
    : null;

  return (
    <div className="overflow-hidden rounded-xl border border-line bg-panel">
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

      <div className="flex items-center gap-3 border-t border-line bg-raise px-3 py-2.5">
        <button
          type="button"
          onClick={addRow}
          className="flex items-center gap-1.5 rounded-md border border-line2 bg-panel2 px-2.5 py-1 text-xs text-mute hover:text-ink"
        >
          <IconPlus size={13} /> {field.addLabel}
        </button>
        <span className="ml-auto font-mono text-[11.5px] text-faint">
          {total != null && <>Total {(total / 1e9).toFixed(1)}B</>}
          {total != null && shareSum != null && " · "}
          {shareSum != null && (
            <span className={Math.abs(shareSum - 100) > 0.5 ? "text-warn" : undefined}>
              shares {shareSum.toFixed(1)}%
            </span>
          )}
        </span>
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

/* ── provenance ───────────────────────────────────────────────────────── */

function Provenance({
  configKey,
  model,
  onChange,
  sourceHint,
}: {
  configKey: string;
  model: RateModel | TableModel;
  onChange: (m: Model) => void;
  sourceHint: string;
}) {
  const fresh = freshness(configKey, model.as_of || null);
  const rule = cadenceRule(configKey);
  const pos = agePosition(configKey, fresh);
  const meterTone = fresh.kind === "stale" ? "bg-bad" : fresh.kind === "due" ? "bg-warn" : "bg-live";
  const daysTone = fresh.kind === "stale" ? "text-bad" : fresh.kind === "due" ? "text-warn" : "text-faint";

  return (
    <div className="rounded-xl border border-line bg-panel">
      <div className="grid gap-3.5 p-4 md:grid-cols-[150px_1fr]">
        <div>
          <label className={microLabel}>As of</label>
          <input
            type="date"
            value={model.as_of}
            onChange={(e) => onChange({ ...model, as_of: e.target.value } as Model)}
            className={fieldCls + " font-mono"}
          />
        </div>
        <div>
          <label className={microLabel}>Source</label>
          <input
            value={model.source}
            onChange={(e) => onChange({ ...model, source: e.target.value } as Model)}
            placeholder={sourceHint}
            className={fieldCls}
          />
        </div>
      </div>
      {rule && (
        <div className="flex items-center gap-2.5 border-t border-line px-4 py-2.5 text-[11.5px] text-faint">
          <span>{rule}</span>
          {pos != null && (
            <>
              <span className="h-[3px] w-full max-w-[200px] overflow-hidden rounded-sm bg-line2">
                <span className={"block h-full rounded-sm " + meterTone} style={{ width: `${Math.round(pos * 100)}%` }} />
              </span>
              <span className={"font-mono " + daysTone}>
                {fresh.kind === "ok" || fresh.kind === "due" || fresh.kind === "stale" ? `${fresh.days}d` : ""}
              </span>
            </>
          )}
          {!model.as_of && <span className="ml-auto text-warn">No date set, freshness cannot be judged.</span>}
        </div>
      )}
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
  dirty,
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
  dirty: boolean;
  onChange: (m: Model) => void;
  onReset: () => void;
  onDelete: () => void;
}) {
  const dated =
    (field.kind === "rate" && field.showMeta !== false) || field.kind === "table";
  const asOf = dated ? ((model as RateModel | TableModel).as_of || null) : null;
  const fresh = freshness(configKey, asOf);
  const pill = freshPill(fresh);
  const v = validate(field, model);
  const impact = computeImpact(configKey, field, published, model, board);
  const consumers = CONSUMERS[configKey] ?? [];
  const app = consumers.filter((c) => c.surface === "App");
  const landing = consumers.filter((c) => c.surface === "Landing");

  const publishedRate =
    published && typeof published === "object"
      ? String((published as { rate?: unknown }).rate ?? "")
      : "";

  const valueNote = dirty ? "Staged, not published" : isNew ? "Not set, the app uses its baked-in value" : "Published";

  return (
    <div className="max-w-[800px] px-7 py-6 pb-20">
      {/* 1. what is this */}
      <div className="mb-6 flex items-start gap-4">
        <div className="min-w-0">
          <div className="mb-2 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-faint">
            <span>{field.group}</span>
            <span className="text-line2">/</span>
            <span className="rounded border border-line bg-panel2 px-1.5 py-px font-mono text-[10px] normal-case tracking-normal text-faint">
              {KIND_LABEL[field.kind] ?? field.kind}
            </span>
          </div>
          <h2 className="text-[21px] font-semibold tracking-tight text-ink">{field.label}</h2>
          <div className="mt-0.5 font-mono text-[11.5px] text-faint">{configKey}</div>
          {field.help && <p className="mt-3 max-w-[62ch] text-[13px] leading-relaxed text-mute">{field.help}</p>}
        </div>
        <div className="ml-auto flex flex-none flex-col items-end gap-2">
          {pill && (
            <span className={"inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 font-mono text-[11px] " + pill.cls}>
              {fresh.kind !== "constant" && (
                <span
                  className={
                    "h-1.5 w-1.5 rounded-full " +
                    (fresh.kind === "stale" ? "bg-bad" : fresh.kind === "due" ? "bg-warn" : "bg-live")
                  }
                />
              )}
              {pill.label}
            </span>
          )}
          {isNew && (
            <span className="rounded-lg border border-line px-2.5 py-1.5 font-mono text-[11px] text-faint">not set</span>
          )}
        </div>
      </div>

      {/* 2. can I trust it */}
      {dated && (
        <section className="mt-6">
          <SectionHead title="Provenance" note="Where this came from, and when" />
          <Provenance
            configKey={configKey}
            model={model as RateModel | TableModel}
            onChange={onChange}
            sourceHint={field.kind === "table" ? "CMA CIS Quarterly Report Q1 2026" : "CBK auction"}
          />
        </section>
      )}

      {/* 3. what is it */}
      <section className="mt-6">
        <SectionHead title="Value" note={valueNote} />
        {field.kind === "rate" && (
          <RateEditor model={model as RateModel} publishedRate={publishedRate} onChange={onChange} />
        )}
        {field.kind === "flag" && (
          <FlagEditor model={model as boolean} changed={dirty} onChange={onChange} />
        )}
        {field.kind === "text" && <TextEditor field={field} model={model as string} onChange={onChange} />}
        {field.kind === "stringList" && <ChipsEditor model={model as string[]} onChange={onChange} />}
        {field.kind === "table" && <TableEditor field={field} model={model as TableModel} onChange={onChange} />}
        {field.kind === "json" && <JsonEditor model={model as string} onChange={onChange} />}

        {!v.ok && <p className="mt-2.5 text-xs text-bad">{v.msg}</p>}
        {v.warn && <p className="mt-2.5 text-xs text-warn">{v.warn}</p>}
      </section>

      {/* 4. what breaks. Always rendered: an empty impact box is information. */}
      <section className="mt-7">
        <SectionHead title="Impact" note="Recomputed live against the board, before you publish" />
        <div className="overflow-hidden rounded-xl border border-line bg-panel">
          {impact.length === 0 ? (
            <p className="px-4 py-4 text-[12.5px] text-faint">
              {dirty
                ? "Nothing derived in the app changes with this edit."
                : "No staged edit. Change the value to see what moves."}
            </p>
          ) : (
            <>
              {impact.map((r) => (
                <div
                  key={r.label}
                  className="grid grid-cols-[1fr_96px_22px_96px] items-center gap-3 border-b border-line px-4 py-2.5 last:border-0"
                >
                  <div className="min-w-0">
                    <div className="text-[12.5px] font-medium text-ink">{r.label}</div>
                    <div className="mt-0.5 text-[11px] text-faint">{r.sub}</div>
                  </div>
                  <div className="text-right font-mono text-[13.5px] text-faint">{r.before}</div>
                  <div className="grid place-items-center text-line2">
                    <Arrow />
                  </div>
                  <div
                    className={
                      "text-right font-mono text-[13.5px] font-semibold " +
                      (r.dir === "up" ? "text-live" : r.dir === "down" ? "text-bad" : "text-mute")
                    }
                  >
                    {r.after}
                  </div>
                </div>
              ))}
              <div className="border-t border-line bg-raise px-4 py-2.5 text-[11.5px] text-faint">
                Nothing changes for users until you publish.
              </div>
            </>
          )}
        </div>
      </section>

      {/* 5. who reads it */}
      {consumers.length > 0 && (
        <section className="mt-7">
          <SectionHead title="Read by" note={`${consumers.length} surface${consumers.length === 1 ? "" : "s"}`} />
          <div className="grid gap-2.5 md:grid-cols-2">
            {[
              { name: "App", icon: <PhoneIcon />, list: app },
              { name: "Landing", icon: <WindowIcon />, list: landing },
            ]
              .filter((s) => s.list.length > 0)
              .map((s) => (
                <div key={s.name} className="rounded-xl border border-line bg-panel p-3.5">
                  <div className="mb-2.5 flex items-center gap-2 text-[10px] font-bold uppercase tracking-widest text-faint">
                    {s.icon}
                    {s.name}
                  </div>
                  <ul className="flex flex-col gap-1.5">
                    {s.list.map((c) => (
                      <li key={c.where} className="flex items-center gap-2 text-[12.5px] text-mute">
                        <span className="h-[3px] w-[3px] flex-none rounded-full bg-line2" />
                        {c.where}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
          </div>
        </section>
      )}

      {/* 6. how do I back out */}
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
          disabled={!dirty}
          className="rounded-md border border-line2 px-2.5 py-1.5 text-[11.5px] text-faint hover:text-ink disabled:opacity-40"
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

"use client";

import { useMemo, useState, useTransition } from "react";
import { upsertConfig, deleteConfig } from "./actions";
import { IconPlus, IconX } from "../_icons";
import {
  type Field,
  type Model,
  type RateModel,
  type TableModel,
  defaultModel,
  parseModel,
  serializeValue,
  validate,
} from "./schema";

// ── shared field styles ─────────────────────────────────────────────────────

const fieldCls =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const monoCls = fieldCls + " font-mono text-xs";
const microLabel = "mb-1 block text-[10px] uppercase tracking-wider text-faint";

// ── individual editors ──────────────────────────────────────────────────────
// Each is controlled: it owns its model and reports the serialized string up.

interface EditorProps {
  field: Field;
  model: Model;
  onChange: (model: Model) => void;
}

function RateEditor({ field, model, onChange }: EditorProps) {
  const m = model as RateModel;
  const showMeta = field.kind === "rate" && field.showMeta !== false;
  return (
    <div className="space-y-3">
      <div className="max-w-[180px]">
        <label className={microLabel}>Rate</label>
        <div className="relative">
          <input
            inputMode="decimal"
            value={m.rate}
            onChange={(e) => onChange({ ...m, rate: e.target.value })}
            placeholder="0.00"
            className={fieldCls + " pr-7 font-mono tnum"}
          />
          <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm text-faint">%</span>
        </div>
      </div>
      {showMeta && (
        <div className="flex flex-wrap gap-3">
          <div>
            <label className={microLabel}>As of</label>
            <input
              type="date"
              value={m.as_of}
              onChange={(e) => onChange({ ...m, as_of: e.target.value })}
              className={fieldCls + " w-[150px]"}
            />
          </div>
          <div className="min-w-[180px] flex-1">
            <label className={microLabel}>Source</label>
            <input
              value={m.source}
              onChange={(e) => onChange({ ...m, source: e.target.value })}
              placeholder="e.g. CBK auction"
              className={fieldCls}
            />
          </div>
        </div>
      )}
    </div>
  );
}

function FlagEditor({ model, onChange }: EditorProps) {
  const on = model as boolean;
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      onClick={() => onChange(!on)}
      className="flex items-center gap-3"
    >
      <span
        className={
          "relative h-6 w-11 rounded-full border transition-colors " +
          (on ? "border-gold/60 bg-gold/80" : "border-line bg-panel2")
        }
      >
        <span
          className={
            "absolute top-0.5 h-4 w-4 rounded-full bg-ink transition-all " + (on ? "left-[22px]" : "left-0.5")
          }
        />
      </span>
      <span className={"text-sm font-medium " + (on ? "text-ink" : "text-mute")}>{on ? "On" : "Off"}</span>
    </button>
  );
}

function TextEditor({ field, model, onChange }: EditorProps) {
  const multiline = field.kind === "text" && field.multiline;
  const v = model as string;
  return multiline ? (
    <textarea rows={3} value={v} onChange={(e) => onChange(e.target.value)} className={fieldCls} />
  ) : (
    <input value={v} onChange={(e) => onChange(e.target.value)} className={fieldCls} />
  );
}

function StringListEditor({ model, onChange }: EditorProps) {
  const items = model as string[];
  const [draft, setDraft] = useState("");
  const add = () => {
    const t = draft.trim();
    if (!t) return;
    onChange([...items, t]);
    setDraft("");
  };
  return (
    <div>
      <div className="mb-2 flex flex-wrap gap-2">
        {items.length === 0 && <span className="text-xs text-faint">No chips yet — add one below.</span>}
        {items.map((s, i) => (
          <span key={i} className="flex items-center gap-1.5 rounded-full border border-line bg-panel2 py-1 pl-3 pr-2 text-xs text-ink">
            {s}
            <button
              type="button"
              onClick={() => onChange(items.filter((_, j) => j !== i))}
              className="text-faint hover:text-bad"
              aria-label={`Remove ${s}`}
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
          className="flex items-center gap-1 rounded-md border border-line bg-panel2 px-2.5 text-xs text-mute hover:text-ink"
        >
          <IconPlus size={13} /> Add
        </button>
      </div>
    </div>
  );
}

function TableEditor({ field, model, onChange }: EditorProps) {
  if (field.kind !== "table") return null;
  const m = model as TableModel;
  const cols = field.columns;

  const setCell = (row: number, key: string, val: string) => {
    const rows = m.rows.map((r, i) => (i === row ? { ...r, [key]: val } : r));
    onChange({ ...m, rows });
  };
  const addRow = () => {
    const blank: Record<string, string> = {};
    for (const c of cols) blank[c.key] = "";
    onChange({ ...m, rows: [...m.rows, blank] });
  };
  const removeRow = (i: number) => onChange({ ...m, rows: m.rows.filter((_, j) => j !== i) });

  const shareCol = cols.find((c) => c.suffix === "%");
  const shareSum = shareCol ? m.rows.reduce((s, r) => s + Number(r[shareCol.key] || 0), 0) : null;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-3">
        <div>
          <label className={microLabel}>As of</label>
          <input
            type="date"
            value={m.as_of}
            onChange={(e) => onChange({ ...m, as_of: e.target.value })}
            className={fieldCls + " w-[150px]"}
          />
        </div>
        <div className="min-w-[200px] flex-1">
          <label className={microLabel}>Source</label>
          <input
            value={m.source}
            onChange={(e) => onChange({ ...m, source: e.target.value })}
            placeholder="e.g. CMA CIS Q1 2026"
            className={fieldCls}
          />
        </div>
      </div>

      <div className="overflow-hidden rounded-md border border-line">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-line bg-panel2">
              {cols.map((c) => (
                <th key={c.key} className="px-2 py-1.5 text-left text-[10px] uppercase tracking-wider text-faint">
                  {c.label}
                </th>
              ))}
              <th className="w-8" />
            </tr>
          </thead>
          <tbody>
            {m.rows.map((r, i) => (
              <tr key={i} className="border-b border-line last:border-0">
                {cols.map((c) => (
                  <td key={c.key} className="px-1.5 py-1">
                    <input
                      inputMode={c.type === "number" ? "decimal" : "text"}
                      value={r[c.key] ?? ""}
                      onChange={(e) => setCell(i, c.key, e.target.value)}
                      className={
                        "w-full rounded border border-transparent bg-transparent px-1.5 py-1 text-ink outline-none focus:border-line focus:bg-panel2 " +
                        (c.type === "number" ? "font-mono tnum text-xs" : "text-sm")
                      }
                    />
                  </td>
                ))}
                <td className="px-1 text-center">
                  <button
                    type="button"
                    onClick={() => removeRow(i)}
                    className="text-faint hover:text-bad"
                    aria-label={`Remove row ${i + 1}`}
                  >
                    <IconX size={12} />
                  </button>
                </td>
              </tr>
            ))}
            {m.rows.length === 0 && (
              <tr>
                <td colSpan={cols.length + 1} className="px-2 py-3 text-center text-xs text-faint">
                  No rows yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={addRow}
          className="flex items-center gap-1 rounded-md border border-line bg-panel2 px-2.5 py-1 text-xs text-mute hover:text-ink"
        >
          <IconPlus size={13} /> {field.addLabel}
        </button>
        {shareSum != null && (
          <span className={"tnum text-xs " + (Math.abs(shareSum - 100) > 0.5 ? "text-warn" : "text-faint")}>
            Shares total {shareSum.toFixed(1)}%
          </span>
        )}
      </div>
    </div>
  );
}

function JsonEditor({ model, onChange }: EditorProps) {
  const v = model as string;
  return <textarea rows={4} value={v} onChange={(e) => onChange(e.target.value)} className={monoCls} spellCheck={false} />;
}

function renderEditor(props: EditorProps) {
  switch (props.field.kind) {
    case "rate":
      return <RateEditor {...props} />;
    case "flag":
      return <FlagEditor {...props} />;
    case "text":
      return <TextEditor {...props} />;
    case "stringList":
      return <StringListEditor {...props} />;
    case "table":
      return <TableEditor {...props} />;
    case "json":
      return <JsonEditor {...props} />;
  }
}

// ── card wrapper: label + help + editor + footer, per-card dirty & save ──────

export interface ConfigCardProps {
  configKey: string;
  field: Field;
  value: unknown;
  description: string | null;
  updatedAt?: string;
  mode?: "edit" | "create";
  onDone?: () => void;
}

export function ConfigCard({
  configKey,
  field,
  value,
  description,
  updatedAt,
  mode = "edit",
  onDone,
}: ConfigCardProps) {
  const initial = useMemo(
    () => (mode === "create" ? defaultModel(field) : parseModel(field, value)),
    [field, value, mode],
  );
  const initialStr = useMemo(() => serializeValue(field, initial), [field, initial]);

  const [model, setModel] = useState<Model>(initial);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const serialized = serializeValue(field, model);
  const dirty = mode === "create" || serialized !== initialStr;
  const v = validate(field, model);
  const canSave = dirty && v.ok && !pending;

  function save() {
    if (!v.ok) {
      setError(v.msg ?? "Fix the highlighted fields.");
      return;
    }
    const fd = new FormData();
    fd.set("key", configKey);
    fd.set("value", serialized);
    // Registry owns the human help; preserve any legacy DB description as-is.
    fd.set("description", description ?? "");
    start(async () => {
      const r = await upsertConfig(fd);
      setError(r.error);
      if (r.ok) onDone?.();
    });
  }

  function remove() {
    if (!confirm(`Delete ${configKey}? The app falls back to its baked-in value.`)) return;
    start(async () => {
      const r = await deleteConfig(configKey);
      setError(r.error);
      if (r.ok) onDone?.();
    });
  }

  return (
    <div className="rounded-xl border border-line bg-panel p-4">
      <div className="mb-1 flex items-baseline justify-between gap-3">
        <h3 className="text-sm font-semibold text-ink">{field.label}</h3>
        {updatedAt && (
          <span className="whitespace-nowrap text-[11px] text-faint">
            updated {new Date(updatedAt).toLocaleDateString()}
          </span>
        )}
      </div>
      <code className="mb-3 block font-mono text-[11px] text-faint">{configKey}</code>
      {field.help && <p className="mb-3 text-xs leading-relaxed text-mute">{field.help}</p>}

      {renderEditor({ field, model, onChange: setModel })}

      {v.warn && <p className="mt-2 text-xs text-warn">{v.warn}</p>}
      {error && <p className="mt-2 text-xs text-bad">{error}</p>}

      <div className="mt-4 flex items-center gap-3">
        <button
          type="button"
          onClick={save}
          disabled={!canSave}
          className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {pending ? "Publishing…" : mode === "create" ? "Add & republish" : "Save & republish"}
        </button>
        {dirty && mode === "edit" && <span className="text-xs text-faint">Unsaved changes</span>}
        {mode === "edit" && (
          <button type="button" onClick={remove} disabled={pending} className="ml-auto text-xs text-faint hover:text-bad">
            Delete
          </button>
        )}
        {mode === "create" && onDone && (
          <button type="button" onClick={onDone} disabled={pending} className="ml-auto text-xs text-faint hover:text-mute">
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

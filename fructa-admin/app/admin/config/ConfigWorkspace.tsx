"use client";

import { useMemo, useState, useTransition } from "react";
import { deleteConfig, publishConfig, type ConfigRow } from "./actions";
import { Detail } from "./Detail";
import { computeImpact, type Board } from "./impact";
import { freshness, groupTone, KIND_LABEL } from "./config-meta";
import {
  CONFIG_SCHEMA,
  type Field,
  type Model,
  type RateModel,
  type TableModel,
  defaultModel,
  fieldFor,
  groupRank,
  initialSerialized,
  parseModel,
  serializeValue,
  validate,
} from "./schema";
import { IconSearch } from "../_icons";

type Entry = {
  key: string;
  field: Field;
  /** the value in the database, or undefined when the key is not set */
  published: unknown;
  isNew: boolean;
  updatedAt: string | null;
};

/** A one-line summary of a value, for the list column. */
function preview(field: Field, model: Model): string {
  switch (field.kind) {
    case "rate": {
      const r = (model as RateModel).rate;
      return r ? `${Number(r).toFixed(2)}%` : "empty";
    }
    case "flag":
      return model === true ? "on" : "off";
    case "stringList":
      return `${(model as string[]).length} chips`;
    case "table":
      return `${(model as TableModel).rows.length} rows`;
    case "text":
      return "text";
    default:
      return "json";
  }
}

export function ConfigWorkspace({
  rows,
  board,
  publishedAt,
}: {
  rows: ConfigRow[];
  board: Board;
  publishedAt: string | null;
}) {
  // every registry key, plus anything in the database the registry has not met
  const entries = useMemo<Entry[]>(() => {
    const byKey = new Map(rows.map((r) => [r.key, r]));
    const out: Entry[] = [];

    for (const key of Object.keys(CONFIG_SCHEMA)) {
      const row = byKey.get(key);
      out.push({
        key,
        field: CONFIG_SCHEMA[key],
        published: row?.value,
        isNew: !row,
        updatedAt: row?.updated_at ?? null,
      });
    }
    for (const r of rows) {
      if (CONFIG_SCHEMA[r.key]) continue;
      out.push({ key: r.key, field: fieldFor(r), published: r.value, isNew: false, updatedAt: r.updated_at });
    }
    return out;
  }, [rows]);

  const entryOf = useMemo(() => new Map(entries.map((e) => [e.key, e])), [entries]);

  const [selected, setSelected] = useState<string>(entries[0]?.key ?? "");
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<"all" | "stale" | "unset">("all");
  const [staged, setStaged] = useState<Record<string, Model>>({});
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  /** The model currently on screen for a key: staged if touched, else stored. */
  const modelOf = (e: Entry): Model =>
    staged[e.key] ?? (e.isNew ? defaultModel(e.field) : parseModel(e.field, e.published));

  const isDirty = (e: Entry): boolean => {
    const m = staged[e.key];
    if (m === undefined) return false;
    const base = e.isNew
      ? serializeValue(e.field, defaultModel(e.field))
      : initialSerialized(e.field, e.published);
    // a not-set key counts as staged the moment it is touched at all
    return e.isNew ? true : serializeValue(e.field, m) !== base;
  };

  const dirtyKeys = useMemo(
    () => entries.filter(isDirty).map((e) => e.key),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [entries, staged],
  );

  const staleKeys = useMemo(
    () =>
      entries.filter((e) => {
        const m = modelOf(e);
        const asOf =
          e.field.kind === "rate" || e.field.kind === "table"
            ? (m as RateModel | TableModel).as_of || null
            : null;
        return freshness(e.key, asOf).kind === "stale";
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [entries, staged],
  );
  const unsetKeys = useMemo(() => entries.filter((e) => e.isNew), [entries]);

  const visible = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return entries.filter((e) => {
      if (filter === "stale" && !staleKeys.includes(e)) return false;
      if (filter === "unset" && !e.isNew) return false;
      if (needle && !`${e.key} ${e.field.label}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [entries, q, filter, staleKeys]);

  const grouped = useMemo(() => {
    const g = new Map<string, Entry[]>();
    for (const e of visible) {
      if (!g.has(e.field.group)) g.set(e.field.group, []);
      g.get(e.field.group)!.push(e);
    }
    return [...g.entries()].sort((a, b) => groupRank(a[0]) - groupRank(b[0]) || a[0].localeCompare(b[0]));
  }, [visible]);

  const current = entryOf.get(selected);

  // the diff chips on the publish bar
  const diffs = dirtyKeys.map((k) => {
    const e = entryOf.get(k)!;
    const before = e.isNew ? "unset" : preview(e.field, parseModel(e.field, e.published));
    const after = preview(e.field, modelOf(e));
    return { key: k.split(".").slice(-1)[0], before, after };
  });

  const blocked = dirtyKeys
    .map((k) => entryOf.get(k)!)
    .filter((e) => !validate(e.field, modelOf(e)).ok);

  function publish() {
    setMsg(null);
    const edits = dirtyKeys.map((k) => {
      const e = entryOf.get(k)!;
      return { key: k, value: serializeValue(e.field, modelOf(e)) };
    });
    start(async () => {
      const r = await publishConfig(edits);
      if (r.ok) {
        setStaged({});
        setMsg({ ok: true, text: `Published ${edits.length} change${edits.length === 1 ? "" : "s"}` });
      } else {
        setMsg({ ok: false, text: r.error ?? "Publish failed" });
      }
    });
  }

  function remove(key: string) {
    if (!confirm(`Delete ${key}? The app falls back to the value baked into the build.`)) return;
    start(async () => {
      const r = await deleteConfig(key);
      setMsg(r.ok ? { ok: true, text: `Deleted ${key}` } : { ok: false, text: r.error ?? "Delete failed" });
      if (r.ok) setStaged((s) => { const n = { ...s }; delete n[key]; return n; });
    });
  }

  const Dot = ({ e }: { e: Entry }) => {
    if (e.isNew) return <span className="h-1.5 w-1.5 rounded-full border border-line2" />;
    const m = modelOf(e);
    const asOf =
      e.field.kind === "rate" || e.field.kind === "table"
        ? (m as RateModel | TableModel).as_of || null
        : null;
    const f = freshness(e.key, asOf);
    const tone =
      f.kind === "stale" ? "bg-bad" : f.kind === "due" ? "bg-warn" : f.kind === "constant" || f.kind === "undated" ? "bg-line2" : "bg-live";
    return <span className={"h-1.5 w-1.5 rounded-full " + tone} />;
  };

  const Chip = ({ id, label, n }: { id: typeof filter; label: string; n: number }) => (
    <button
      onClick={() => setFilter(id)}
      className={
        "inline-flex items-center gap-1.5 rounded-md border px-2 py-1 text-[11px] " +
        (filter === id ? "border-line2 bg-panel2 text-ink" : "border-line text-faint hover:text-ink")
      }
    >
      {id === "stale" && n > 0 && <span className="h-1.5 w-1.5 rounded-full bg-warn" />}
      {label} <span className="tnum text-faint">{n}</span>
    </button>
  );

  return (
    <div className="flex h-[calc(100vh-64px)] flex-col">
      <div className="grid min-h-0 flex-1 grid-cols-[298px_1fr]">
        {/* keys */}
        <div className="flex min-h-0 flex-col border-r border-line bg-panel">
          <div className="border-b border-line p-2.5">
            <div className="relative">
              <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-faint">
                <IconSearch size={13} />
              </span>
              <input
                value={q}
                onChange={(e) => setQ(e.target.value)}
                placeholder="Filter keys"
                className="w-full rounded-md border border-line bg-panel2 py-1.5 pl-7 pr-2 text-[12.5px] text-ink outline-none placeholder:text-faint focus:border-line2"
              />
            </div>
            <div className="mt-2 flex gap-1.5">
              <Chip id="all" label="All" n={entries.length} />
              <Chip id="stale" label="Stale" n={staleKeys.length} />
              <Chip id="unset" label="Unset" n={unsetKeys.length} />
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto pb-3">
            {grouped.map(([group, items]) => (
              <div key={group}>
                <div className="flex items-center gap-2 px-3 pb-1.5 pt-4">
                  <span className={"h-2.5 w-0.5 rounded-full " + groupTone(group).solid} />
                  <span className={"text-[10px] font-semibold uppercase tracking-wider " + groupTone(group).text}>
                    {group}
                  </span>
                  <span className="tnum text-[10px] text-line2">{items.length}</span>
                </div>
                {items.map((e) => {
                  const on = e.key === selected;
                  const dirty = isDirty(e);
                  const tone = groupTone(e.field.group);
                  return (
                    <button
                      key={e.key}
                      onClick={() => setSelected(e.key)}
                      className={
                        "grid w-full grid-cols-[6px_1fr_auto] items-center gap-2.5 border-l-2 px-3 py-1.5 text-left " +
                        (on
                          ? `${tone.border.replace("border-", "border-l-")} bg-panel2`
                          : "border-l-transparent hover:bg-raise") +
                        (dirty && !on ? " bg-gold/[0.05]" : "")
                      }
                    >
                      <Dot e={e} />
                      <span className="min-w-0">
                        <span className={"block text-[12.5px] font-medium " + (on ? "text-ink" : "text-mute")}>
                          {e.field.label}
                        </span>
                        <span className="mt-px block font-mono text-[10px] text-faint">{e.key}</span>
                      </span>
                      <span
                        className={
                          "flex items-center gap-1.5 font-mono text-[11.5px] " +
                          (e.isNew ? "text-faint" : on ? tone.text : "text-mute")
                        }
                      >
                        {e.isNew ? "not set" : preview(e.field, modelOf(e))}
                        {dirty && <span className="h-1.5 w-1.5 rounded-full bg-gold" />}
                      </span>
                    </button>
                  );
                })}
              </div>
            ))}
            {visible.length === 0 && (
              <p className="px-3 py-8 text-center text-xs text-faint">No keys match.</p>
            )}
          </div>
        </div>

        {/* detail */}
        <div className="min-h-0 overflow-y-auto">
          {current ? (
            <Detail
              key={current.key}
              configKey={current.key}
              field={current.field}
              published={current.published}
              model={modelOf(current)}
              isNew={current.isNew}
              updatedAt={current.updatedAt}
              board={board}
              onChange={(m) => setStaged((s) => ({ ...s, [current.key]: m }))}
              onReset={() =>
                setStaged((s) => {
                  const n = { ...s };
                  delete n[current.key];
                  return n;
                })
              }
              onDelete={() => remove(current.key)}
            />
          ) : (
            <p className="p-8 text-sm text-faint">Pick a key.</p>
          )}
        </div>
      </div>

      {/* publish */}
      <div className="flex h-[52px] flex-none items-center gap-3.5 border-t border-line2 bg-panel px-4">
        {dirtyKeys.length === 0 ? (
          <span className="flex items-center gap-2 text-[12.5px] text-faint">
            <span className="h-1.5 w-1.5 rounded-full bg-live" />
            {msg ? (
              <span className={msg.ok ? "text-live" : "text-bad"}>{msg.text}</span>
            ) : publishedAt ? (
              <>Snapshot published {new Date(publishedAt).toLocaleString()}</>
            ) : (
              <>No staged changes</>
            )}
          </span>
        ) : (
          <>
            <span className="flex flex-none items-center gap-2 text-[12.5px] font-medium">
              <span className="rounded bg-gold px-1.5 py-px font-mono text-[11px] font-bold text-[#191204]">
                {dirtyKeys.length}
              </span>
              staged
            </span>
            <div className="flex flex-1 gap-1.5 overflow-x-auto">
              {diffs.map((d) => (
                <span
                  key={d.key}
                  className="inline-flex flex-none items-center gap-1.5 rounded-md border border-line bg-panel2 px-2 py-1 font-mono text-[11px]"
                >
                  <span className="text-mute">{d.key}</span>
                  <span className="text-faint line-through">{d.before}</span>
                  <span className="text-line2">to</span>
                  <b className="font-semibold text-gold">{d.after}</b>
                </span>
              ))}
            </div>
            {blocked.length > 0 && (
              <span className="flex-none text-[11.5px] text-bad">
                {blocked.length} invalid, fix before publishing
              </span>
            )}
            {msg && !msg.ok && <span className="flex-none text-[11.5px] text-bad">{msg.text}</span>}
            <button
              onClick={() => setStaged({})}
              disabled={pending}
              className="flex-none rounded-lg border border-line2 px-3 py-1.5 text-[12.5px] text-mute hover:bg-panel2 hover:text-ink disabled:opacity-40"
            >
              Discard
            </button>
            <button
              onClick={publish}
              disabled={pending || blocked.length > 0}
              className="flex-none rounded-lg border border-gold bg-gold px-3.5 py-1.5 text-[12.5px] font-semibold text-[#191204] hover:brightness-110 disabled:opacity-40"
            >
              {pending ? "Publishing" : `Publish ${dirtyKeys.length} change${dirtyKeys.length === 1 ? "" : "s"}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

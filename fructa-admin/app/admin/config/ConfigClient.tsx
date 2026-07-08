"use client";

import { useMemo, useState, useTransition } from "react";
import { upsertConfig, type ConfigRow } from "./actions";
import { ConfigCard } from "./editors";
import { CONFIG_SCHEMA, fieldFor, groupRank } from "./schema";
import { IconSearch } from "../_icons";

export function ConfigClient({ rows }: { rows: ConfigRow[] }) {
  const [q, setQ] = useState("");
  const [groupFilter, setGroupFilter] = useState<string>("all");
  const [sortBy, setSortBy] = useState<"key" | "updated">("key");
  const [creating, setCreating] = useState<string>(""); // predefined key being added

  // group + field resolved once per row
  const resolved = useMemo(
    () => rows.map((r) => ({ row: r, field: fieldFor(r) })),
    [rows],
  );

  const groupCounts = useMemo(() => {
    const m = new Map<string, number>();
    for (const { field } of resolved) m.set(field.group, (m.get(field.group) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => groupRank(a[0]) - groupRank(b[0]) || a[0].localeCompare(b[0]));
  }, [resolved]);

  const lastUpdated = useMemo(
    () => rows.reduce((mx, r) => Math.max(mx, new Date(r.updated_at).getTime()), 0),
    [rows],
  );

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return resolved.filter(({ row, field }) => {
      if (groupFilter !== "all" && field.group !== groupFilter) return false;
      if (needle) {
        const hay = `${row.key} ${field.label} ${field.help} ${row.description ?? ""}`.toLowerCase();
        if (!hay.includes(needle)) return false;
      }
      return true;
    });
  }, [resolved, q, groupFilter]);

  const groups = useMemo(() => {
    const g = new Map<string, typeof filtered>();
    for (const item of filtered) {
      if (!g.has(item.field.group)) g.set(item.field.group, []);
      g.get(item.field.group)!.push(item);
    }
    for (const list of g.values()) {
      list.sort((a, b) =>
        sortBy === "key"
          ? a.field.label.localeCompare(b.field.label)
          : new Date(b.row.updated_at).getTime() - new Date(a.row.updated_at).getTime(),
      );
    }
    return [...g.entries()].sort((a, b) => groupRank(a[0]) - groupRank(b[0]) || a[0].localeCompare(b[0]));
  }, [filtered, sortBy]);

  // predefined schema keys not yet in the DB — one-click add with a real editor
  const missingKeys = useMemo(() => {
    const have = new Set(rows.map((r) => r.key));
    return Object.keys(CONFIG_SCHEMA).filter((k) => !have.has(k));
  }, [rows]);

  const Kpi = ({ label, value }: { label: string; value: number | string }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className="mt-0.5 text-2xl font-semibold tnum text-ink">{value}</div>
    </div>
  );

  return (
    <div className="space-y-4">
      {/* KPIs */}
      <div className="grid grid-cols-3 gap-3">
        <Kpi label="Keys" value={rows.length} />
        <Kpi label="Groups" value={groupCounts.length} />
        <Kpi label="Last updated" value={lastUpdated ? new Date(lastUpdated).toLocaleDateString() : "—"} />
      </div>

      {/* toolbar */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-faint">
            <IconSearch size={14} />
          </span>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search name, key, or description…"
            className="w-72 rounded-md border border-line bg-panel2 py-1.5 pl-8 pr-3 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60"
          />
        </div>
        <div className="flex flex-wrap items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
          <button
            onClick={() => setGroupFilter("all")}
            className={"rounded-md px-2.5 py-1 text-xs " + (groupFilter === "all" ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}
          >
            All
          </button>
          {groupCounts.map(([g, c]) => (
            <button
              key={g}
              onClick={() => setGroupFilter(g)}
              className={"rounded-md px-2.5 py-1 text-xs " + (groupFilter === g ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}
            >
              {g} <span className="tnum text-faint">{c}</span>
            </button>
          ))}
        </div>
        <select
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value as "key" | "updated")}
          className="ml-auto rounded-md border border-line bg-panel2 px-2 py-1.5 text-xs text-mute outline-none focus:border-gold/60"
        >
          <option value="key">Sort: name A–Z</option>
          <option value="updated">Sort: recently updated</option>
        </select>
      </div>

      {/* grouped cards */}
      {groups.map(([group, items]) => (
        <div key={group} className="space-y-3">
          <div className="flex items-center gap-2 pt-1">
            <span className="text-[11px] uppercase tracking-wider text-gold">{group}</span>
            <span className="tnum text-[11px] text-faint">{items.length}</span>
            <div className="h-px flex-1 bg-line" />
          </div>
          {items.map(({ row, field }) => (
            <ConfigCard
              key={row.key}
              configKey={row.key}
              field={field}
              value={row.value}
              description={row.description}
              updatedAt={row.updated_at}
            />
          ))}
        </div>
      ))}

      {filtered.length === 0 && (
        <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">
          No keys match. Clear the search or pick a different group.
        </p>
      )}

      {/* add a key */}
      <div className="space-y-3 rounded-xl border border-dashed border-line bg-panel p-4">
        <p className="text-[11px] uppercase tracking-wider text-faint">Add a key</p>

        {missingKeys.length > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-mute">Predefined:</span>
            <select
              value={creating}
              onChange={(e) => setCreating(e.target.value)}
              className="rounded-md border border-line bg-panel2 px-2 py-1.5 text-xs text-ink outline-none focus:border-gold/60"
            >
              <option value="">Choose a key…</option>
              {missingKeys.map((k) => (
                <option key={k} value={k}>
                  {CONFIG_SCHEMA[k].label} · {k}
                </option>
              ))}
            </select>
          </div>
        )}

        {creating && (
          <ConfigCard
            key={creating}
            mode="create"
            configKey={creating}
            field={CONFIG_SCHEMA[creating]}
            value={CONFIG_SCHEMA[creating].seed ?? null}
            description={null}
            onDone={() => setCreating("")}
          />
        )}

        <CustomKeyForm />
      </div>
    </div>
  );
}

/** Escape hatch: add an arbitrary key as plain text or JSON (pre-registry). */
function CustomKeyForm() {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const input =
    "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 font-mono text-xs text-ink outline-none placeholder:text-faint focus:border-gold/60";

  function add(fd: FormData) {
    start(async () => {
      const r = await upsertConfig(fd);
      setError(r.error);
    });
  }

  return (
    <details className="group">
      <summary className="cursor-pointer text-xs text-mute hover:text-ink">Add a custom key (advanced)</summary>
      <form action={add} className="mt-3 space-y-2">
        <input name="key" placeholder="namespace.key" className={input} />
        <textarea name="value" rows={2} placeholder='Plain text, or JSON (true / 12.5 / {"a":1})' className={input} />
        <input
          name="description"
          placeholder="What this controls (optional)"
          className="w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-xs text-mute outline-none placeholder:text-faint focus:border-gold/60"
        />
        {error && <p className="text-xs text-bad">{error}</p>}
        <button
          disabled={pending}
          className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40"
        >
          {pending ? "Publishing…" : "Add & republish"}
        </button>
      </form>
    </details>
  );
}

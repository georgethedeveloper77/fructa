"use client";

import { useMemo, useState } from "react";
import { addTemplate, updateTemplate, toggleTemplate, deleteTemplate } from "./actions";

export type Template = {
  id: number;
  key: string;
  tag: "STRENGTH" | "WATCH" | "NOTE";
  template: string;
  active: boolean;
};

// The 25 condition keys the engine evaluates.
const KEYS = [
  "upBig", "upSmall", "downBig", "downSmall", "flat", "top1", "liqFast",
  "minLow", "minHigh", "feeHigh", "taxfree",
  "tbillHeavy", "corpHeavy",
  "usd", "sacco", "bondLock", "insurerGap",
  "gokHeavy", "depositHeavy", "offshoreEx", "unlistedEx", "concentrated", "diversified",
  "mgrTop", "mgrBig",
];
const TAGS = ["STRENGTH", "WATCH", "NOTE"] as const;
type Tag = (typeof TAGS)[number];

const tagClass: Record<string, string> = {
  STRENGTH: "border-live/40 bg-live/10 text-live",
  WATCH: "border-bad/40 bg-bad/10 text-bad",
  NOTE: "border-line text-mute",
};

// Valid replacement tokens (from the engine). Anything else renders literally
// in-app, so we flag unknown tokens before they're saved.
const VALID_TOKENS = new Set([
  "n", "r", "net", "min", "fee", "d", "liq", "tb", "cp",
  "gok", "dep", "off", "unl", "top", "topName", "rank", "aum",
]);
function unknownTokens(text: string): string[] {
  const found = [...text.matchAll(/\{([^}]+)\}/g)].map((m) => m[1].trim());
  return [...new Set(found.filter((t) => !VALID_TOKENS.has(t)))];
}

function SearchIcon() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.5" y2="16.5" />
    </svg>
  );
}
function WarnIcon() {
  return (
    <svg width={11} height={11} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 9v4M12 17h.01M10.3 3.9 2 18a2 2 0 0 0 1.7 3h16.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" />
    </svg>
  );
}
function TokenWarn({ text }: { text: string }) {
  const bad = unknownTokens(text);
  if (bad.length === 0) return null;
  return (
    <span className="inline-flex items-center gap-1 rounded-md border border-warn/40 bg-warn/5 px-2 py-0.5 text-[11px] text-warn">
      <WarnIcon /> unknown token{bad.length > 1 ? "s" : ""}: {bad.map((t) => `{${t}}`).join(" ")}
    </span>
  );
}

export function InsightsClient({ rows }: { rows: Template[] }) {
  const [q, setQ] = useState("");
  const [tag, setTag] = useState<Tag | "all">("all");
  const [hideEmpty, setHideEmpty] = useState(false);
  const [newTemplate, setNewTemplate] = useState("");
  const [edits, setEdits] = useState<Record<number, string>>({});

  const keysPresent = useMemo(
    () => [...new Set([...KEYS, ...rows.map((r) => r.key)])],
    [rows],
  );

  const stats = useMemo(() => {
    const perTag: Record<string, number> = { STRENGTH: 0, WATCH: 0, NOTE: 0 };
    let active = 0, badTokens = 0;
    const covered = new Set<string>();
    for (const r of rows) {
      perTag[r.tag] = (perTag[r.tag] ?? 0) + 1;
      if (r.active) active++;
      covered.add(r.key);
      if (unknownTokens(r.template).length) badTokens++;
    }
    const emptyKeys = keysPresent.filter((k) => !covered.has(k)).length;
    return { total: rows.length, active, inactive: rows.length - active, perTag, covered: covered.size, emptyKeys, badTokens };
  }, [rows, keysPresent]);

  const byKey = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const m = new Map<string, Template[]>();
    for (const r of rows) {
      if (tag !== "all" && r.tag !== tag) continue;
      if (needle && !`${r.template} ${r.key}`.toLowerCase().includes(needle)) continue;
      m.set(r.key, [...(m.get(r.key) ?? []), r]);
    }
    return m;
  }, [rows, q, tag]);

  const filtering = q.trim() !== "" || tag !== "all";
  const sections = keysPresent.filter((key) => {
    const list = byKey.get(key) ?? [];
    if (list.length > 0) return true;
    if (filtering || hideEmpty) return false; // hide empty keys while filtering/hiding
    return true;
  });

  const Kpi = ({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: "warn" | "ok" }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={"mt-0.5 text-2xl font-semibold tnum " + (tone === "warn" ? "text-warn" : tone === "ok" ? "text-live" : "text-ink")}>{value}</div>
      {sub && <div className="text-[11px] text-faint">{sub}</div>}
    </div>
  );

  return (
    <div className="space-y-4">
      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Phrasings" value={stats.total} />
        <Kpi label="Active" value={stats.active} sub={`${stats.inactive} inactive`} />
        <Kpi label="Keys covered" value={`${stats.covered}/${keysPresent.length}`} sub={`${stats.emptyKeys} empty`} tone={stats.emptyKeys ? "warn" : "ok"} />
        <Kpi label="Bad tokens" value={stats.badTokens} tone={stats.badTokens ? "warn" : "ok"} />
      </div>

      {/* tag distribution */}
      <div className="flex flex-wrap gap-x-5 gap-y-1 rounded-xl border border-line bg-panel px-4 py-2.5 text-xs text-mute">
        {TAGS.map((tg) => (
          <span key={tg}><span className="tnum font-medium text-ink">{stats.perTag[tg] ?? 0}</span> {tg}</span>
        ))}
      </div>

      {/* add */}
      <form action={addTemplate} className="flex flex-wrap items-end gap-2 rounded-xl border border-line bg-panel p-4">
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Key</span>
          <select name="key" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            {KEYS.map((k) => <option key={k} value={k}>{k}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Tag</span>
          <select name="tag" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            {TAGS.map((tg) => <option key={tg} value={tg}>{tg}</option>)}
          </select>
        </label>
        <label className="flex flex-1 flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Template</span>
          <input
            name="template" required value={newTemplate} onChange={(e) => setNewTemplate(e.target.value)}
            placeholder="{n} leads its class at <b>{r}%</b> ({net}% net)."
            className="w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60"
          />
        </label>
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add</button>
        {newTemplate.trim() && <div className="w-full"><TokenWarn text={newTemplate} /></div>}
      </form>

      {/* toolbar */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-faint"><SearchIcon /></span>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search phrasing or key…"
            className="w-64 rounded-md border border-line bg-panel2 py-1.5 pl-8 pr-3 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
        </div>
        <div className="flex items-center gap-0.5 rounded-lg border border-line bg-panel p-0.5">
          <button onClick={() => setTag("all")} className={"rounded-md px-2.5 py-1 text-xs " + (tag === "all" ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>All</button>
          {TAGS.map((tg) => (
            <button key={tg} onClick={() => setTag(tg)} className={"rounded-md px-2.5 py-1 text-xs " + (tag === tg ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>
              {tg} <span className="tnum text-faint">{stats.perTag[tg] ?? 0}</span>
            </button>
          ))}
        </div>
        <label className="ml-auto flex cursor-pointer items-center gap-1.5 text-xs text-mute">
          <input type="checkbox" checked={hideEmpty} onChange={(e) => setHideEmpty(e.target.checked)} className="accent-gold" />
          Hide empty keys
        </label>
      </div>

      {/* grouped */}
      <div className="space-y-5">
        {sections.map((key) => {
          const list = byKey.get(key) ?? [];
          return (
            <section key={key}>
              <div className="mb-2 flex items-baseline gap-2">
                <h2 className="font-mono text-sm text-ink">{key}</h2>
                <span className="text-xs text-faint">{list.length} phrasing{list.length === 1 ? "" : "s"}</span>
              </div>
              {list.length === 0 ? (
                <p className="rounded-lg border border-dashed border-line px-3 py-3 text-xs text-faint">No phrasings yet — add one above with this key.</p>
              ) : (
                <div className="space-y-2">
                  {list.map((t) => {
                    const val = edits[t.id] ?? t.template;
                    return (
                      <div key={t.id} className={"rounded-lg border border-line bg-panel p-3 " + (t.active ? "" : "opacity-50")}>
                        <form action={updateTemplate} className="flex items-center gap-2">
                          <input type="hidden" name="id" value={t.id} />
                          <select name="tag" defaultValue={t.tag} className={"rounded-md border px-2 py-0.5 text-[10px] font-semibold tracking-wide " + tagClass[t.tag]}>
                            {TAGS.map((tg) => <option key={tg} value={tg}>{tg}</option>)}
                          </select>
                          <input
                            name="template" value={val}
                            onChange={(e) => setEdits((s) => ({ ...s, [t.id]: e.target.value }))}
                            className="min-w-0 flex-1 rounded-md border border-line bg-panel2 px-2.5 py-1 text-sm text-ink outline-none focus:border-gold/60"
                          />
                          <button className="rounded-md border border-line px-2 py-1 text-xs text-mute hover:border-gold/60 hover:text-gold">Save</button>
                        </form>
                        <div className="mt-2 flex flex-wrap items-center gap-3 text-xs">
                          <ToggleActive id={t.id} active={t.active} />
                          <DeleteBtn id={t.id} />
                          <TokenWarn text={val} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>
          );
        })}
        {sections.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">No phrasings match.</p>
        )}
      </div>
    </div>
  );
}

function ToggleActive({ id, active }: { id: number; active: boolean }) {
  return (
    <form action={toggleTemplate}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="value" value={(!active).toString()} />
      <button className={"hover:underline " + (active ? "text-mute" : "text-faint")}>{active ? "Active" : "Inactive"}</button>
    </form>
  );
}
function DeleteBtn({ id }: { id: number }) {
  return (
    <form action={deleteTemplate}>
      <input type="hidden" name="id" value={id} />
      <button className="text-faint hover:text-bad">Delete</button>
    </form>
  );
}

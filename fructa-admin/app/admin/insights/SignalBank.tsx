"use client";

import { useMemo, useState } from "react";
import { addTemplate, updateTemplate, toggleTemplate, deleteTemplate } from "./actions";
import {
  KEY_META, KEY_BY_NAME, KEYS, GROUPS, TOKEN_META, unknownTokens, fillTemplate,
  type Tag,
} from "./signal-meta";

export type Template = { id: number; key: string; tag: Tag; template: string; active: boolean };

const TAGS: Tag[] = ["STRENGTH", "WATCH", "NOTE"];
const tagPill: Record<string, string> = {
  STRENGTH: "bg-live/10 text-live",
  WATCH: "bg-bad/10 text-bad",
  NOTE: "bg-raise2 text-muted",
};
const tagSelect: Record<string, string> = {
  STRENGTH: "border-live/40 bg-live/10 text-live",
  WATCH: "border-bad/40 bg-bad/10 text-bad",
  NOTE: "border-line text-mute",
};

function Chevron({ open }: { open: boolean }) {
  return (
    <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      {open ? <path d="m6 9 6 6 6-6" /> : <path d="m9 6 6 6-6 6" />}
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
function SearchIcon() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" />
    </svg>
  );
}

// Live preview: fill tokens, then render <b>…</b> as bold gold.
function Filled({ template }: { template: string }) {
  const text = fillTemplate(template);
  const parts = text.split(/(<\/?b>)/g);
  let bold = false;
  const nodes: React.ReactNode[] = [];
  parts.forEach((p, i) => {
    if (p === "<b>") { bold = true; return; }
    if (p === "</b>") { bold = false; return; }
    if (!p) return;
    nodes.push(bold ? <b key={i} className="text-gold">{p}</b> : <span key={i}>{p}</span>);
  });
  return <span className="leading-snug">{nodes}</span>;
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

function Verify() {
  return <span className="rounded border border-warn/40 bg-warn/5 px-1.5 py-0.5 text-[10px] font-medium text-warn">verify</span>;
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

export function SignalBank({ rows }: { rows: Template[] }) {
  const [mode, setMode] = useState<"human" | "code">("human");
  const [q, setQ] = useState("");
  const [edits, setEdits] = useState<Record<number, string>>({});
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [addKey, setAddKey] = useState(KEYS[0]);
  const [addTag, setAddTag] = useState<Tag>("STRENGTH");
  const [newTemplate, setNewTemplate] = useState("");

  const toggleOpen = (k: string) =>
    setOpen((s) => { const n = new Set(s); n.has(k) ? n.delete(k) : n.add(k); return n; });

  const stats = useMemo(() => {
    const perTag: Record<string, number> = { STRENGTH: 0, WATCH: 0, NOTE: 0 };
    let active = 0, bad = 0;
    const covered = new Set<string>();
    for (const r of rows) {
      perTag[r.tag] = (perTag[r.tag] ?? 0) + 1;
      if (r.active) active++;
      covered.add(r.key);
      if (unknownTokens(r.template).length) bad++;
    }
    const allKeys = new Set([...KEYS, ...rows.map((r) => r.key)]);
    const empty = [...allKeys].filter((k) => !covered.has(k)).length;
    return { total: rows.length, active, inactive: rows.length - active, perTag, covered: covered.size, keys: allKeys.size, empty, bad };
  }, [rows]);

  const byKey = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const m = new Map<string, Template[]>();
    for (const r of rows) {
      if (needle && !`${r.template} ${r.key}`.toLowerCase().includes(needle)) continue;
      m.set(r.key, [...(m.get(r.key) ?? []), r]);
    }
    return m;
  }, [rows, q]);

  const filtering = q.trim() !== "";

  // legacy keys present in data but not in the meta dictionary
  const legacy = useMemo(
    () => [...new Set(rows.map((r) => r.key))].filter((k) => !KEY_BY_NAME[k]),
    [rows],
  );

  const Kpi = ({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: "warn" | "ok" }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={"mt-0.5 text-2xl font-semibold tnum " + (tone === "warn" ? "text-warn" : tone === "ok" ? "text-live" : "text-ink")}>{value}</div>
      {sub && <div className="text-[11px] text-faint">{sub}</div>}
    </div>
  );

  // one phrasing, rendered by mode
  function Phrasing({ t }: { t: Template }) {
    const val = edits[t.id] ?? t.template;
    if (mode === "human") {
      return (
        <div className={"rounded-lg border border-line bg-panel p-3 " + (t.active ? "" : "opacity-50")}>
          <div className="text-[13.5px] text-ink"><Filled template={val} /></div>
          <form action={updateTemplate} className="mt-2 flex items-center gap-2">
            <input type="hidden" name="id" value={t.id} />
            <input type="hidden" name="tag" value={t.tag} />
            <input
              name="template" value={val}
              onChange={(e) => setEdits((s) => ({ ...s, [t.id]: e.target.value }))}
              className="min-w-0 flex-1 rounded-md border border-line bg-panel2 px-2.5 py-1 font-mono text-[12px] text-mute outline-none focus:border-gold/60 focus:text-ink"
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
    }
    // code mode
    return (
      <div className={"rounded-lg border border-line bg-panel p-3 " + (t.active ? "" : "opacity-50")}>
        <form action={updateTemplate} className="flex items-center gap-2">
          <input type="hidden" name="id" value={t.id} />
          <select name="tag" defaultValue={t.tag} className={"rounded-md border px-2 py-0.5 text-[10px] font-semibold tracking-wide " + tagSelect[t.tag]}>
            {TAGS.map((tg) => <option key={tg} value={tg}>{tg}</option>)}
          </select>
          <input
            name="template" value={val}
            onChange={(e) => setEdits((s) => ({ ...s, [t.id]: e.target.value }))}
            className="min-w-0 flex-1 rounded-md border border-line bg-panel2 px-2.5 py-1 font-mono text-sm text-ink outline-none focus:border-gold/60"
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
  }

  function KeyCard({ keyName }: { keyName: string }) {
    const meta = KEY_BY_NAME[keyName];
    const list = byKey.get(keyName) ?? [];
    const isOpen = open.has(keyName) || mode === "code" || filtering;

    // empty key gap (only when not filtering) in human mode
    if (list.length === 0 && mode === "human" && !filtering) {
      return (
        <div className="flex items-center gap-3 rounded-xl border border-dashed border-warn/50 bg-warn/5 px-4 py-3">
          <span className="w-[104px] flex-none font-mono text-[13px] font-semibold text-warn">{keyName}</span>
          <span className="flex-1 text-[12.5px] text-muted">
            <b className="text-warn">No phrasings yet.</b> {meta?.meaning ?? "Meaning not documented."} The app has nothing to say when this fires.
          </span>
          <button
            onClick={() => { setAddKey(keyName); if (meta) setAddTag(meta.tag); }}
            className="flex-none rounded-md border border-gold/50 bg-gold/10 px-3 py-1 text-xs font-medium text-gold hover:bg-gold/20"
          >
            Write one
          </button>
        </div>
      );
    }
    if (list.length === 0 && (filtering || mode === "code")) return null;

    return (
      <div className="overflow-hidden rounded-xl border border-line bg-panel">
        <button
          onClick={() => mode === "human" && toggleOpen(keyName)}
          className={"flex w-full items-center gap-3 px-4 py-3 text-left " + (mode === "human" ? "hover:bg-raise" : "cursor-default")}
        >
          <span className="w-[104px] flex-none font-mono text-[13.5px] font-semibold text-ink">{keyName}</span>
          {meta && <span className={"flex-none rounded px-1.5 py-0.5 text-[10px] font-semibold " + tagPill[meta.tag]}>{meta.tag}</span>}
          {mode === "human" && <span className="flex-1 text-[13px] text-muted">{meta?.meaning ?? "Meaning not documented for this key."}</span>}
          {mode === "code" && <span className="flex-1 font-mono text-xs text-faint">{list.length} phrasing{list.length === 1 ? "" : "s"}</span>}
          {meta?.unsure && <Verify />}
          <span className="flex-none font-mono text-[11px] text-faint">{list.length}</span>
          {mode === "human" && <span className="flex-none text-faint"><Chevron open={isOpen} /></span>}
        </button>
        {isOpen && (
          <div className="space-y-2 border-t border-line bg-raise p-3">
            {list.map((t) => <Phrasing key={t.id} t={t} />)}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* explainer */}
      <div className="rounded-xl border border-line bg-panel px-4 py-3 text-[13px] leading-relaxed text-muted">
        Each day the app shows <b className="text-ink">one line per fund</b>. You do not write them per fund, you write reusable
        <b className="text-ink"> phrasings</b> under a <b className="text-ink">key</b> (a condition like <code className="font-mono text-faint">top1</code>),
        and the app fills each fund's numbers into the <code className="font-mono text-faint">{"{tokens}"}</code>.
      </div>

      {/* mode toggle + KPIs */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="inline-flex rounded-lg border border-line bg-panel p-0.5">
          {(["human", "code"] as const).map((m) => (
            <button key={m} onClick={() => setMode(m)}
              className={"rounded-md px-3.5 py-1.5 text-sm font-medium capitalize " + (mode === m ? "bg-panel2 text-ink" : "text-mute hover:text-ink")}>
              {m} mode
            </button>
          ))}
        </div>
        <span className="text-xs text-faint">
          {mode === "human" ? "Plain-English meanings and live previews." : "Raw templates and tokens for fast editing."}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Phrasings" value={stats.total} sub={`${stats.active} active`} />
        <Kpi label="Keys covered" value={`${stats.covered}/${stats.keys}`} sub={`${stats.empty} empty`} tone={stats.empty ? "warn" : "ok"} />
        <Kpi label="Strengths" value={stats.perTag.STRENGTH ?? 0} sub={`${stats.perTag.WATCH ?? 0} watch · ${stats.perTag.NOTE ?? 0} note`} />
        <Kpi label="Bad tokens" value={stats.bad} tone={stats.bad ? "warn" : "ok"} />
      </div>

      {/* token reference */}
      {mode === "human" ? (
        <div>
          <div className="mb-2 text-[11px] uppercase tracking-wider text-faint">Tokens, and what they fill with</div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {TOKEN_META.map((t) => (
              <div key={t.token} className="rounded-lg border border-line bg-panel px-3 py-2">
                <div className="flex items-center gap-1.5">
                  <span className="font-mono text-[12.5px] font-semibold text-gold">{`{${t.token}}`}</span>
                  {t.unsure && <Verify />}
                </div>
                <div className="mt-0.5 text-[11.5px] text-muted">{t.meaning}</div>
                <div className="mt-0.5 font-mono text-[11px] text-faint">{t.sample}</div>
              </div>
            ))}
          </div>
        </div>
      ) : (
        <div className="rounded-lg border border-line bg-panel px-4 py-2.5 font-mono text-[11.5px] text-faint">
          {TOKEN_META.map((t) => `{${t.token}}`).join(" ")} &nbsp;·&nbsp; {"<b>bold</b>"}
        </div>
      )}

      {/* add */}
      <form action={addTemplate} className="rounded-xl border border-line bg-panel p-4">
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Key</span>
            <select name="key" value={addKey} onChange={(e) => setAddKey(e.target.value)}
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
              {KEY_META.map((k) => <option key={k.key} value={k.key}>{mode === "human" ? `${k.key} · ${k.meaning}` : k.key}</option>)}
              {legacy.map((k) => <option key={k} value={k}>{k}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Tag</span>
            <select name="tag" value={addTag} onChange={(e) => setAddTag(e.target.value as Tag)}
              className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
              {TAGS.map((tg) => <option key={tg} value={tg}>{tg}</option>)}
            </select>
          </label>
          <label className="flex flex-1 flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Phrasing</span>
            <input name="template" required value={newTemplate} onChange={(e) => setNewTemplate(e.target.value)}
              placeholder="{n} leads its class at <b>{r}%</b> ({net}% net)."
              className="w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
          </label>
          <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add</button>
        </div>
        {newTemplate.trim() && (
          <div className="mt-3 flex flex-wrap items-center gap-3">
            <span className="text-[11px] uppercase tracking-wider text-faint">Preview</span>
            <span className="text-[13px] text-ink"><Filled template={newTemplate} /></span>
            <TokenWarn text={newTemplate} />
          </div>
        )}
      </form>

      {/* search */}
      <div className="relative">
        <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-faint"><SearchIcon /></span>
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search phrasing or key"
          className="w-72 rounded-md border border-line bg-panel2 py-1.5 pl-8 pr-3 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60" />
      </div>

      {/* grouped keys */}
      <div className="space-y-6">
        {GROUPS.map((g) => {
          const keys = KEY_META.filter((k) => k.group === g).map((k) => k.key);
          const visible = keys.filter((k) => !(filtering && (byKey.get(k) ?? []).length === 0));
          if (visible.length === 0) return null;
          return (
            <section key={g}>
              <div className="mb-2 flex items-center gap-2">
                <span className="text-[11px] font-semibold uppercase tracking-wider text-gold">{g}</span>
                <span className="h-px flex-1 bg-line" />
              </div>
              <div className="space-y-2">
                {keys.map((k) => <KeyCard key={k} keyName={k} />)}
              </div>
            </section>
          );
        })}

        {legacy.length > 0 && (
          <section>
            <div className="mb-2 flex items-center gap-2">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-faint">Other keys (not in dictionary)</span>
              <span className="h-px flex-1 bg-line" />
            </div>
            <div className="space-y-2">
              {legacy.map((k) => <KeyCard key={k} keyName={k} />)}
            </div>
          </section>
        )}

        {filtering && [...byKey.keys()].length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">No phrasings match.</p>
        )}
      </div>
    </div>
  );
}

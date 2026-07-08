"use client";

import { useState, useTransition } from "react";
import {
  deleteLesson,
  deleteStep,
  deleteUnit,
  republishNow,
  saveLesson,
  saveStep,
  saveUnit,
  type FundOption,
  type LearnLessonRow,
  type LearnStepRow,
  type LearnUnitRow,
} from "./actions";
import { IconChevronRight, IconPlus, IconRefresh, IconX } from "../_icons";

// ── shared styles ────────────────────────────────────────────────────────────
const field =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const micro = "mb-1 block text-[10px] uppercase tracking-wider text-faint";
const btnGold =
  "rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40";
const btnGhost =
  "flex items-center gap-1 rounded-md border border-line bg-panel2 px-2.5 py-1 text-xs text-mute hover:text-ink";
const del = "ml-auto text-xs text-faint hover:text-bad";

const ACCENTS = ["", "gold", "sky", "emerald", "iris", "amber"];

function Toggle({ on, onChange }: { on: boolean; onChange: (b: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      onClick={() => onChange(!on)}
      className="flex items-center gap-2"
    >
      <span
        className={
          "relative h-5 w-9 rounded-full border transition-colors " +
          (on ? "border-gold/60 bg-gold/80" : "border-line bg-panel2")
        }
      >
        <span
          className={
            "absolute top-0.5 h-3.5 w-3.5 rounded-full bg-ink transition-all " +
            (on ? "left-[18px]" : "left-0.5")
          }
        />
      </span>
      <span className={"text-xs " + (on ? "text-ink" : "text-mute")}>
        {on ? "Active" : "Hidden"}
      </span>
    </button>
  );
}

function Err({ msg }: { msg: string | null }) {
  return msg ? <p className="mt-2 text-xs text-bad">{msg}</p> : null;
}

// ── Step editor ──────────────────────────────────────────────────────────────

type Payload = Record<string, unknown>;

function defaultPayload(kind: string): Payload {
  if (kind === "interactive") {
    return {
      title: "",
      body: "",
      widget: "earn_slider",
      rate: 10.67,
      min: 1000,
      max: 500000,
      initial: 10000,
    };
  }
  if (kind === "quiz") {
    return {
      prompt: "",
      options: [{ text: "", correct: false }],
      explain_ok: "",
      explain_no: "",
    };
  }
  if (kind === "image") {
    return { url: "", caption: "" };
  }
  return { title: "", body: "", note: "" };
}

const CHART_TEMPLATE = JSON.stringify(
  {
    chart: "bars",
    title: "MMF vs inflation",
    caption: "A top MMF still beats inflation today.",
    unit: "%",
    series: [
      { label: "Etica MMF", value: 10.67, highlight: true },
      { label: "Inflation", value: 6.7 },
    ],
  },
  null,
  2,
);

function buildPayload(kind: string, p: Payload): Payload {
  const s = (v: unknown) => (typeof v === "string" ? v.trim() : v);
  const n = (v: unknown) => Number(v) || 0;
  if (kind === "interactive") {
    return {
      title: s(p.title),
      body: s(p.body),
      widget: (p.widget as string) || "earn_slider",
      rate: n(p.rate),
      min: n(p.min),
      max: n(p.max),
      initial: n(p.initial),
    };
  }
  if (kind === "quiz") {
    const opts = ((p.options as { text: string; correct: boolean }[]) ?? [])
      .map((o) => ({ text: (o.text ?? "").trim(), correct: !!o.correct }))
      .filter((o) => o.text !== "");
    return {
      prompt: s(p.prompt),
      options: opts,
      explain_ok: s(p.explain_ok) || undefined,
      explain_no: s(p.explain_no) || undefined,
    };
  }
  if (kind === "image") {
    const o: Payload = { url: s(p.url) };
    if (s(p.caption)) o.caption = s(p.caption);
    return o;
  }
  const out: Payload = { title: s(p.title), body: s(p.body) };
  if (s(p.note)) out.note = s(p.note);
  return out;
}

function StepCard({
  step,
  lessonId,
  mode = "edit",
  onDone,
}: {
  step?: LearnStepRow;
  lessonId: string;
  mode?: "edit" | "create";
  onDone?: () => void;
}) {
  const [kind, setKind] = useState(step?.kind ?? "explainer");
  const [ord, setOrd] = useState(String(step?.ord ?? 0));
  const [p, setP] = useState<Payload>(
    () => step?.payload ?? defaultPayload("explainer"),
  );
  const [chartText, setChartText] = useState(() =>
    step?.kind === "chart"
      ? JSON.stringify(step.payload, null, 2)
      : CHART_TEMPLATE,
  );
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const set = (k: string, v: unknown) => setP((prev) => ({ ...prev, [k]: v }));

  function changeKind(k: string) {
    setKind(k);
    if (mode === "create" || !step || k !== step.kind) setP(defaultPayload(k));
    else setP(step.payload);
    if (k === "chart" && (mode === "create" || step?.kind !== "chart")) {
      setChartText(CHART_TEMPLATE);
    }
  }

  function save() {
    let payloadObj: Payload;
    if (kind === "chart") {
      try {
        payloadObj = JSON.parse(chartText);
      } catch {
        setError("Chart JSON is invalid.");
        return;
      }
    } else {
      payloadObj = buildPayload(kind, p);
    }
    const fd = new FormData();
    if (step?.id) fd.set("id", step.id);
    fd.set("lesson_id", lessonId);
    fd.set("kind", kind);
    fd.set("ord", ord);
    fd.set("payload", JSON.stringify(payloadObj));
    start(async () => {
      const r = await saveStep(fd);
      setError(r.error);
      if (r.ok) onDone?.();
    });
  }

  function remove() {
    if (!step) return;
    if (!confirm("Delete this step?")) return;
    start(async () => {
      const r = await deleteStep(step.id);
      setError(r.error);
    });
  }

  const opts = (p.options as { text: string; correct: boolean }[]) ?? [];

  return (
    <div className="rounded-lg border border-line bg-panel2 p-3">
      <div className="mb-2 flex items-center gap-2">
        <select
          value={kind}
          onChange={(e) => changeKind(e.target.value)}
          className="rounded-md border border-line bg-panel px-2 py-1 text-xs text-ink outline-none focus:border-gold/60"
        >
          <option value="explainer">Explainer</option>
          <option value="interactive">Interactive</option>
          <option value="quiz">Quiz</option>
          <option value="image">Image</option>
          <option value="chart">Chart</option>
        </select>
        <label className="text-[10px] uppercase tracking-wider text-faint">
          Order
        </label>
        <input
          value={ord}
          inputMode="numeric"
          onChange={(e) => setOrd(e.target.value)}
          className="w-14 rounded-md border border-line bg-panel px-2 py-1 text-xs text-ink outline-none focus:border-gold/60"
        />
      </div>

      {kind === "explainer" && (
        <div className="space-y-2">
          <input
            value={(p.title as string) ?? ""}
            onChange={(e) => set("title", e.target.value)}
            placeholder="Title"
            className={field}
          />
          <textarea
            rows={4}
            value={(p.body as string) ?? ""}
            onChange={(e) => set("body", e.target.value)}
            placeholder="Body (blank line = new paragraph)"
            className={field}
          />
          <textarea
            rows={2}
            value={(p.note as string) ?? ""}
            onChange={(e) => set("note", e.target.value)}
            placeholder="Note (optional callout)"
            className={field}
          />
        </div>
      )}

      {kind === "interactive" && (
        <div className="space-y-2">
          <input
            value={(p.title as string) ?? ""}
            onChange={(e) => set("title", e.target.value)}
            placeholder="Title"
            className={field}
          />
          <textarea
            rows={2}
            value={(p.body as string) ?? ""}
            onChange={(e) => set("body", e.target.value)}
            placeholder="Body"
            className={field}
          />
          <div className="flex flex-wrap gap-2">
            <label className="text-xs text-mute">
              Widget
              <select
                value={(p.widget as string) ?? "earn_slider"}
                onChange={(e) => set("widget", e.target.value)}
                className="ml-2 rounded-md border border-line bg-panel px-2 py-1 text-xs text-ink outline-none focus:border-gold/60"
              >
                <option value="earn_slider">Earn slider</option>
              </select>
            </label>
          </div>
          <div className="grid grid-cols-4 gap-2">
            {(["rate", "min", "max", "initial"] as const).map((k) => (
              <div key={k}>
                <label className={micro}>{k}</label>
                <input
                  inputMode="decimal"
                  value={String(p[k] ?? "")}
                  onChange={(e) => set(k, e.target.value)}
                  className={field + " font-mono text-xs tnum"}
                />
              </div>
            ))}
          </div>
          <p className="text-[11px] text-faint">
            Rate defaults to the fund&rsquo;s live rate when the lesson is linked
            to a fund; the value here is the fallback.
          </p>
        </div>
      )}

      {kind === "quiz" && (
        <div className="space-y-2">
          <textarea
            rows={2}
            value={(p.prompt as string) ?? ""}
            onChange={(e) => set("prompt", e.target.value)}
            placeholder="Question"
            className={field}
          />
          <div className="space-y-1.5">
            {opts.map((o, i) => (
              <div key={i} className="flex items-center gap-2">
                <button
                  type="button"
                  role="checkbox"
                  aria-checked={o.correct}
                  onClick={() =>
                    set(
                      "options",
                      opts.map((x, j) =>
                        j === i ? { ...x, correct: !x.correct } : x,
                      ),
                    )
                  }
                  className={
                    "flex h-5 w-5 shrink-0 items-center justify-center rounded border " +
                    (o.correct
                      ? "border-gold/60 bg-gold/20 text-gold"
                      : "border-line text-transparent")
                  }
                  title={o.correct ? "Correct answer" : "Mark correct"}
                >
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
                </button>
                <input
                  value={o.text}
                  onChange={(e) =>
                    set(
                      "options",
                      opts.map((x, j) =>
                        j === i ? { ...x, text: e.target.value } : x,
                      ),
                    )
                  }
                  placeholder={`Option ${i + 1}`}
                  className={field}
                />
                <button
                  type="button"
                  onClick={() =>
                    set("options", opts.filter((_, j) => j !== i))
                  }
                  className="text-faint hover:text-bad"
                  aria-label="Remove option"
                >
                  <IconX size={13} />
                </button>
              </div>
            ))}
            <button
              type="button"
              onClick={() => set("options", [...opts, { text: "", correct: false }])}
              className={btnGhost}
            >
              <IconPlus size={12} /> Option
            </button>
          </div>
          <textarea
            rows={2}
            value={(p.explain_ok as string) ?? ""}
            onChange={(e) => set("explain_ok", e.target.value)}
            placeholder="Explanation when correct"
            className={field}
          />
          <textarea
            rows={2}
            value={(p.explain_no as string) ?? ""}
            onChange={(e) => set("explain_no", e.target.value)}
            placeholder="Explanation when wrong"
            className={field}
          />
        </div>
      )}

      {kind === "image" && (
        <div className="space-y-2">
          <input
            value={(p.url as string) ?? ""}
            onChange={(e) => set("url", e.target.value)}
            placeholder="Image URL (https://…)"
            className={field}
          />
          <input
            value={(p.caption as string) ?? ""}
            onChange={(e) => set("caption", e.target.value)}
            placeholder="Caption (optional)"
            className={field}
          />
          <p className="text-[11px] text-faint">
            Host the image in Supabase Storage (or any public URL). It renders
            cached, rounded and full-width.
          </p>
        </div>
      )}

      {kind === "chart" && (
        <div className="space-y-2">
          <textarea
            rows={10}
            value={chartText}
            onChange={(e) => setChartText(e.target.value)}
            spellCheck={false}
            className={field + " font-mono text-xs"}
          />
          <p className="text-[11px] leading-relaxed text-faint">
            <code className="text-mute">chart</code>:{" "}
            <code className="text-mute">bars</code> (series of label/value, one{" "}
            <code className="text-mute">highlight</code>) ·{" "}
            <code className="text-mute">line</code> (
            <code className="text-mute">labels</code> +{" "}
            <code className="text-mute">lines</code>) ·{" "}
            <code className="text-mute">growth</code> (
            <code className="text-mute">principal, rate, years, net</code>).
          </p>
        </div>
      )}

      <Err msg={error} />
      <div className="mt-3 flex items-center gap-3">
        <button onClick={save} disabled={pending} className={btnGold}>
          {pending ? "Publishing…" : mode === "create" ? "Add step" : "Save"}
        </button>
        {mode === "edit" && step && (
          <button onClick={remove} disabled={pending} className={del}>
            Delete
          </button>
        )}
        {mode === "create" && onDone && (
          <button onClick={onDone} className="ml-auto text-xs text-faint hover:text-mute">
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

// ── Lesson editor ────────────────────────────────────────────────────────────

function LessonCard({
  lesson,
  unitId,
  funds,
  mode = "edit",
  onDone,
}: {
  lesson?: LearnLessonRow;
  unitId: string;
  funds: FundOption[];
  mode?: "edit" | "create";
  onDone?: () => void;
}) {
  const [title, setTitle] = useState(lesson?.title ?? "");
  const [ord, setOrd] = useState(String(lesson?.ord ?? 0));
  const [xp, setXp] = useState(String(lesson?.xp ?? 20));
  const [fundId, setFundId] = useState(lesson?.fund_id ?? "");
  const [active, setActive] = useState(lesson?.active ?? true);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [addingStep, setAddingStep] = useState(false);

  function save() {
    const fd = new FormData();
    if (lesson?.id) fd.set("id", lesson.id);
    fd.set("unit_id", unitId);
    fd.set("title", title);
    fd.set("ord", ord);
    fd.set("xp", xp);
    fd.set("fund_id", fundId);
    fd.set("active", String(active));
    start(async () => {
      const r = await saveLesson(fd);
      setError(r.error);
      if (r.ok) onDone?.();
    });
  }

  function remove() {
    if (!lesson) return;
    if (!confirm(`Delete lesson “${lesson.title}” and its steps?`)) return;
    start(async () => {
      const r = await deleteLesson(lesson.id);
      setError(r.error);
    });
  }

  const body = (
    <div className="space-y-2">
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Lesson title"
        className={field}
      />
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className={micro}>Order</label>
          <input value={ord} inputMode="numeric" onChange={(e) => setOrd(e.target.value)} className={field + " w-20"} />
        </div>
        <div>
          <label className={micro}>XP</label>
          <input value={xp} inputMode="numeric" onChange={(e) => setXp(e.target.value)} className={field + " w-20"} />
        </div>
        <div className="min-w-[180px] flex-1">
          <label className={micro}>Live fund (optional)</label>
          <select
            value={fundId ?? ""}
            onChange={(e) => setFundId(e.target.value)}
            className={field}
          >
            <option value="">None</option>
            {funds.map((f) => (
              <option key={f.id} value={f.id}>
                {f.name}
              </option>
            ))}
          </select>
        </div>
        <Toggle on={active} onChange={setActive} />
      </div>
      <Err msg={error} />
      <div className="flex items-center gap-3">
        <button onClick={save} disabled={pending} className={btnGold}>
          {pending ? "Publishing…" : mode === "create" ? "Add lesson" : "Save lesson"}
        </button>
        {mode === "edit" && lesson && (
          <button onClick={remove} disabled={pending} className={del}>
            Delete lesson
          </button>
        )}
        {mode === "create" && onDone && (
          <button onClick={onDone} className="ml-auto text-xs text-faint hover:text-mute">
            Cancel
          </button>
        )}
      </div>

      {mode === "edit" && lesson && (
        <div className="mt-2 space-y-2 border-t border-line pt-3">
          <p className="text-[11px] uppercase tracking-wider text-faint">Steps</p>
          {lesson.steps.map((s) => (
            <StepCard key={s.id} step={s} lessonId={lesson.id} />
          ))}
          {addingStep ? (
            <StepCard
              lessonId={lesson.id}
              mode="create"
              onDone={() => setAddingStep(false)}
            />
          ) : (
            <button onClick={() => setAddingStep(true)} className={btnGhost}>
              <IconPlus size={12} /> Add step
            </button>
          )}
        </div>
      )}
    </div>
  );

  if (mode === "create") {
    return <div className="rounded-lg border border-dashed border-line bg-panel p-3">{body}</div>;
  }

  return (
    <details className="group rounded-lg border border-line bg-panel [&_summary::-webkit-details-marker]:hidden">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-3 py-2">
        <span className="text-faint transition-transform group-open:rotate-90">
          <IconChevronRight size={14} />
        </span>
        <span className="text-sm font-medium text-ink">{lesson?.title}</span>
        {!active && <span className="rounded bg-panel2 px-1.5 text-[10px] text-faint">hidden</span>}
        <span className="ml-auto text-[11px] text-faint">
          {lesson?.steps.length} steps · {xp} XP
        </span>
      </summary>
      <div className="px-3 pb-3">{body}</div>
    </details>
  );
}

// ── Unit editor ──────────────────────────────────────────────────────────────

function UnitCard({
  unit,
  units,
  funds,
  mode = "edit",
  onDone,
}: {
  unit?: LearnUnitRow;
  units: LearnUnitRow[];
  funds: FundOption[];
  mode?: "edit" | "create";
  onDone?: () => void;
}) {
  const [title, setTitle] = useState(unit?.title ?? "");
  const [ord, setOrd] = useState(String(unit?.ord ?? 0));
  const [subtitle, setSubtitle] = useState(unit?.subtitle ?? "");
  const [accent, setAccent] = useState(unit?.accent ?? "");
  const [unlockAfter, setUnlockAfter] = useState(unit?.unlock_after ?? "");
  const [active, setActive] = useState(unit?.active ?? true);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [addingLesson, setAddingLesson] = useState(false);

  const others = units.filter((u) => u.id !== unit?.id);

  function save() {
    const fd = new FormData();
    if (unit?.id) fd.set("id", unit.id);
    fd.set("title", title);
    fd.set("ord", ord);
    fd.set("subtitle", subtitle);
    fd.set("accent", accent);
    fd.set("unlock_after", unlockAfter);
    fd.set("active", String(active));
    start(async () => {
      const r = await saveUnit(fd);
      setError(r.error);
      if (r.ok) onDone?.();
    });
  }

  function remove() {
    if (!unit) return;
    if (!confirm(`Delete unit “${unit.title}”, its lessons and steps?`)) return;
    start(async () => {
      const r = await deleteUnit(unit.id);
      setError(r.error);
    });
  }

  const body = (
    <div className="space-y-2">
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Unit title"
        className={field}
      />
      <input
        value={subtitle}
        onChange={(e) => setSubtitle(e.target.value)}
        placeholder="Subtitle (optional)"
        className={field}
      />
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className={micro}>Order</label>
          <input value={ord} inputMode="numeric" onChange={(e) => setOrd(e.target.value)} className={field + " w-20"} />
        </div>
        <div>
          <label className={micro}>Accent</label>
          <select value={accent ?? ""} onChange={(e) => setAccent(e.target.value)} className={field}>
            {ACCENTS.map((a) => (
              <option key={a} value={a}>
                {a === "" ? "default" : a}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-[160px] flex-1">
          <label className={micro}>Unlocks after</label>
          <select value={unlockAfter ?? ""} onChange={(e) => setUnlockAfter(e.target.value)} className={field}>
            <option value="">Open from start</option>
            {others.map((u) => (
              <option key={u.id} value={u.id}>
                {u.title}
              </option>
            ))}
          </select>
        </div>
        <Toggle on={active} onChange={setActive} />
      </div>
      <Err msg={error} />
      <div className="flex items-center gap-3">
        <button onClick={save} disabled={pending} className={btnGold}>
          {pending ? "Publishing…" : mode === "create" ? "Add unit" : "Save unit"}
        </button>
        {mode === "edit" && unit && (
          <button onClick={remove} disabled={pending} className={del}>
            Delete unit
          </button>
        )}
        {mode === "create" && onDone && (
          <button onClick={onDone} className="ml-auto text-xs text-faint hover:text-mute">
            Cancel
          </button>
        )}
      </div>

      {mode === "edit" && unit && (
        <div className="mt-2 space-y-2 border-t border-line pt-3">
          <p className="text-[11px] uppercase tracking-wider text-faint">Lessons</p>
          {unit.lessons.map((l) => (
            <LessonCard key={l.id} lesson={l} unitId={unit.id} funds={funds} />
          ))}
          {addingLesson ? (
            <LessonCard
              unitId={unit.id}
              funds={funds}
              mode="create"
              onDone={() => setAddingLesson(false)}
            />
          ) : (
            <button onClick={() => setAddingLesson(true)} className={btnGhost}>
              <IconPlus size={12} /> Add lesson
            </button>
          )}
        </div>
      )}
    </div>
  );

  if (mode === "create") {
    return <div className="rounded-xl border border-dashed border-line bg-panel p-4">{body}</div>;
  }

  return (
    <details className="group rounded-xl border border-line bg-panel [&_summary::-webkit-details-marker]:hidden">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3">
        <span className="text-faint transition-transform group-open:rotate-90">
          <IconChevronRight size={16} />
        </span>
        <span className="text-sm font-semibold text-ink">{unit?.title}</span>
        {!active && <span className="rounded bg-panel2 px-1.5 text-[10px] text-faint">hidden</span>}
        <span className="ml-auto text-[11px] text-faint">
          {unit?.lessons.length} lessons
        </span>
      </summary>
      <div className="px-4 pb-4">{body}</div>
    </details>
  );
}

// ── Root ─────────────────────────────────────────────────────────────────────

export function LearnClient({
  units,
  funds,
}: {
  units: LearnUnitRow[];
  funds: FundOption[];
}) {
  const [addingUnit, setAddingUnit] = useState(false);
  const [pending, start] = useTransition();

  const lessonCount = units.reduce((s, u) => s + u.lessons.length, 0);
  const stepCount = units.reduce(
    (s, u) => s + u.lessons.reduce((t, l) => t + l.steps.length, 0),
    0,
  );

  const Kpi = ({ label, value }: { label: string; value: number | string }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className="mt-0.5 text-2xl font-semibold tnum text-ink">{value}</div>
    </div>
  );

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-3">
        <Kpi label="Units" value={units.length} />
        <Kpi label="Lessons" value={lessonCount} />
        <Kpi label="Steps" value={stepCount} />
      </div>

      <div className="flex items-center gap-3">
        <button
          onClick={() => start(async () => void (await republishNow()))}
          disabled={pending}
          className={btnGhost + " px-3 py-1.5"}
        >
          <IconRefresh size={13} /> {pending ? "Publishing…" : "Republish snapshot"}
        </button>
        <span className="text-[11px] text-faint">Saves already republish automatically.</span>
      </div>

      <div className="space-y-3">
        {units.map((u) => (
          <UnitCard key={u.id} unit={u} units={units} funds={funds} />
        ))}
      </div>

      {units.length === 0 && (
        <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">
          No units yet. Add the first one below.
        </p>
      )}

      <div className="space-y-3 rounded-xl border border-dashed border-line bg-panel p-4">
        <p className="text-[11px] uppercase tracking-wider text-faint">Add a unit</p>
        {addingUnit ? (
          <UnitCard units={units} funds={funds} mode="create" onDone={() => setAddingUnit(false)} />
        ) : (
          <button onClick={() => setAddingUnit(true)} className={btnGhost}>
            <IconPlus size={13} /> New unit
          </button>
        )}
      </div>
    </div>
  );
}

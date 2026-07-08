"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase/server";
import { republishSnapshot, slugify, strOrNull } from "@/lib/publish";

// ── Row shapes (nested for the client) ──────────────────────────────────────

export interface LearnStepRow {
  id: string;
  lesson_id: string;
  ord: number;
  kind: string; // explainer | interactive | quiz
  payload: Record<string, unknown>;
}

export interface LearnLessonRow {
  id: string;
  unit_id: string;
  ord: number;
  title: string;
  xp: number;
  fund_id: string | null;
  active: boolean;
  steps: LearnStepRow[];
}

export interface LearnUnitRow {
  id: string;
  ord: number;
  title: string;
  subtitle: string | null;
  accent: string | null;
  unlock_after: string | null;
  active: boolean;
  lessons: LearnLessonRow[];
}

export interface FundOption {
  id: string;
  name: string;
}

export interface Result {
  ok: boolean;
  error: string | null;
}

const rand = () => Math.random().toString(36).slice(2, 6);
const num = (v: FormDataEntryValue | null, d: number) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};
const bool = (v: FormDataEntryValue | null) => String(v) !== "false"; // default true

// A write only matters once it's in the snapshot the app reads.
async function publishAndRevalidate() {
  await republishSnapshot();
  revalidatePath("/admin/learn");
}

// ── Units ────────────────────────────────────────────────────────────────────

export async function saveUnit(fd: FormData): Promise<Result> {
  const title = String(fd.get("title") ?? "").trim();
  if (!title) return { ok: false, error: "Title is required." };
  const id = strOrNull(fd.get("id")) ?? `u_${slugify(title)}-${rand()}`;

  const db = supabaseAdmin();
  const { error } = await db.from("learn_units").upsert({
    id,
    ord: num(fd.get("ord"), 0),
    title,
    subtitle: strOrNull(fd.get("subtitle")),
    accent: strOrNull(fd.get("accent")),
    unlock_after: strOrNull(fd.get("unlock_after")),
    active: bool(fd.get("active")),
  });
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

export async function deleteUnit(id: string): Promise<Result> {
  const db = supabaseAdmin();
  const { error } = await db.from("learn_units").delete().eq("id", id);
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

// ── Lessons ──────────────────────────────────────────────────────────────────

export async function saveLesson(fd: FormData): Promise<Result> {
  const unitId = String(fd.get("unit_id") ?? "").trim();
  const title = String(fd.get("title") ?? "").trim();
  if (!unitId) return { ok: false, error: "Missing unit." };
  if (!title) return { ok: false, error: "Title is required." };
  const id = strOrNull(fd.get("id")) ?? `l_${slugify(title)}-${rand()}`;

  const db = supabaseAdmin();
  const { error } = await db.from("learn_lessons").upsert({
    id,
    unit_id: unitId,
    ord: num(fd.get("ord"), 0),
    title,
    xp: num(fd.get("xp"), 20),
    fund_id: strOrNull(fd.get("fund_id")),
    active: bool(fd.get("active")),
  });
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

export async function deleteLesson(id: string): Promise<Result> {
  const db = supabaseAdmin();
  const { error } = await db.from("learn_lessons").delete().eq("id", id);
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

// ── Steps ────────────────────────────────────────────────────────────────────

const KINDS = new Set(["explainer", "interactive", "quiz", "image", "chart"]);

export async function saveStep(fd: FormData): Promise<Result> {
  const lessonId = String(fd.get("lesson_id") ?? "").trim();
  const kind = String(fd.get("kind") ?? "").trim();
  if (!lessonId) return { ok: false, error: "Missing lesson." };
  if (!KINDS.has(kind)) return { ok: false, error: "Unknown step kind." };

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(String(fd.get("payload") ?? "{}"));
  } catch {
    return { ok: false, error: "Step payload isn't valid JSON." };
  }

  const id = strOrNull(fd.get("id")) ?? `s_${rand()}${rand()}`;

  const db = supabaseAdmin();
  const { error } = await db.from("learn_steps").upsert({
    id,
    lesson_id: lessonId,
    ord: num(fd.get("ord"), 0),
    kind,
    payload,
  });
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

export async function deleteStep(id: string): Promise<Result> {
  const db = supabaseAdmin();
  const { error } = await db.from("learn_steps").delete().eq("id", id);
  if (error) return { ok: false, error: error.message };
  await publishAndRevalidate();
  return { ok: true, error: null };
}

// ── Manual republish ─────────────────────────────────────────────────────────

export async function republishNow(): Promise<Result> {
  await publishAndRevalidate();
  return { ok: true, error: null };
}

// ── Bulk import ──────────────────────────────────────────────────────────────
// Paste a whole authored document (typically AI-generated) as one JSON tree and
// upsert it. Ids are optional — generated from titles when absent — and order
// falls back to array position, so a minimal doc still imports cleanly.

export interface ImportResult {
  ok: boolean;
  error: string | null;
  units: number;
  lessons: number;
  steps: number;
}

type Json = Record<string, unknown>;
const asObj = (v: unknown): Json =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Json) : {};
const asArr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const asStr = (v: unknown): string => (typeof v === "string" ? v : "");
const sn = (v: unknown): string | null => {
  const t = asStr(v).trim();
  return t === "" ? null : t;
};
const numOr = (v: unknown, d: number): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};
const fail = (msg: string): ImportResult => ({
  ok: false,
  error: msg,
  units: 0,
  lessons: 0,
  steps: 0,
});

export async function importLearn(fd: FormData): Promise<ImportResult> {
  const raw = String(fd.get("json") ?? "");
  const replace = String(fd.get("replace")) === "true";

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return fail("That isn't valid JSON.");
  }

  const units = Array.isArray(parsed) ? parsed : asArr(asObj(parsed).units);
  if (units.length === 0) {
    return fail('Expected { "units": [ … ] } with at least one unit.');
  }

  const uRows: Json[] = [];
  const lRows: Json[] = [];
  const sRows: Json[] = [];
  const errors: string[] = [];

  units.forEach((uRaw, ui) => {
    const u = asObj(uRaw);
    const title = asStr(u.title).trim();
    const uid = sn(u.id) ?? `u_${slugify(title || `unit-${ui}`)}-${rand()}`;
    uRows.push({
      id: uid,
      ord: numOr(u.ord, ui),
      title,
      subtitle: sn(u.subtitle),
      accent: sn(u.accent),
      unlock_after: sn(u.unlock_after),
      active: u.active !== false,
    });

    asArr(u.lessons).forEach((lRaw, li) => {
      const l = asObj(lRaw);
      const ltitle = asStr(l.title).trim();
      const lid = sn(l.id) ?? `l_${slugify(ltitle || `lesson-${li}`)}-${rand()}`;
      lRows.push({
        id: lid,
        unit_id: uid,
        ord: numOr(l.ord, li),
        title: ltitle,
        xp: numOr(l.xp, 20),
        fund_id: sn(l.fund_id),
        active: l.active !== false,
      });

      asArr(l.steps).forEach((sRaw, si) => {
        const s = asObj(sRaw);
        const kind = asStr(s.kind).trim();
        if (!KINDS.has(kind)) {
          errors.push(`Unknown step kind "${kind}" in lesson "${ltitle}".`);
          return;
        }
        sRows.push({
          id: sn(s.id) ?? `s_${rand()}${rand()}`,
          lesson_id: lid,
          ord: numOr(s.ord, si),
          kind,
          payload: asObj(s.payload),
        });
      });
    });
  });

  if (errors.length) return fail(errors[0]);
  if (uRows.some((u) => !u.title)) return fail("Every unit needs a title.");
  if (lRows.some((l) => !l.title)) return fail("Every lesson needs a title.");

  const db = supabaseAdmin();
  try {
    if (replace) {
      // Cascades to lessons + steps.
      await db.from("learn_units").delete().neq("id", "");
    }
    // Parents first so the foreign keys resolve.
    if (uRows.length) {
      const { error } = await db.from("learn_units").upsert(uRows);
      if (error) return fail(error.message);
    }
    if (lRows.length) {
      const { error } = await db.from("learn_lessons").upsert(lRows);
      if (error) return fail(error.message);
    }
    if (sRows.length) {
      const { error } = await db.from("learn_steps").upsert(sRows);
      if (error) return fail(error.message);
    }
  } catch (e) {
    return fail(e instanceof Error ? e.message : "Import failed.");
  }

  await publishAndRevalidate();
  return {
    ok: true,
    error: null,
    units: uRows.length,
    lessons: lRows.length,
    steps: sRows.length,
  };
}

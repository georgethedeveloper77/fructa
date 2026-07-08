import { supabaseAdmin } from "@/lib/supabase/server";
import { LearnClient } from "./LearnClient";
import { LearnImport } from "./LearnImport";
import type {
  FundOption,
  LearnLessonRow,
  LearnStepRow,
  LearnUnitRow,
} from "./actions";

export const dynamic = "force-dynamic";

export default async function LearnPage() {
  const db = supabaseAdmin();

  const [uRes, lRes, sRes, fRes] = await Promise.all([
    db.from("learn_units")
      .select("id,ord,title,subtitle,accent,unlock_after,active")
      .order("ord"),
    db.from("learn_lessons")
      .select("id,unit_id,ord,title,xp,fund_id,active")
      .order("ord"),
    db.from("learn_steps")
      .select("id,lesson_id,ord,kind,payload")
      .order("ord"),
    db.from("funds").select("id,name").eq("retail", true).order("name"),
  ]);

  const stepsByLesson = new Map<string, LearnStepRow[]>();
  for (const s of (sRes.data ?? []) as LearnStepRow[]) {
    const arr = stepsByLesson.get(s.lesson_id) ?? [];
    arr.push(s);
    stepsByLesson.set(s.lesson_id, arr);
  }

  const lessonsByUnit = new Map<string, LearnLessonRow[]>();
  for (const l of (lRes.data ?? []) as Omit<LearnLessonRow, "steps">[]) {
    const arr = lessonsByUnit.get(l.unit_id) ?? [];
    arr.push({ ...l, steps: stepsByLesson.get(l.id) ?? [] });
    lessonsByUnit.set(l.unit_id, arr);
  }

  const units: LearnUnitRow[] =
    ((uRes.data ?? []) as Omit<LearnUnitRow, "lessons">[]).map((u) => ({
      ...u,
      lessons: lessonsByUnit.get(u.id) ?? [],
    }));

  const funds = (fRes.data ?? []) as FundOption[];

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Learn</h1>
        <p className="mt-1 text-sm text-mute">
          Author the in-app lessons. Units hold lessons hold steps
          (explainer · interactive · quiz). Every save republishes the
          snapshot — devices pick changes up on their next refresh, no app
          release. A lesson can point at a fund to light up its live-rate badge
          and the &ldquo;See it live&rdquo; hand-off.
        </p>
      </header>
      <LearnImport />
      <LearnClient units={units} funds={funds} />
    </div>
  );
}

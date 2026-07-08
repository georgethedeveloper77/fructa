import { supabaseAdmin } from "@/lib/supabase/server";
import { ConfigClient } from "./ConfigClient";
import type { ConfigRow } from "./actions";

export const dynamic = "force-dynamic";

export default async function ConfigPage() {
  const db = supabaseAdmin();
  const { data } = await db
    .from("app_config")
    .select("key,value,description,updated_at")
    .order("key");

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Remote config</h1>
        <p className="mt-1 text-sm text-mute">
          The values published inside the app snapshot. Every save republishes —
          devices pick changes up on their next refresh, no app release. The app
          keeps baked-in fallbacks, so a deleted or malformed value can never
          break rendering. These drive the benchmark anchors, the Markets donut,
          feature flags, search, and onboarding copy.
        </p>
      </header>
      <ConfigClient rows={(data ?? []) as ConfigRow[]} />
    </div>
  );
}

// Shared helpers for the new admin sections. Mirrors the pattern in
// app/admin/funds/actions.ts so behaviour is identical across the panel.

// Manual changes must reach the app: re-publish the snapshot after a write.
// Non-fatal — a hiccup shouldn't fail the edit.
export async function republishSnapshot() {
  try {
    await fetch(`${process.env.SUPABASE_URL}/functions/v1/publish-snapshot`, {
      method: "POST",
      headers: { "x-cron-secret": process.env.CRON_SECRET ?? "" },
    });
  } catch {
    /* ignore */
  }
}

// Same slug rule the SQL backfill used (companies.id from a name).
export const slugify = (s: string) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

export const strOrNull = (v: FormDataEntryValue | null) => {
  const s = String(v ?? "").trim();
  return s === "" ? null : s;
};

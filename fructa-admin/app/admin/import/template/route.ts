import { supabaseAdmin } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

// Exports every fund name as a CSV (name,rate) so the Google Sheet / import file
// uses the EXACT names the importer matches on — no "unmatched" surprises.
export async function GET() {
  const { data } = await supabaseAdmin()
    .from("funds")
    .select("name,category,manager")
    .eq("kind", "fund")
    .order("category")
    .order("name");

  const esc = (s: string) => `"${s.replace(/"/g, '""')}"`;
  const lines = ["name,rate"];
  for (const f of data ?? []) {
    lines.push(`${esc((f as { name: string }).name)},`);
  }
  const csv = lines.join("\n");

  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="fructa_mmf_rates_template.csv"',
    },
  });
}

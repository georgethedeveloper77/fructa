import { supabaseAdmin } from "@/lib/supabase/server";
import { createCompany } from "./actions";
import { CompaniesTable, type Company } from "./CompaniesTable";

export const dynamic = "force-dynamic";

const TYPE_LABEL: Record<string, string> = {
  fund_manager: "Fund manager",
  insurer: "Insurer",
  sacco: "SACCO",
  government: "Government",
};

export default async function CompaniesPage() {
  const db = supabaseAdmin();
  const [{ data: companies, error }, { data: funds }] = await Promise.all([
    db.from("companies").select("id,name,type,brand_color,logo_url,website,phone,whatsapp,email,verified").order("name"),
    db.from("funds").select("company_id"),
  ]);

  const rows = (companies ?? []) as Company[];
  const counts: Record<string, number> = {};
  for (const f of funds ?? []) {
    const cid = (f as { company_id: string | null }).company_id;
    if (cid) counts[cid] = (counts[cid] ?? 0) + 1;
  }

  return (
    <div className="mx-auto max-w-6xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Companies</h1>
        <p className="mt-1 text-sm text-mute">
          {rows.length} companies. Edit names, sites and type inline; select rows for bulk verify/delete. Logos: 512×512 PNG, square, brand mark.
        </p>
      </header>

      <form action={createCompany} className="mb-6 flex flex-wrap items-end gap-2 rounded-xl border border-line bg-panel p-4">
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Name</span>
          <input name="name" required placeholder="Etica Capital" className="w-56 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60" />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Type</span>
          <select name="type" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            {Object.entries(TYPE_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Website</span>
          <input name="website" placeholder="https://eticacap.com" className="w-56 rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60" />
        </label>
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add company</button>
      </form>

      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>
      )}

      <CompaniesTable rows={rows} counts={counts} />
    </div>
  );
}

import { supabaseAdmin } from "@/lib/supabase/server";
import { createInsurer, updateInsurer, deleteInsurer } from "./actions";

export const dynamic = "force-dynamic";

type Insurer = {
  id: string;
  name: string;
  company_id: string | null;
  currency: string;
  motor_rate: number | null;
  min_premium: number | null;
  excess_pct: number | null;
  excess_min: number | null;
  claims_days: number | null;
  rating: number | null;
  benefits: string[] | null;
  plans: { name: string; price: number }[] | null;
  logo_domain: string | null;
};
type Company = { id: string; name: string };

export default async function InsurersPage() {
  const db = supabaseAdmin();
  const [{ data: insurers, error }, { data: companies }] = await Promise.all([
    db
      .from("funds")
      .select(
        "id,name,company_id,currency,motor_rate,min_premium,excess_pct,excess_min,claims_days,rating,benefits,plans,logo_domain",
      )
      .eq("kind", "insurance")
      .order("name"),
    db.from("companies").select("id,name").order("name"),
  ]);

  const rows = (insurers ?? []) as Insurer[];
  const cos = (companies ?? []) as Company[];

  return (
    <div className="mx-auto max-w-4xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Insurers</h1>
        <p className="mt-1 text-sm text-mute">
          {rows.length} products. Motor uses a % of vehicle value; travel plans are flat tiers. Edits publish to the app.
        </p>
      </header>

      {/* create */}
      <form action={createInsurer} className="mb-6 flex flex-wrap items-end gap-2 rounded-xl border border-line bg-panel p-4">
        <F label="Name" name="name" placeholder="CIC General" required w="w-52" />
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Company</span>
          <select name="company_id" defaultValue="" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            <option value="">—</option>
            {cos.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Currency</span>
          <select name="currency" defaultValue="KES" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            <option>KES</option><option>USD</option>
          </select>
        </label>
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add insurer</button>
      </form>

      {error && <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>}

      <div className="space-y-4">
        {rows.map((i) => (
          <form key={i.id} action={updateInsurer} className="rounded-xl border border-line bg-panel p-4">
            <input type="hidden" name="id" value={i.id} />
            <div className="mb-3 flex items-center gap-2">
              <input name="name" defaultValue={i.name} className="w-64 rounded-md border border-line bg-panel2 px-2.5 py-1 text-sm font-medium text-ink outline-none focus:border-gold/60" />
              <select name="company_id" defaultValue={i.company_id ?? ""} className="rounded-md border border-line bg-panel2 px-2 py-1 text-xs text-mute outline-none focus:border-gold/60">
                <option value="">— company —</option>
                {cos.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
              <select name="currency" defaultValue={i.currency} className="rounded-md border border-line bg-panel2 px-2 py-1 text-xs text-mute">
                <option>KES</option><option>USD</option>
              </select>
              <span className="ml-auto text-[11px] text-faint">{i.id}</span>
            </div>

            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Num label="Motor rate %" name="motor_rate" v={i.motor_rate} />
              <Num label="Min premium" name="min_premium" v={i.min_premium} />
              <Num label="Excess %" name="excess_pct" v={i.excess_pct} />
              <Num label="Excess min" name="excess_min" v={i.excess_min} />
              <Num label="Claims (days)" name="claims_days" v={i.claims_days} />
              <Num label="Rating (1-5)" name="rating" v={i.rating} />
            </div>

            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <label className="flex flex-col gap-1">
                <span className="text-[11px] uppercase tracking-wider text-faint">Benefits (comma-separated)</span>
                <input name="benefits" defaultValue={(i.benefits ?? []).join(", ")} placeholder="Courtesy car 14d, Windscreen 75k, Roadside" className="rounded-md border border-line bg-panel2 px-2.5 py-1 text-sm text-ink outline-none focus:border-gold/60" />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[11px] uppercase tracking-wider text-faint">Logo domain</span>
                <input name="logo_domain" defaultValue={i.logo_domain ?? ""} placeholder="cic.co.ke" className="rounded-md border border-line bg-panel2 px-2.5 py-1 text-sm text-ink outline-none focus:border-gold/60" />
              </label>
            </div>

            <label className="mt-3 flex flex-col gap-1">
              <span className="text-[11px] uppercase tracking-wider text-faint">Travel plans (one per line: Name, price)</span>
              <textarea
                name="plans"
                rows={3}
                defaultValue={(i.plans ?? []).map((p) => `${p.name}, ${p.price}`).join("\n")}
                placeholder={"Africa 7 days, 2650\nWorldwide 30 days, 8900"}
                className="rounded-md border border-line bg-panel2 px-2.5 py-2 font-mono text-xs text-ink outline-none focus:border-gold/60"
              />
            </label>

            <div className="mt-3 flex items-center gap-3">
              <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Save</button>
              <button
                formAction={deleteInsurer}
                className="rounded-md border border-bad/40 px-3 py-1.5 text-xs text-bad hover:bg-bad/10"
              >
                Delete
              </button>
            </div>
          </form>
        ))}
        {rows.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">No insurers yet.</p>
        )}
      </div>
    </div>
  );
}

function F({ label, name, placeholder, required, w }: { label: string; name: string; placeholder?: string; required?: boolean; w: string }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] uppercase tracking-wider text-faint">{label}</span>
      <input name={name} placeholder={placeholder} required={required} className={`${w} rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60`} />
    </label>
  );
}

function Num({ label, name, v }: { label: string; name: string; v: number | null }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] uppercase tracking-wider text-faint">{label}</span>
      <input name={name} defaultValue={v ?? ""} inputMode="decimal" className="rounded-md border border-line bg-panel2 px-2.5 py-1 text-sm text-ink outline-none focus:border-gold/60" />
    </label>
  );
}

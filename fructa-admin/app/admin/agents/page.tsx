import { supabaseAdmin } from "@/lib/supabase/server";
import {
  createAgent,
  toggleAgentFlag,
  deleteAgent,
  addAgentCompany,
  removeAgentCompany,
} from "./actions";
import { IconX } from "../_icons";

export const dynamic = "force-dynamic";

type Agent = {
  id: string;
  name: string;
  role: string | null;
  phone: string | null;
  whatsapp: boolean;
  active: boolean;
  is_free: boolean;
};
type Company = { id: string; name: string };

export default async function AgentsPage() {
  const db = supabaseAdmin();
  const [{ data: agents, error }, { data: companies }, { data: joins }] =
    await Promise.all([
      db.from("agents").select("id,name,role,phone,whatsapp,active,is_free").order("name"),
      db.from("companies").select("id,name").order("name"),
      db.from("agent_companies").select("agent_id,company_id"),
    ]);

  const rows = (agents ?? []) as Agent[];
  const cos = (companies ?? []) as Company[];
  const coName = new Map(cos.map((c) => [c.id, c.name]));
  const byAgent = new Map<string, string[]>();
  for (const j of joins ?? []) {
    const r = j as { agent_id: string; company_id: string };
    byAgent.set(r.agent_id, [...(byAgent.get(r.agent_id) ?? []), r.company_id]);
  }

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Agents</h1>
        <p className="mt-1 text-sm text-mute">
          {rows.length} agents. Shown on the company page for calls & WhatsApp. Free agents map to many companies.
        </p>
      </header>

      {/* create */}
      <form
        action={createAgent}
        className="mb-6 flex flex-wrap items-end gap-2 rounded-xl border border-line bg-panel p-4"
      >
        <Field label="Name" name="name" placeholder="Jane Mwangi" required width="w-44" />
        <Field label="Role" name="role" placeholder="Relationship manager" width="w-52" />
        <Field label="Phone" name="phone" placeholder="+2547…" width="w-40" />
        <Check label="WhatsApp" name="whatsapp" />
        <Check label="Free agent" name="is_free" />
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">
          Add agent
        </button>
      </form>

      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">
          {error.message}
        </p>
      )}

      <div className="space-y-3">
        {rows.map((a) => {
          const assigned = byAgent.get(a.id) ?? [];
          const unassigned = cos.filter((c) => !assigned.includes(c.id));
          return (
            <div key={a.id} className="rounded-xl border border-line bg-panel p-4">
              <div className="flex flex-wrap items-center gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-ink">{a.name}</span>
                    {a.is_free && (
                      <span className="rounded border border-line px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-mute">
                        free
                      </span>
                    )}
                    {!a.active && (
                      <span className="rounded border border-faint/40 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-faint">
                        inactive
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-faint">
                    {[a.role, a.phone].filter(Boolean).join(" · ") || "—"}
                  </div>
                </div>

                <Flag id={a.id} field="whatsapp" on={a.whatsapp} label="WhatsApp" />
                <Flag id={a.id} field="active" on={a.active} label="Active" />
                <form action={deleteAgent}>
                  <input type="hidden" name="id" value={a.id} />
                  <button className="text-xs text-faint hover:text-bad">Delete</button>
                </form>
              </div>

              {/* company chips */}
              <div className="mt-3 flex flex-wrap items-center gap-2">
                {assigned.map((cid) => (
                  <form action={removeAgentCompany} key={cid}>
                    <input type="hidden" name="agent_id" value={a.id} />
                    <input type="hidden" name="company_id" value={cid} />
                    <button className="group flex items-center gap-1 rounded-full border border-line bg-panel2 px-2.5 py-1 text-xs text-mute hover:border-bad/50 hover:text-bad">
                      {coName.get(cid) ?? cid}
                      <span className="text-faint group-hover:text-bad"><IconX size={12} /></span>
                    </button>
                  </form>
                ))}
                {unassigned.length > 0 && (
                  <form action={addAgentCompany} className="flex items-center gap-1.5">
                    <input type="hidden" name="agent_id" value={a.id} />
                    <select
                      name="company_id"
                      defaultValue=""
                      className="rounded-md border border-line bg-panel2 px-2 py-1 text-xs text-mute outline-none focus:border-gold/60"
                    >
                      <option value="" disabled>Assign company…</option>
                      {unassigned.map((c) => (
                        <option key={c.id} value={c.id}>{c.name}</option>
                      ))}
                    </select>
                    <button className="rounded-md border border-line px-2 py-1 text-xs text-mute hover:border-gold/60 hover:text-gold">
                      Add
                    </button>
                  </form>
                )}
              </div>
            </div>
          );
        })}
        {rows.length === 0 && (
          <p className="rounded-xl border border-line bg-panel px-4 py-10 text-center text-sm text-mute">
            No agents yet.
          </p>
        )}
      </div>
    </div>
  );
}

function Field({
  label, name, placeholder, required, width,
}: { label: string; name: string; placeholder?: string; required?: boolean; width: string }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] uppercase tracking-wider text-faint">{label}</span>
      <input
        name={name}
        placeholder={placeholder}
        required={required}
        className={`${width} rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60`}
      />
    </label>
  );
}

function Check({ label, name }: { label: string; name: string }) {
  return (
    <label className="flex items-center gap-1.5 pb-1.5 text-sm text-mute">
      <input type="checkbox" name={name} className="accent-gold" />
      {label}
    </label>
  );
}

function Flag({ id, field, on, label }: { id: string; field: string; on: boolean; label: string }) {
  return (
    <form action={toggleAgentFlag}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="field" value={field} />
      <input type="hidden" name="value" value={(!on).toString()} />
      <button
        className={
          "rounded-md border px-2 py-1 text-xs " +
          (on ? "border-gold/50 bg-gold/10 text-gold" : "border-line text-faint hover:text-mute")
        }
      >
        {label}
      </button>
    </form>
  );
}

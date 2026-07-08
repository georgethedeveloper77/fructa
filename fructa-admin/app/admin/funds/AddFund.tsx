"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { addFund } from "./actions";
import { IconPlus, IconX } from "../_icons";

type Co = { id: string; name: string };

const TYPES: [string, string][] = [
  ["mmf", "Money Market"],
  ["fixed_income", "Fixed Income"],
  ["equity", "Equity"],
  ["balanced", "Balanced"],
  ["special", "Special"],
];
const CCY = ["KES", "USD", "GBP", "EUR", "ZAR"];

export function AddFund({ companies }: { companies: Co[] }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [companyId, setCompanyId] = useState("");
  const [type, setType] = useState("mmf");
  const [ccy, setCcy] = useState("KES");
  const [min, setMin] = useState("");
  const [fee, setFee] = useState("");
  const [pending, start] = useTransition();

  const sorted = useMemo(
    () => [...companies].sort((a, b) => a.name.localeCompare(b.name)),
    [companies],
  );
  const valid = name.trim() !== "" && companyId !== "";

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  function reset() {
    setName("");
    setCompanyId("");
    setType("mmf");
    setCcy("KES");
    setMin("");
    setFee("");
  }

  function submit() {
    if (!valid) return;
    const fd = new FormData();
    fd.set("name", name.trim());
    fd.set("company_id", companyId);
    fd.set("fund_type", type);
    fd.set("currency", ccy);
    if (min.trim()) fd.set("min_invest", min.trim());
    if (fee.trim()) fd.set("mgmt_fee", fee.trim());
    start(async () => {
      await addFund(fd);
      reset();
      setOpen(false);
    });
  }

  const field =
    "w-full rounded-md border border-line bg-panel2 px-3 py-2 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
  const label = "mb-1 block text-[11px] uppercase tracking-wider text-faint";

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1.5 rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-sm font-medium text-gold hover:bg-gold/20"
      >
        <IconPlus size={14} /> Create fund
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) setOpen(false);
          }}
        >
          <div className="w-full max-w-md rounded-xl border border-line bg-panel p-5 shadow-xl">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-base font-semibold text-ink">Create fund</h2>
              <button onClick={() => setOpen(false)} className="text-faint hover:text-ink" aria-label="Close">
                <IconX size={16} />
              </button>
            </div>

            <div className="space-y-3">
              <div>
                <label className={label}>Fund name</label>
                <input
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="AA Kenya Money Market Fund"
                  className={field}
                />
              </div>

              <div>
                <label className={label}>Company</label>
                <select value={companyId} onChange={(e) => setCompanyId(e.target.value)} className={field}>
                  <option value="">Choose a company…</option>
                  {sorted.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
                <p className="mt-1 text-[11px] text-faint">The fund manager. Not listed? Add it under Companies first.</p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={label}>Type</label>
                  <select value={type} onChange={(e) => setType(e.target.value)} className={field}>
                    {TYPES.map(([k, l]) => (
                      <option key={k} value={k}>
                        {l}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className={label}>Currency</label>
                  <select value={ccy} onChange={(e) => setCcy(e.target.value)} className={field}>
                    {CCY.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={label}>Min invest (optional)</label>
                  <input
                    inputMode="numeric"
                    value={min}
                    onChange={(e) => setMin(e.target.value)}
                    placeholder="100000"
                    className={field + " tnum"}
                  />
                </div>
                <div>
                  <label className={label}>Mgmt fee % (optional)</label>
                  <input
                    inputMode="decimal"
                    value={fee}
                    onChange={(e) => setFee(e.target.value)}
                    placeholder="2.00"
                    className={field + " tnum"}
                  />
                </div>
              </div>

              <p className="text-[11px] text-faint">
                Created live and in-app with no rate yet — set it on the row, or let the bulk importer fill it. Min and
                fee can also come from the importer.
              </p>
            </div>

            <div className="mt-5 flex items-center justify-end gap-3">
              <button onClick={() => setOpen(false)} disabled={pending} className="text-sm text-faint hover:text-mute">
                Cancel
              </button>
              <button
                onClick={submit}
                disabled={!valid || pending}
                className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {pending ? "Creating…" : "Create fund"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

"use client";

import { useEffect, useState, useTransition } from "react";
import { addSacco } from "./actions";
import { IconPlus, IconX } from "../_icons";

// Deposit-taking is first and is the default, because it is the only class that
// belongs in a rates product: a credit-only society is prohibited by law from
// taking new deposits, so a savings rate next to its name would be a rate on
// money it cannot accept.
const CLASSES: [string, string][] = [
  ["dt", "Deposit taking (Schedule I)"],
  ["nwdt", "Non deposit taking, BOSA only (Schedule II)"],
  ["credit_only", "Credit only, restricted (Schedule III)"],
];

export function AddSacco() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [county, setCounty] = useState("");
  const [cls, setCls] = useState("dt");
  const [pending, start] = useTransition();

  const valid = name.trim() !== "";

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  function reset() {
    setName("");
    setDisplayName("");
    setCounty("");
    setCls("dt");
  }

  function submit() {
    if (!valid) return;
    const fd = new FormData();
    fd.set("name", name.trim());
    if (displayName.trim()) fd.set("display_name", displayName.trim());
    if (county.trim()) fd.set("county", county.trim());
    fd.set("licence_class", cls);
    start(async () => {
      await addSacco(fd);
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
        <IconPlus size={14} /> Add SACCO
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
              <h2 className="text-base font-semibold text-ink">Add SACCO</h2>
              <button
                onClick={() => setOpen(false)}
                className="text-faint hover:text-ink"
                aria-label="Close"
              >
                <IconX size={16} />
              </button>
            </div>

            <div className="space-y-3">
              <div>
                <label className={label}>Registered name</label>
                <input
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Tower Sacco Society Ltd"
                  className={field}
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={label}>Display name</label>
                  <input
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                    placeholder="Tower Sacco"
                    className={field}
                  />
                </div>
                <div>
                  <label className={label}>County</label>
                  <input
                    value={county}
                    onChange={(e) => setCounty(e.target.value)}
                    placeholder="Nyandarua"
                    className={field}
                  />
                </div>
              </div>

              <div>
                <label className={label}>Licence class</label>
                <select
                  value={cls}
                  onChange={(e) => setCls(e.target.value)}
                  className={field}
                >
                  {CLASSES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </div>

              <p className="text-[11px] leading-relaxed text-faint">
                The common bond starts as <span className="text-warn">unknown</span>{" "}
                and the app treats unknown as not joinable. SASRA does not publish
                it, so it has to be confirmed against the society&apos;s own terms
                and set on the edit page. Rates, joining terms and institution
                figures are set there too.
              </p>
            </div>

            <div className="mt-5 flex items-center justify-end gap-3">
              <button
                onClick={() => setOpen(false)}
                disabled={pending}
                className="text-sm text-faint hover:text-mute"
              >
                Cancel
              </button>
              <button
                onClick={submit}
                disabled={!valid || pending}
                className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {pending ? "Adding" : "Add SACCO"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

"use client";

import { useState, useTransition } from "react";
import { applyFactsheet, type ApplyResult } from "./actions";

/// Apply, then say what actually happened.
///
/// Not a plain form button, because "applied" is not the useful answer. A
/// reviewer needs to see that the rate points were skipped as stale while the
/// minimum investment went through, which is a partial outcome a redirect would
/// hide. The skipped list is the half worth reading.
export function ApplyButton({ id, disabled }: { id: number; disabled: boolean }) {
  const [res, setRes] = useState<ApplyResult | null>(null);
  const [pending, start] = useTransition();

  const go = (fd: FormData) => start(async () => setRes(await applyFactsheet(fd)));

  if (res && res.ok) {
    return (
      <div className="w-full space-y-1 text-xs">
        <div className="text-live">Applied.</div>
        {res.applied.map((a, i) => (
          <div key={i} className="text-faint">wrote {a}</div>
        ))}
        {res.skipped.map((s, i) => (
          <div key={i} className="text-warn">skipped {s}</div>
        ))}
      </div>
    );
  }

  return (
    <div className="flex flex-col items-end gap-1">
      {res?.error && <span className="text-xs text-bad">{res.error}</span>}
      <form action={go}>
        <input type="hidden" name="id" value={id} />
        <button
          disabled={disabled || pending}
          className={
            "rounded-md border px-3 py-1.5 text-xs " +
            (disabled
              ? "border-line text-faint opacity-50"
              : "border-gold bg-gold/10 text-gold hover:bg-gold/20")
          }
        >
          {pending ? "Applying" : "Apply"}
        </button>
      </form>
    </div>
  );
}

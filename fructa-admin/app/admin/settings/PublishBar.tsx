"use client";

import { useState, useTransition } from "react";
import { republishNow } from "./actions";

/*
 * Every save on this page republishes the snapshot, so the snapshot's state
 * belongs at the top of it rather than being implied by a button label. The bar
 * does not claim a "last published" time, because nothing in app_config records
 * one; it reports what it actually knows, and what it just did.
 */
export function PublishBar() {
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  function go() {
    setMsg(null);
    start(async () => {
      const r = await republishNow();
      setMsg(r.ok ? { ok: true, text: "Republished" } : { ok: false, text: r.error ?? "Failed" });
    });
  }

  return (
    <div className="flex items-center gap-2.5 rounded-lg border border-line bg-panel px-3 py-1.5">
      <span
        className={
          "h-1.5 w-1.5 rounded-full " +
          (msg && !msg.ok ? "bg-bad" : "bg-live shadow-[0_0_0_3px_rgba(61,220,151,0.13)]")
        }
      />
      <span className="text-[11.5px] text-mute">
        {pending ? (
          "Republishing the snapshot"
        ) : msg ? (
          <span className={msg.ok ? "text-live" : "text-bad"}>{msg.text}</span>
        ) : (
          <>
            Snapshot rebuilds on <span className="text-ink">every save</span>
          </>
        )}
      </span>
      <span className="h-3.5 w-px bg-line2" />
      <button
        onClick={go}
        disabled={pending}
        className="text-[11.5px] font-semibold text-gold hover:underline disabled:opacity-40"
      >
        Republish now
      </button>
    </div>
  );
}

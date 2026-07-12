"use client";

import { useState } from "react";
import { saveStats } from "./actions";
import { SettingsForm } from "./SettingsForm";
import { input } from "./ui";

/*
 * The four figures on the landing band. The strip underneath renders them the
 * way the page does, including greying an empty pair as "not shown", so the drop
 * behaviour is visible rather than described in a note nobody reads.
 */
type Stat = { n: string; l: string };

export function StatBand({ initial }: { initial: Stat[] }) {
  const [rows, setRows] = useState<Stat[]>(() =>
    Array.from({ length: 4 }, (_, i) => ({ n: initial[i]?.n ?? "", l: initial[i]?.l ?? "" })),
  );

  const set = (i: number, k: keyof Stat) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setRows((s) => s.map((r, j) => (j === i ? { ...r, [k]: e.target.value } : r)));

  const clear = (i: number) => setRows((s) => s.map((r, j) => (j === i ? { n: "", l: "" } : r)));

  return (
    <SettingsForm action={saveStats}>
      <div className="space-y-2">
        {rows.map((r, i) => (
          <div key={i} className="grid grid-cols-[22px_112px_1fr_26px] items-center gap-2.5">
            <span className="text-center font-mono text-[11px] text-faint">{String(i + 1).padStart(2, "0")}</span>
            <input
              name={`stat_${i}_n`}
              value={r.n}
              onChange={set(i, "n")}
              placeholder="Figure"
              className={input + (r.n || r.l ? "" : " border-dashed")}
            />
            <input
              name={`stat_${i}_l`}
              value={r.l}
              onChange={set(i, "l")}
              placeholder="Label"
              className={input + (r.n || r.l ? "" : " border-dashed")}
            />
            <button
              type="button"
              onClick={() => clear(i)}
              aria-label={`Clear figure ${i + 1}`}
              className="text-faint hover:text-bad"
            >
              <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round">
                <path d="M18 6 6 18M6 6l12 12" />
              </svg>
            </button>
          </div>
        ))}
      </div>

      <div className="mt-4 grid grid-cols-4 gap-px overflow-hidden rounded-xl border border-line bg-line">
        {rows.map((r, i) => {
          const off = !r.n && !r.l;
          return (
            <div key={i} className={"bg-bg px-3 py-3.5 text-center " + (off ? "opacity-35" : "")}>
              <div className="font-mono text-[19px] font-semibold text-gold">{r.n || "..."}</div>
              <div className="mt-0.5 text-[10.5px] leading-tight text-faint">{r.l || "not shown"}</div>
            </div>
          );
        })}
      </div>
    </SettingsForm>
  );
}

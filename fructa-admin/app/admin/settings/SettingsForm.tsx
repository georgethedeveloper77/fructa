"use client";

import { useState, useTransition } from "react";

/*
 * Gives a section's Save button real state: idle, saving, saved or the actual
 * error text. The section actions throw on failure and return void on success,
 * so a try/catch around the call is all this needs; actions.ts is untouched and
 * its writers stay field-scoped.
 *
 * Save stays disabled until something actually changes, so the button tells you
 * whether there is anything to save. Inputs stay uncontrolled unless the section
 * needs a live preview, and FormData is read off the form on submit either way.
 */
export function SettingsForm({
  action,
  children,
  hint = "Saving republishes the snapshot.",
}: {
  action: (fd: FormData) => Promise<void>;
  children: React.ReactNode;
  hint?: string;
}) {
  const [pending, start] = useTransition();
  const [dirty, setDirty] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    setMsg(null);
    start(async () => {
      try {
        await action(fd);
        setDirty(false);
        setMsg({ ok: true, text: "Saved" });
      } catch (err) {
        setMsg({ ok: false, text: err instanceof Error ? err.message : "Could not save" });
      }
    });
  }

  return (
    <form
      onSubmit={onSubmit}
      onChange={() => {
        setDirty(true);
        setMsg(null);
      }}
    >
      <div className="px-5 py-5">{children}</div>

      <div className="flex items-center gap-4 border-t border-line bg-raise px-5 py-3">
        <span className="text-[11.5px] text-faint">{hint}</span>
        <div className="ml-auto flex items-center gap-3">
          {msg && (
            <span className={"text-[11.5px] " + (msg.ok ? "text-live" : "text-bad")}>{msg.text}</span>
          )}
          <button
            disabled={pending || !dirty}
            className="rounded-lg border border-gold bg-gold px-3.5 py-1.5 text-xs font-semibold text-[#191204] hover:brightness-110 disabled:cursor-default disabled:opacity-40"
          >
            {pending ? "Saving" : "Save changes"}
          </button>
        </div>
      </div>
    </form>
  );
}

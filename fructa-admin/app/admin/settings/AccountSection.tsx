"use client";

import { useEffect, useState, useTransition } from "react";
import { supabaseBrowser } from "@/lib/supabase/auth-browser";
import { input } from "./ui";

const btn =
  "rounded-lg border border-line2 bg-transparent px-3 py-1.5 text-xs font-medium text-mute hover:border-gold hover:text-gold disabled:opacity-40";

function Note({ m }: { m: { ok: boolean; text: string } | null }) {
  if (!m) return null;
  return <p className={"text-[11.5px] " + (m.ok ? "text-live" : "text-bad")}>{m.text}</p>;
}

export function AccountSection() {
  const [email, setEmail] = useState<string>("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [pwMsg, setPwMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [newEmail, setNewEmail] = useState("");
  const [emMsg, setEmMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, start] = useTransition();

  useEffect(() => {
    supabaseBrowser()
      .auth.getUser()
      .then(({ data }) => setEmail(data.user?.email ?? ""));
  }, []);

  function changePassword() {
    setPwMsg(null);
    if (pw.length < 8) return setPwMsg({ ok: false, text: "Use at least 8 characters." });
    if (pw !== pw2) return setPwMsg({ ok: false, text: "The two passwords do not match." });
    start(async () => {
      const { error } = await supabaseBrowser().auth.updateUser({ password: pw });
      if (error) return setPwMsg({ ok: false, text: error.message });
      setPw("");
      setPw2("");
      setPwMsg({ ok: true, text: "Password updated." });
    });
  }

  function changeEmail() {
    setEmMsg(null);
    if (!/.+@.+\..+/.test(newEmail)) return setEmMsg({ ok: false, text: "Enter a valid email address." });
    start(async () => {
      const { error } = await supabaseBrowser().auth.updateUser({ email: newEmail });
      if (error) return setEmMsg({ ok: false, text: error.message });
      setEmMsg({
        ok: true,
        text: "Confirmation sent. Set ADMIN_EMAIL to the new address and redeploy once you have confirmed.",
      });
    });
  }

  const initials =
    email
      .split("@")[0]
      .split(/[.\-_]/)
      .map((p) => p[0])
      .join("")
      .slice(0, 2)
      .toUpperCase() || "..";

  return (
    <section id="account" className="scroll-mt-24 overflow-hidden rounded-2xl border border-line bg-panel">
      <div className="flex items-start gap-3 px-5 pt-5">
        <div>
          <h2 className="text-[15px] font-semibold tracking-tight text-ink">Account</h2>
          <p className="mt-1 text-[12.5px] text-mute">Your admin login. This address is also the owner allowlist.</p>
        </div>
        <span className="ml-auto flex-none rounded bg-panel2 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-faint">
          Private
        </span>
      </div>

      <div className="px-5 py-5">
        <div className="mb-5 flex items-center gap-3 rounded-xl border border-line bg-panel2 px-3 py-2.5">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-gold/10 font-mono text-xs font-semibold text-gold">
            {initials}
          </span>
          <span className="text-[13px] text-ink">{email || "Loading"}</span>
          <span className="ml-auto rounded bg-gold/10 px-2 py-0.5 text-[9.5px] font-semibold uppercase tracking-wide text-gold">
            Owner
          </span>
        </div>

        <div className="grid gap-0 md:grid-cols-2">
          <div className="space-y-2.5 md:border-r md:border-line md:pr-6">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-faint">Change password</p>
            <input
              type="password"
              value={pw}
              onChange={(e) => setPw(e.target.value)}
              placeholder="New password"
              autoComplete="new-password"
              className={input}
            />
            <input
              type="password"
              value={pw2}
              onChange={(e) => setPw2(e.target.value)}
              placeholder="Confirm new password"
              autoComplete="new-password"
              className={input}
            />
            <div className="flex items-center gap-3 pt-0.5">
              <button onClick={changePassword} disabled={busy} className={btn}>
                Update password
              </button>
              <Note m={pwMsg} />
            </div>
          </div>

          <div className="mt-6 space-y-2.5 md:mt-0 md:pl-6">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-faint">Change login email</p>
            <input
              type="email"
              value={newEmail}
              onChange={(e) => setNewEmail(e.target.value)}
              placeholder="new@email.com"
              className={input}
            />
            <div className="flex gap-2 rounded-lg border border-warn/30 bg-warn/5 px-2.5 py-2 text-[11.5px] leading-relaxed text-warn">
              <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className="mt-0.5 flex-none">
                <path d="M12 9v4M12 17h.01M10.3 3.9 2 18a2 2 0 0 0 1.7 3h16.6a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z" />
              </svg>
              <span>
                After you confirm, set the ADMIN_EMAIL secret to the new address and redeploy, or you will be
                locked out.
              </span>
            </div>
            <div className="flex items-center gap-3 pt-0.5">
              <button onClick={changeEmail} disabled={busy} className={btn}>
                Send confirmation
              </button>
              <Note m={emMsg} />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

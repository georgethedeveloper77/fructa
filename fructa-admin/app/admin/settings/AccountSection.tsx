"use client";

import { useEffect, useState, useTransition } from "react";
import { supabaseBrowser } from "@/lib/supabase/auth-browser";
import { IconCheck } from "../_icons";

const input =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const btn =
  "rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40";

function Note({ m }: { m: { ok: boolean; text: string } | null }) {
  if (!m) return null;
  return (
    <span className={"inline-flex items-center gap-1 text-[11px] " + (m.ok ? "text-live" : "text-bad")}>
      {m.ok && <IconCheck size={11} />}
      {m.text}
    </span>
  );
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
    if (pw !== pw2) return setPwMsg({ ok: false, text: "Passwords don't match." });
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
    if (!/.+@.+\..+/.test(newEmail)) return setEmMsg({ ok: false, text: "Enter a valid email." });
    start(async () => {
      const { error } = await supabaseBrowser().auth.updateUser({ email: newEmail });
      if (error) return setEmMsg({ ok: false, text: error.message });
      setEmMsg({
        ok: true,
        text: "Confirmation sent. After confirming, update the ADMIN_EMAIL secret to match, then redeploy.",
      });
    });
  }

  return (
    <section className="rounded-xl border border-line bg-panel p-5">
      <div className="mb-4">
        <h2 className="text-sm font-semibold text-ink">Account</h2>
        <p className="mt-0.5 text-xs text-mute">
          Signed in as <span className="text-ink">{email || "…"}</span>
        </p>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        {/* password */}
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-wider text-faint">Change password</p>
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
          <div className="flex items-center gap-3">
            <button onClick={changePassword} disabled={busy} className={btn}>
              Update password
            </button>
            <Note m={pwMsg} />
          </div>
        </div>

        {/* email */}
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-wider text-faint">Change login email</p>
          <input
            type="email"
            value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)}
            placeholder="new@email.com"
            className={input}
          />
          <p className="rounded-md border border-warn/30 bg-warn/5 px-2.5 py-1.5 text-[11px] leading-relaxed text-warn">
            The login email is also the owner allowlist. After the confirmation link, you must set
            the ADMIN_EMAIL secret to the new address and redeploy, or you'll be locked out.
          </p>
          <div className="flex items-center gap-3">
            <button onClick={changeEmail} disabled={busy} className={btn}>
              Send confirmation
            </button>
            <Note m={emMsg} />
          </div>
        </div>
      </div>
    </section>
  );
}

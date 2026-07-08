"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/auth-browser";

export default function Console() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const { error } = await supabaseBrowser().auth.signInWithPassword({ email, password });
    setLoading(false);
    if (error) {
      setError(error.message);
      return;
    }
    router.push("/admin");
    router.refresh();
  }

  return (
    <main className="flex min-h-screen items-center justify-center px-6">
      <form onSubmit={onSubmit} className="w-full max-w-sm rounded-2xl border border-line bg-panel p-7">
        <div className="mb-6">
          <span className="text-lg font-bold tracking-tight text-ink">fructa</span>
          <span className="text-lg font-bold text-gold"> .</span>
          <p className="mt-0.5 text-[11px] uppercase tracking-widest text-faint">admin</p>
        </div>

        <label className="mb-3 block text-sm">
          <span className="mb-1 block text-xs text-mute">Email</span>
          <input
            type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus
            className="w-full rounded-lg border border-line bg-panel2 px-3 py-2 text-ink outline-none focus:border-gold/60"
          />
        </label>
        <label className="mb-4 block text-sm">
          <span className="mb-1 block text-xs text-mute">Password</span>
          <input
            type="password" value={password} onChange={(e) => setPassword(e.target.value)} required
            className="w-full rounded-lg border border-line bg-panel2 px-3 py-2 text-ink outline-none focus:border-gold/60"
          />
        </label>

        {error && <p className="mb-3 text-sm text-bad">{error}</p>}

        <button
          disabled={loading}
          className="w-full rounded-lg bg-gold px-4 py-2 text-sm font-medium text-black hover:bg-gold/90 disabled:opacity-60"
        >
          {loading ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </main>
  );
}

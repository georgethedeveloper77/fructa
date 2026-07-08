import { createBrowserClient } from "@supabase/ssr";

// Cookie-based auth client for client components (login, sign-out).
// Uses the public (publishable/anon) key — never the secret.
export function supabaseBrowser() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}

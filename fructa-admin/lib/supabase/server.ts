import { createClient } from "@supabase/supabase-js";

// Service-role client — SERVER ONLY. Bypasses RLS; full read/write.
// Never import this into a client component.
export const supabaseAdmin = () => {
  // The URL is public — reuse the NEXT_PUBLIC value so /admin doesn't depend on
  // a second, separately-configured SUPABASE_URL (that mismatch was 500-ing the
  // admin route). Only the service-role KEY is secret, injected via Secret Manager.
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error(
      "supabaseAdmin: missing SUPABASE_URL/NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY",
    );
  }

  return createClient(url, key, { auth: { persistSession: false } });
};

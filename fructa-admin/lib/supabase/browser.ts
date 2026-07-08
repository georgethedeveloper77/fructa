import { createClient } from "@supabase/supabase-js";

// Anon client — safe for the browser. Reads are RLS-guarded; writes are denied.
export const supabaseBrowser = () =>
  createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

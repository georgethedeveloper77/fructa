import { supabaseAdmin } from '@/lib/supabase/server';
import { DEFAULT_CONTENT, applyConfig, type LandingContent } from './content';

// Reads the brand/seo/links/landing.* keys from app_config and merges them over
// the shipped defaults. Same source the admin edits and the snapshot publishes.
// Fails safe to defaults so the public page can never break on a bad read.
export async function getLandingContent(): Promise<LandingContent> {
  try {
    const db = supabaseAdmin();
    const { data } = await db.from('app_config').select('key,value');
    if (!data) return DEFAULT_CONTENT;
    const rows = (data as { key: string; value: unknown }[]).filter((r) =>
      /^(brand|seo|links|landing)\./.test(r.key),
    );
    return applyConfig(rows);
  } catch {
    return DEFAULT_CONTENT;
  }
}

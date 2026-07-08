class Config {
  static const supabaseUrl = 'https://lxtyrtgyfrhxyjraroku.supabase.co';

  // Publishable (anon) key  safe to ship in the app; RLS protects the data.
  // Only used for the lazy rate_history calls; the snapshot is public storage.
  static const anonKey = 'sb_publishable_Nn3p9o-iA2wzcZ8sfev1qw_PkkOcNtl';

  static String get snapshotUrl =>
      '$supabaseUrl/storage/v1/object/public/snapshots/funds-snapshot.json';
  static String get restBase => '$supabaseUrl/rest/v1';
  static String get functionsBase => '$supabaseUrl/functions/v1';
}

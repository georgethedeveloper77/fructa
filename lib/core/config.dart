class Config {
  static const supabaseUrl = 'https://lxtyrtgyfrhxyjraroku.supabase.co';

  // Publishable (anon) key  safe to ship in the app; RLS protects the data.
  // Only used for the lazy rate_history calls; the snapshot is public storage.
  static const anonKey = 'sb_publishable_Nn3p9o-iA2wzcZ8sfev1qw_PkkOcNtl';

  static String get snapshotUrl =>
      '$supabaseUrl/storage/v1/object/public/snapshots/funds-snapshot.json';
  static String get restBase => '$supabaseUrl/rest/v1';
  static String get functionsBase => '$supabaseUrl/functions/v1';

  // ── Fructa Pro (RevenueCat) ────────────────────────────────────────────────
  //
  // Public SDK keys, one per store, from RevenueCat > Project > API keys. They
  // are designed to ship inside the binary: they can read offerings and start
  // purchases, never grant access. Leave the placeholder in and ProService
  // stays dormant, so a build without keys runs exactly as it does today.
  static const revenueCatAppleKey = 'appl_DKAYwFhNVvKaIyNdEDCgCKjkxME';
  static const revenueCatGoogleKey = 'goog_QBZwVPDseNAWKgQVICctkYFeVQT';

  /// Entitlement identifier configured in RevenueCat. Every Pro check in the
  /// app asks about this one name, never about a product id, so adding a plan
  /// later is a dashboard change rather than a release.
  static const proEntitlement = 'pro';

  /// Store product identifiers, kept here for reference and diagnostics only.
  /// The paywall reads packages from the RevenueCat offering, not these ids.
  static const proMonthlyAppleId = 'com.mindberzerk.fructa.pro.monthly';
  static const proAnnualAppleId = 'com.mindberzerk.fructa.pro.annual';
  static const proGoogleProductId = 'fructa_pro';

  /// Store subscription management pages, used when RevenueCat does not hand
  /// back a management URL (sandbox, or before the first purchase syncs).
  static const appleManageSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';
  static const googleManageSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions'
      '?sku=fructa_pro&package=com.mindberzerk.fructa';
}

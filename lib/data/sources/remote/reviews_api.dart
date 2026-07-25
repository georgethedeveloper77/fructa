import 'package:flutter/foundation.dart';
import 'package:fructa/data/models/insurer_review.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reviews are the ONE part of Fructa that does not ride the snapshot.
///
/// Everything else in the app reads a static JSON file published by
/// publish-snapshot, which is right for rates: they change on a schedule and a
/// cached read is a feature. Reviews cannot work that way. A user who posts a
/// rating must see it immediately, and a moderator who approves a body must not
/// have to trigger a snapshot rebuild for those words to appear. So this talks
/// to Postgres directly, through RLS.
///
/// Identity is ANONYMOUS auth: a stable per-device UUID with no name, email or
/// phone behind it. That is enough to enforce one review per person per
/// insurer, to let an author edit their own words, and to let an admin block an
/// abusive device (Apple Guideline 1.2) without Fructa ever holding personal
/// data.
class ReviewsApi {
  /// Why the last read came back empty, or null when nothing has gone wrong.
  ///
  /// EVERY method here degrades to an empty result rather than throwing, which
  /// is the right call on a page that must not show a red box, and which had
  /// one cost: five different failures all rendered as "nobody has reviewed
  /// yet". Supabase never initialised, the public view missing its grant to
  /// anon, RLS refusing the read, the network down, and a genuinely unreviewed
  /// insurer were indistinguishable from each other and from success.
  ///
  /// The behaviour is unchanged. The reason is now recorded, and printed in
  /// debug, so the next run says which of the five it is instead of leaving it
  /// to be guessed at from an empty section.
  String? lastError;

  T _fail<T>(String where, Object e, T fallback) {
    lastError = '$where: $e';
    if (kDebugMode) debugPrint('[reviews] $lastError');
    return fallback;
  }

  /// Null until Supabase.initialize has run in main(). This is the single most
  /// likely reason the section is absent: it gates every method below and it
  /// makes `available` false, which hides the whole section by design.
  SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return _fail('Supabase.instance', e, null);
    }
  }

  bool get available => _db != null;

  /// One line naming what is wrong, for the settings diagnostics panel or a
  /// debug print. Does not touch the network.
  String get diagnosis {
    if (_db == null) {
      return 'Supabase is not initialised. Reviews are hidden.';
    }
    final e = lastError;
    if (e != null) return e;
    return 'Reviews are reachable.';
  }

  /// Sign in anonymously if we have not already. Idempotent, and safe to call
  /// before any write.
  Future<String?> ensureSession() async {
    final db = _db;
    if (db == null) return null;
    final existing = db.auth.currentUser;
    if (existing != null) return existing.id;
    try {
      final res = await db.auth.signInAnonymously();
      return res.user?.id;
    } catch (e) {
      return _fail('ensureSession', e, null);
    }
  }

  /// Aggregate for the histogram. Absent row means nobody has reviewed yet,
  /// which is a real state, not an error.
  Future<ReviewStats> stats(String insurerId) async {
    final db = _db;
    if (db == null) return ReviewStats.empty;
    try {
      final row = await db
          .from('insurer_review_stats')
          .select()
          .eq('insurer_id', insurerId)
          .maybeSingle();
      if (row == null) return ReviewStats.empty;
      lastError = null;
      return ReviewStats.fromJson(row);
    } catch (e) {
      // A definer view still needs its own grant. If `insurer_review_stats`
      // was never granted to anon this is a permission error, and it looks
      // exactly like an insurer nobody has rated.
      return _fail('stats(insurer_review_stats)', e, ReviewStats.empty);
    }
  }

  /// The public list. Reads the VIEW, never the table: the view is what nulls
  /// an unapproved body, and reading the table directly would defeat the whole
  /// moderation model.
  ///
  /// Reviews carrying words come first. A wall of bare stars tells a reader
  /// nothing; "the assessor came the same week" is the reason anyone scrolls
  /// here.
  Future<List<InsurerReview>> list(String insurerId, {int limit = 20}) async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await db
          .from('insurer_reviews_public')
          .select()
          .eq('insurer_id', insurerId)
          .order('created_at', ascending: false)
          .limit(limit);
      final all = (rows as List)
          .map(
            (r) => InsurerReview.fromJson((r as Map).cast<String, dynamic>()),
          )
          .toList();
      all.sort((a, b) {
        if (a.hasBody != b.hasBody) return a.hasBody ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      lastError = null;
      return all;
    } catch (e) {
      return _fail('list(insurer_reviews_public)', e, const <InsurerReview>[]);
    }
  }

  /// The caller's own row, if they have one. RLS restricts SELECT on the base
  /// table to auth.uid() = author_id, so this can only ever return the caller's
  /// review; it is also the only path by which body_status is visible.
  Future<MyReview?> mine(String insurerId) async {
    final db = _db;
    if (db == null || db.auth.currentUser == null) return null;
    try {
      final row = await db
          .from('insurer_reviews')
          .select('id,rating,body,body_status,reject_reason,claims_holder')
          .eq('insurer_id', insurerId)
          .eq('author_id', db.auth.currentUser!.id)
          .maybeSingle();
      if (row == null) return null;
      return MyReview.fromJson(row);
    } catch (e) {
      return _fail('mine', e, null);
    }
  }

  /// Write or replace the caller's review.
  ///
  /// Upsert on (insurer_id, author_id): one review per person per insurer, and
  /// editing REPLACES rather than stacking. The body_status is deliberately not
  /// set here. A database trigger owns it, because a client that could set its
  /// own body to 'approved' would make the entire moderation queue decorative.
  /// The same trigger re-queues an edited body, so nobody can get bland text
  /// approved and then quietly rewrite it into an accusation.
  Future<bool> submit({
    required String insurerId,
    required int rating,
    String? body,
    bool claimsHolder = false,
  }) async {
    final db = _db;
    if (db == null) return false;
    final uid = await ensureSession();
    if (uid == null) return false;

    final text = body?.trim();
    try {
      await db.from('insurer_reviews').upsert({
        'insurer_id': insurerId,
        'author_id': uid,
        'rating': rating,
        'body': (text == null || text.isEmpty) ? null : text,
        'claims_holder': claimsHolder,
      }, onConflict: 'insurer_id,author_id');
      return true;
    } catch (e) {
      return _fail('submit', e, false);
    }
  }

  Future<bool> remove(String reviewId) async {
    final db = _db;
    if (db == null || db.auth.currentUser == null) return false;
    try {
      await db.from('insurer_reviews').delete().eq('id', reviewId);
      return true;
    } catch (e) {
      return _fail('remove', e, false);
    }
  }

  /// Flag a review. Three distinct reporters auto-hides it pending an admin
  /// look: an approved body can still turn out to be defamatory, and "we
  /// removed it within the hour" is a materially better legal position than "we
  /// reviewed it and left it up".
  ///
  /// A duplicate report from the same device violates a unique constraint and
  /// returns false, which the UI reads as "already reported".
  Future<bool> report(
    String reviewId,
    ReportReason reason, {
    String? note,
  }) async {
    final db = _db;
    if (db == null) return false;
    final uid = await ensureSession();
    if (uid == null) return false;
    try {
      await db.from('review_reports').insert({
        'review_id': reviewId,
        'reporter_id': uid,
        'reason': reason.key,
        'note': note,
      });
      return true;
    } catch (e) {
      return _fail('report', e, false);
    }
  }
}

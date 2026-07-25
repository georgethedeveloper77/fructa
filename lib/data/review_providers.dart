import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/insurer_review.dart';
import 'sources/remote/reviews_api.dart';

/// Reviews live outside the snapshot, so they get their own providers rather
/// than hanging off snapshotExtrasProvider. They are autoDispose + family: a
/// review list is per-insurer and should not be held once the page is gone.

final reviewsApiProvider = Provider<ReviewsApi>((ref) => ReviewsApi());

/// True only when Supabase.initialize has actually run. The review section
/// hides itself when this is false, so a missing init degrades to "no reviews
/// section" rather than a red error box on the insurer page.
final reviewsAvailableProvider = Provider<bool>(
  (ref) => ref.watch(reviewsApiProvider).available,
);

final reviewStatsProvider = FutureProvider.autoDispose
    .family<ReviewStats, String>(
      (ref, insurerId) => ref.watch(reviewsApiProvider).stats(insurerId),
    );

final insurerReviewsProvider = FutureProvider.autoDispose
    .family<List<InsurerReview>, String>(
      (ref, insurerId) => ref.watch(reviewsApiProvider).list(insurerId),
    );

/// The caller's own review, which is the only way body_status reaches the UI.
/// Drives "your words are with a moderator, your rating is already counted".
final myReviewProvider = FutureProvider.autoDispose.family<MyReview?, String>(
  (ref, insurerId) => ref.watch(reviewsApiProvider).mine(insurerId),
);

/// Refresh all three after a write. Called once, so the histogram, the list and
/// the author's own status can never disagree with each other.
void invalidateReviews(WidgetRef ref, String insurerId) {
  ref.invalidate(reviewStatsProvider(insurerId));
  ref.invalidate(insurerReviewsProvider(insurerId));
  ref.invalidate(myReviewProvider(insurerId));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/insurer.dart';
import '../../data/models/insurer_review.dart';
import '../../data/review_providers.dart';
import 'insure_common.dart';

/// The reviews surface on an insurer page.
///
/// Placed BELOW the trust panel and the price, deliberately and permanently.
/// A GCR rating and a stranger's opinion are different kinds of thing, and the
/// page says so by its order: facts rank, opinions colour. Reviews never touch
/// the sort order of a quote, never feed the trust panel, and never sit above
/// the rating.
class InsurerReviews extends ConsumerWidget {
  const InsurerReviews(this.insurer, {super.key});

  final Insurer insurer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(reviewsAvailableProvider)) return const SizedBox.shrink();

    final stats = ref.watch(reviewStatsProvider(insurer.id));
    final list = ref.watch(insurerReviewsProvider(insurer.id));
    final mine = ref.watch(myReviewProvider(insurer.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsureH2(t('insure.review.title'), small: t('insure.review.sub')),
        stats.when(
          loading: () => const _Skeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (s) => s.isEmpty
              ? _Empty(insurer: insurer)
              : _Histogram(stats: s, reviews: list.value ?? const []),
        ),
        mine.maybeWhen(
          data: (m) => m == null
              ? const SizedBox.shrink()
              : _MyStatus(review: m, insurer: insurer),
          orElse: () => const SizedBox.shrink(),
        ),
        list.maybeWhen(
          data: (rs) {
            // Claim first, then words, then newest. The API already floats
            // reviews that carry words, which was right as far as it went: a
            // wall of bare stars tells a reader nothing. But in insurance the
            // sharper cut is whether the writer ever tested the cover. Five
            // stars from a policy nobody has claimed on is the least
            // informative thing on this page, however recent it is.
            final ordered = [...rs]
              ..sort((a, b) {
                if (a.claimsHolder != b.claimsHolder) {
                  return a.claimsHolder ? -1 : 1;
                }
                if (a.hasBody != b.hasBody) return a.hasBody ? -1 : 1;
                return b.createdAt.compareTo(a.createdAt);
              });
            return Column(
              children: [
                for (var k = 0; k < ordered.length; k++)
                  _ReviewCard(
                    review: ordered[k],
                    insurer: insurer,
                    index: k,
                  ),
              ],
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
        mine.maybeWhen(
          data: (m) => _WriteCta(insurer: insurer, existing: m),
          orElse: () => const SizedBox.shrink(),
        ),
        InsureFoot(t('insure.review.disclaimer')),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 118,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.line),
        ),
        child: Column(
          children: [
            Icon(Icons.rate_review_outlined, size: 26, color: c.faint),
            const SizedBox(height: 12),
            Text(
              t('insure.review.none'),
              style: TextStyle(
                color: c.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('insure.review.noneBody'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
            ),
            // An empty screen is a place to say what a useful review looks
            // like. "No reviews yet" teaches nothing and leaves the reader
            // with no idea why they would write one.
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('insure.review.helpsTitle').toUpperCase(),
                    style: TextStyle(
                      color: c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 8.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('insure.review.helpsBody'),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Average, stars, and the 5-to-1 distribution. Every visible rating counts
/// here, whether or not its words cleared moderation.
class _Histogram extends StatelessWidget {
  const _Histogram({required this.stats, this.reviews = const []});
  final ReviewStats stats;

  /// The loaded page of reviews, used only for the claims split.
  final List<InsurerReview> reviews;

  @override
  Widget build(BuildContext context) {
    // ── the claims split ────────────────────────────────────────────────
    //
    // NOT an average with a star row. In insurance there is one question, and
    // a rating from somebody who never claimed does not answer it.
    // `claims_holder` is already on every row, so splitting on it says
    // something no other Kenyan source will print.
    //
    // Shown only when the loaded page IS the whole set. `list` is capped at
    // twenty, so past that these would be the split of a sample presented as
    // the split of the market, which is the one thing this app does not do.
    final complete = reviews.isNotEmpty && reviews.length == stats.count;
    final claimed = reviews.where((r) => r.claimsHolder).toList();
    final untested = reviews.where((r) => !r.claimsHolder).toList();
    final showSplit =
        complete && claimed.isNotEmpty && untested.isNotEmpty;
    double mean(List<InsurerReview> l) =>
        l.fold<int>(0, (a, r) => a + r.rating) / l.length;

    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSplit) ...[
            _Split(
              claimedAvg: mean(claimed),
              claimedN: claimed.length,
              untestedAvg: mean(untested),
              untestedN: untested.length,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: c.line),
            ),
          ],
          Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stats.average.toStringAsFixed(1),
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                ),
              ),
              const SizedBox(height: 7),
              Stars(stats.average.round(), size: 12),
              const SizedBox(height: 6),
              Text(
                t('insure.review.count', {'n': '${stats.count}'}),
                style: TextStyle(color: c.faint, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: EdgeInsets.only(bottom: star == 1 ? 0 : 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 9,
                          child: Text(
                            '$star',
                            style: TextStyle(
                              color: c.faint,
                              fontFamily: fructaFonts.mono,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              height: 6,
                              color: c.s3,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(
                                    begin: 0,
                                    end: stats.fraction(star),
                                  ),
                                  duration: Duration(
                                    milliseconds: 700 + (5 - star) * 60,
                                  ),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, v, __) => FractionallySizedBox(
                                    widthFactor: v.clamp(0.0, 1.0),
                                    child: Container(color: c.accent),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${stats.buckets[star] ?? 0}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: c.faint,
                              fontFamily: fructaFonts.mono,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
        ],
      ),
    );
  }
}

/// Had a claim against never claimed.
///
/// The gap IS the finding, and it is the reason this section earns its place.
/// Somebody rating an insurer they have never tested is rating a price and how
/// fast the sticker arrived. Somebody who claimed is rating the only thing
/// insurance is actually for.
class _Split extends StatelessWidget {
  const _Split({
    required this.claimedAvg,
    required this.claimedN,
    required this.untestedAvg,
    required this.untestedN,
  });

  final double claimedAvg;
  final int claimedN;
  final double untestedAvg;
  final int untestedN;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final gap = untestedAvg - claimedAvg;
    // Under half a star the two groups are saying the same thing, and a
    // sentence announcing a gap of 0.2 would be reading noise as a signal.
    final material = gap.abs() >= 0.5;
    final worse = gap > 0;

    Widget half(String label, double avg, int n, Color tint) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: TextStyle(
                  color: tint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(child: Stars(avg.round(), size: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t('insure.review.people', {'n': '$n'}),
            style: TextStyle(color: c.faint, fontSize: 11),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            half(
              t('insure.review.hadClaim'),
              claimedAvg,
              claimedN,
              worse && material ? c.down : c.text,
            ),
            Container(
              width: 1,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: c.line,
            ),
            half(t('insure.review.noClaim'), untestedAvg, untestedN, c.text),
          ],
        ),
        if (material) ...[
          const SizedBox(height: 13),
          Text.rich(
            TextSpan(
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
              children: [
                TextSpan(text: t('insure.review.gapLead')),
                TextSpan(
                  text:
                      ' ${t('insure.review.gapStars', {'v': gap.abs().toStringAsFixed(1)})} ',
                  style: TextStyle(
                    color: worse ? c.down : c.up,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: worse
                      ? t('insure.review.gapWorse')
                      : t('insure.review.gapBetter'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The author's own status. Nobody should be left wondering whether the app
/// swallowed their review: their rating counted, their words are queued, and
/// this says so.
class _MyStatus extends StatelessWidget {
  const _MyStatus({required this.review, required this.insurer});
  final MyReview review;
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!review.pending && !review.rejected) return const SizedBox.shrink();

    final tint = review.rejected ? c.down : c.accent;
    final text = review.rejected
        ? t('insure.review.rejected', {'reason': review.rejectReason ?? ''})
        : t('insure.review.pending');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 11, 20, 0),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            review.rejected ? Icons.info_outline : Icons.hourglass_empty,
            size: 16,
            color: tint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({
    required this.review,
    required this.insurer,
    required this.index,
  });

  final InsurerReview review;
  final Insurer insurer;
  final int index;

  static String _ago(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days < 1) return t('insure.review.today');
    if (days < 7) return t('insure.review.daysAgo', {'n': '$days'});
    if (days < 60) {
      return t('insure.review.weeksAgo', {'n': '${(days / 7).round()}'});
    }
    return t('insure.review.monthsAgo', {'n': '${(days / 30).round()}'});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final r = review;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 340 + index.clamp(0, 6) * 45),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 9 * (1 - v)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stars(r.rating, size: 12),
                const SizedBox(width: 9),
                Text(
                  _ago(r.createdAt),
                  style: TextStyle(color: c.faint, fontSize: 10),
                ),
                if (r.claimsHolder) ...[
                  const SizedBox(width: 8),
                  // "Says they hold this", NOT "Verified holder". Holdings live
                  // on-device in Hive, so the server cannot confirm anyone
                  // actually holds a policy. A verified badge would be a promise
                  // the data cannot keep.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.s3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t('insure.review.claimsHolder'),
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (r.hasBody) ...[
              const SizedBox(height: 11),
              Text(
                r.body!,
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.65),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 11),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _report(context, ref),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_outlined, size: 13, color: c.faint),
                        const SizedBox(width: 5),
                        Text(
                          t('insure.review.report'),
                          style: TextStyle(color: c.faint, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      backgroundColor: c.s1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(
                t('insure.review.report'),
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final r in ReportReason.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t('insure.review.reason.${r.key}'),
                    style: TextStyle(color: c.muted, fontSize: 13.5),
                  ),
                  onTap: () => Navigator.of(sheet).pop(r),
                ),
            ],
          ),
        ),
      ),
    );
    if (reason == null) return;

    final ok = await ref.read(reviewsApiProvider).report(review.id, reason);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? t('insure.review.reported') : t('insure.review.reportedAlready'),
        ),
      ),
    );
  }
}

/// The write entry point. Reads "Write a review" or "Edit your review", and is
/// explicit that the rating publishes at once while the words are checked. That
/// is not fine print: it sets the expectation that prevents a support message.
class _WriteCta extends ConsumerWidget {
  const _WriteCta({required this.insurer, this.existing});
  final Insurer insurer;
  final MyReview? existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showReviewSheet(context, ref, insurer, existing),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line2, style: BorderStyle.solid),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.edit_outlined, size: 17, color: c.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? t('insure.review.write')
                          : t('insure.review.edit'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t('insure.review.writeSub'),
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── the write sheet ───────────────────────────────────────────────────────
Future<void> showReviewSheet(
  BuildContext context,
  WidgetRef ref,
  Insurer insurer,
  MyReview? existing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.c.s1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _ReviewSheet(insurer: insurer, existing: existing),
  );
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.insurer, this.existing});
  final Insurer insurer;
  final MyReview? existing;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late bool _holder = widget.existing?.claimsHolder ?? false;
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  String get _verdict => switch (_rating) {
    1 => t('insure.review.v1'),
    2 => t('insure.review.v2'),
    3 => t('insure.review.v3'),
    4 => t('insure.review.v4'),
    5 => t('insure.review.v5'),
    _ => t('insure.review.v0'),
  };

  Future<void> _submit() async {
    if (_rating == 0 || _busy) return;
    setState(() => _busy = true);

    final ok = await ref
        .read(reviewsApiProvider)
        .submit(
          insurerId: widget.insurer.id,
          rating: _rating,
          body: _body.text,
          claimsHolder: _holder,
        );

    if (!mounted) return;
    if (ok) invalidateReviews(ref, widget.insurer.id);
    setState(() => _busy = false);
    Navigator.of(context).pop();

    if (!context.mounted) return;
    final wrote = _body.text.trim().isNotEmpty;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? t('insure.review.failed')
              : wrote
              ? t('insure.review.submitted')
              : t('insure.review.submittedRating'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Text(
                  t('insure.review.rate', {
                    'name': shortInsurerName(widget.insurer.name),
                  }),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  t('insure.review.writeSub'),
                  style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.5),
                ),

                // stars
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var s = 1; s <= 5; s++)
                        GestureDetector(
                          onTap: () => setState(() => _rating = s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: AnimatedScale(
                              scale: _rating == s ? 1.16 : 1.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutBack,
                              child: Icon(
                                s <= _rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 36,
                                color: s <= _rating ? c.accent : c.line2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Center(
                  child: Text(
                    _verdict,
                    style: TextStyle(color: c.muted, fontSize: 11.5),
                  ),
                ),

                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: c.s2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _body,
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 1200,
                    cursorColor: c.accent,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterStyle: TextStyle(color: c.faint, fontSize: 9),
                      hintText: t('insure.review.placeholder'),
                      hintStyle: TextStyle(
                        color: c.faint,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),

                // Their claim, not our verification. The label everywhere else
                // says "Says they hold this" for exactly this reason.
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: c.accent,
                    checkColor: c.inkOn(c.accent),
                    value: _holder,
                    onChanged: (v) => setState(() => _holder = v ?? false),
                    title: Text(
                      t('insure.review.iHold'),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                ),

                // The rules. Not decoration: this is what keeps a defamatory
                // claim about a named Kenyan insurer off the app, and Kenya has
                // no Section 230 to fall back on.
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.s2,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 15, color: c.faint),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          t('insure.review.rules'),
                          style: TextStyle(
                            color: c.faint,
                            fontSize: 10.5,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _rating == 0 || _busy ? null : _submit,
                    style: TextButton.styleFrom(
                      backgroundColor: _rating == 0 ? c.s3 : c.accent,
                      foregroundColor: _rating == 0
                          ? c.faint
                          : c.inkOn(c.accent),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      _busy
                          ? t('insure.review.sending')
                          : t('insure.review.submit'),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Center(
                  child: Text(
                    t('insure.review.consent'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.faint,
                      fontSize: 9.5,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../pro/pro_widgets.dart';
import '../pro/switch_page.dart';
import 'wrap_engine.dart';

/// What a market story means for this user's money, worked out on the phone
/// from their holdings. Nothing here leaves the device.
class ForYou {
  const ForYou({
    required this.figure,
    required this.detail,
    this.tone = WrapTone.up,
    this.switchFrom,
    this.switchTo,
    this.followId,
  });

  /// The headline figure, e.g. "+KES 1,840 a year".
  final String figure;
  final String detail;
  final WrapTone tone;

  /// When set, "Should I switch?" opens the switch page for this pair.
  final String? switchFrom;
  final String? switchTo;

  /// When set, a Follow button for the story's fund.
  final String? followId;
}

String _kes(double v) {
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) {
      b.write(',');
    }
    b.write(s[i]);
  }
  return 'KES $b';
}

bool _kesMmf(Fund f) =>
    f.retail &&
    f.showsYield &&
    f.fundType == 'mmf' &&
    f.currency == 'KES' &&
    f.currentRate != null;

/// The "for you" reading of [s], or null when the user's holdings say
/// nothing about it (no KES money market holding, a personal story).
ForYou? forYouFor(WidgetRef ref, WrapSlide s) {
  if (s.personal) return null;
  final byId = ref.watch(fundsByIdProvider);
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final follows = ref.watch(subscriptionsProvider);
  final held = [
    for (final h in ref.watch(holdingsProvider))
      if (!h.isSacco && h.currency == 'KES' && h.balance > 0)
        if (byId[h.fundId] case final f? when _kesMmf(f)) (h: h, f: f),
  ]..sort((a, b) => b.h.balance.compareTo(a.h.balance));
  if (held.isEmpty) return null;

  final story = s.fundId == null ? null : byId[s.fundId];

  // A story about a fund the user holds: what the move does to their money.
  if (story != null) {
    for (final x in held) {
      if (x.f.id != story.id) continue;
      final move = s.value;
      final rate = story.netRate(wht) ?? story.currentRate!;
      if (move != null && move.abs() >= 0.01 && s.type != 'stable') {
        final yearly =
            x.h.balance * move / 100 * (story.whtStillDue ? 1 - wht / 100 : 1);
        return ForYou(
          figure: '${yearly >= 0 ? '+' : '-'}${_kes(yearly)}',
          detail: t('wrap.you.heldMove'),
          tone: yearly >= 0 ? WrapTone.up : WrapTone.down,
        );
      }
      return ForYou(
        figure: _kes(x.h.balance * rate / 100),
        detail: t('wrap.you.heldYear', {'rate': rate.toStringAsFixed(2)}),
        tone: WrapTone.up,
      );
    }

    // A fund the user does not hold: against their largest KES holding.
    if (_kesMmf(story)) {
      final mine = held.first;
      final gap = (story.netRate(wht) ?? 0) - (mine.f.netRate(wht) ?? 0);
      if (gap > 0.01) {
        return ForYou(
          figure: '+${_kes(mine.h.balance * gap / 100)}',
          detail: t('wrap.you.moreThan', {'fund': mine.f.name}),
          switchFrom: mine.f.id,
          switchTo: story.id,
          followId: follows.contains(story.id) ? null : story.id,
        );
      }
      return ForYou(
        figure: t('wrap.you.yoursPays', {'fund': mine.f.name}),
        detail: t('wrap.you.yoursMore', {'gap': (-gap).toStringAsFixed(2)}),
        tone: WrapTone.info,
      );
    }
    return null;
  }

  // Market-wide stories: the user's book against the bill.
  if (s.type == 'tbill' && s.refRate != null) {
    final total = held.fold(0.0, (n, x) => n + x.h.balance);
    final avg =
        held.fold(0.0, (n, x) => n + x.h.balance * x.f.currentRate!) / total;
    final gap = avg - s.refRate!;
    return ForYou(
      figure: '${avg.toStringAsFixed(2)}%',
      detail: t(gap >= 0 ? 'wrap.you.bookAbove' : 'wrap.you.bookBelow', {
        'gap': gap.abs().toStringAsFixed(2),
      }),
      tone: gap >= 0 ? WrapTone.up : WrapTone.down,
    );
  }
  return null;
}

/// The "for you" panel under a market story. Pro sees the figure and the next
/// step; a free user sees it blurred with the way in. Hidden while the story
/// is captured for sharing, so a shared image never carries anyone's money.
class ForYouPanel extends ConsumerWidget {
  const ForYouPanel({super.key, required this.slide, required this.palette});

  final WrapSlide slide;

  /// The story palette (always dark), from the viewer.
  final fructaColors palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final you = forYouFor(ref, slide);
    if (you == null) return const SizedBox.shrink();
    final d = palette;
    final unlocked = ref.watch(wrapPersonalUnlockedProvider);
    final hide = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );
    final tone = switch (you.tone) {
      WrapTone.up => d.up,
      WrapTone.down => d.down,
      _ => d.text,
    };
    final figure = hide && you.figure.contains('KES')
        ? 'KES \u2022\u2022\u2022\u2022'
        : you.figure;

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          figure,
          style: fructaFonts.numeric(
            color: tone,
            size: 20,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          you.detail,
          style: TextStyle(color: d.muted, fontSize: 13, height: 1.35),
        ),
      ],
    );
    if (!unlocked) {
      body = ExcludeSemantics(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: body,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked
            ? d.text.withValues(alpha: 0.06)
            : d.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? d.text.withValues(alpha: 0.10)
              : d.accent.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t('wrap.you.title'),
                style: TextStyle(
                  color: d.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (!unlocked) const ProBadge(),
            ],
          ),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 10),
          if (!unlocked)
            _Action(
              label: t('wrap.you.unlock'),
              filled: true,
              palette: d,
              onTap: () => ensurePro(context, ref, source: 'wrap_for_you'),
            )
          else if (you.switchFrom != null || you.followId != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (you.switchFrom != null)
                  _Action(
                    label: t('wrap.you.switch'),
                    filled: true,
                    palette: d,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SwitchPage(
                          fromFundId: you.switchFrom,
                          toFundId: you.switchTo,
                        ),
                      ),
                    ),
                  ),
                if (you.followId != null)
                  _Action(
                    label: t('wrap.you.follow'),
                    filled: false,
                    palette: d,
                    onTap: () => ref
                        .read(subscriptionsProvider.notifier)
                        .toggle(you.followId!),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.filled,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final fructaColors palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = palette;
    return Material(
      color: filled ? d.text : d.bg.withValues(alpha: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: filled
            ? BorderSide.none
            : BorderSide(color: d.text.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: filled ? d.bg : d.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// How unusual the move is and its run of weeks, under a server story's chart.
class TrendStrip extends StatelessWidget {
  const TrendStrip({super.key, required this.slide, required this.palette});

  final WrapSlide slide;
  final fructaColors palette;

  @override
  Widget build(BuildContext context) {
    final r = slide.ratio;
    final w = slide.trendWeeks;
    if ((r == null || r < 1.5) && (w == null || w < 2)) {
      return const SizedBox.shrink();
    }
    final d = palette;
    final up = slide.tone == WrapTone.up;
    Widget cell(String k, String v, Color c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(color: d.muted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            v,
            style: TextStyle(
              color: c,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: d.text.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (r != null && r >= 1.5)
            cell(
              t('wrap.trend.unusual'),
              t('wrap.trend.times', {'n': r.toStringAsFixed(1)}),
              d.text,
            ),
          if (w != null && w >= 2)
            cell(
              t('wrap.trend.title'),
              t(up ? 'wrap.trend.rising' : 'wrap.trend.falling', {'n': '$w'}),
              up ? d.up : d.down,
            ),
        ],
      ),
    );
  }
}

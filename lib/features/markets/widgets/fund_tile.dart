import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/categories.dart';
import '../../../core/i18n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/rate_basis.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/fund.dart';
import '../../../data/providers.dart';
import '../../../data/snapshot_providers.dart';

/// Id of the fund row currently opened in the Markets list. One at a time, so
/// opening a row closes the last one and the list never turns into a wall.
final openFundRowProvider = StateProvider<String?>((_) => null);

/// One fund in the Markets list.
///
/// Closed, the row carries only rank, logo, name, one rate and its 7-day move:
/// the rate is gross or net per the app-wide [showNetProvider]. Tapping opens
/// the row in place to show gross, net, after inflation and the 7-day move,
/// with the manager and minimum, and buttons to open or follow the fund. The
/// fund page stays one tap further. In compare mode a tap selects instead.
///
/// The 7-day move comes from one source (the fund's rate event) and is shown
/// on the same basis as the rate above it. No sparkline is drawn beside it,
/// because the sparkline series and the event could disagree.
class FundTile extends ConsumerWidget {
  const FundTile(
    this.fund, {
    super.key,
    required this.onTap,
    this.rank,
    this.selectable = false,
    this.selected = false,
    this.onToggleSelect,
    this.brandColor,
    this.delta,
  });

  final Fund fund;

  /// Opens the fund page.
  final VoidCallback onTap;
  final int? rank;
  final bool selectable;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final Color? brandColor;

  /// Seven-day move in GROSS points, from the fund's rate event.
  final double? delta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = fund;
    final cfg = ref.watch(remoteConfigProvider);
    final wht = cfg.whtPct;
    final showNet = ref.watch(showNetProvider);
    final open = !selectable && ref.watch(openFundRowProvider) == f.id;

    final rate = f.currentRate;
    final hasRate = f.showsYield && rate != null;
    // Net only exists where a deduction is still to come.
    final net = hasRate && f.whtStillDue && !f.taxFree ? f.netRate(wht) : null;
    final useNet = showNet && net != null;

    final headline = f.headlineWith(
      ref.watch(latestPeriodReturnProvider(f.id)),
    );
    final big = switch (headline) {
      YieldHeadline(:final gross) =>
        '${(useNet ? net : gross).toStringAsFixed(2)}%',
      ReturnHeadline(:final pct) =>
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
      NoHeadline() => t('common.dash'),
    };
    final bigColor = switch (headline) {
      ReturnHeadline(:final pct) => c.delta(pct),
      YieldHeadline() => c.text,
      NoHeadline() => c.faint,
    };

    final raw = delta;
    final d = raw == null ? null : (useNet ? raw * (1 - wht / 100) : raw);
    String signed(double v, {int places = 2}) =>
        '${v > 0 ? '+' : ''}${v.toStringAsFixed(places)}';

    void tapRow() {
      if (selectable) {
        onToggleSelect?.call();
        return;
      }
      ref.read(openFundRowProvider.notifier).state = open ? null : f.id;
    }

    return Material(
      color: selected
          ? c.accentSoft
          : open
          ? c.s1
          : c.bg.withValues(alpha: 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: tapRow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
                child: Row(
                  children: [
                    if (rank != null)
                      SizedBox(
                        width: 22,
                        child: Text(
                          '$rank',
                          style: fructaFonts.numeric(
                            color: rank! <= 3 ? c.accentInk : c.faint,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _Logo(
                      fund: f,
                      brandColor: brandColor,
                      checked: selectable && selected,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.name,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StretchSwap(
                          value: useNet,
                          alignment: Alignment.centerRight,
                          child: Glitch(
                            trigger: rate,
                            a: c.accent,
                            b: c.down,
                            child: Text(
                              big,
                              style: fructaFonts.numeric(
                                color: bigColor,
                                size: 18,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (headline case ReturnHeadline(:final label))
                          Text(
                            label,
                            style: TextStyle(color: c.faint, fontSize: 10.5),
                          )
                        else if (headline case NoHeadline(:final reason))
                          Text(
                            reason,
                            style: TextStyle(color: c.faint, fontSize: 9.5),
                          )
                        else if (d != null && d != 0)
                          Text(
                            signed(d),
                            style: fructaFonts.numeric(
                              color: c.delta(d),
                              size: 11.5,
                              weight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (!selectable) ...[
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: c.faint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open
                  ? _Details(
                      fund: f,
                      hasRate: hasRate,
                      gross: rate,
                      net: net,
                      delta: d,
                      deltaText: d == null || d == 0
                          ? t('markets.row.noMove')
                          : t('today.pts', {'v': signed(d)}),
                      onOpen: onTap,
                      inset: rank != null ? 22 : 0,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo with the compare check badge.
class _Logo extends ConsumerWidget {
  const _Logo({
    required this.fund,
    required this.brandColor,
    required this.checked,
  });

  final Fund fund;
  final Color? brandColor;
  final bool checked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FundLogo(
            domain: fund.logoDomain,
            logoUrl: ref.watch(logoUrlProvider(fund.id)),
            seed: fund.manager,
            size: 36,
            brandColor: brandColor,
          ),
          if (checked)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
                child: Icon(Icons.check, size: 10, color: c.onAccent),
              ),
            ),
        ],
      ),
    );
  }
}

/// What a row reveals when opened.
class _Details extends ConsumerWidget {
  const _Details({
    required this.fund,
    required this.hasRate,
    required this.gross,
    required this.net,
    required this.delta,
    required this.deltaText,
    required this.onOpen,
    required this.inset,
  });

  final Fund fund;
  final bool hasRate;
  final double? gross;
  final double? net;
  final double? delta;
  final String deltaText;
  final VoidCallback onOpen;
  final double inset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = fund;
    final cfg = ref.watch(remoteConfigProvider);
    final inflation = cfg.inflationFor(f.currency);
    final real = hasRate && inflation != null
        ? f.realRate(inflation, whtPct: cfg.whtPct)
        : null;
    final following = ref.watch(subscriptionsProvider).contains(f.id);

    final type = categoryLabel(f.category);
    final typeLine = [
      if (f.fundType != null) _typeNames[f.fundType] ?? type else type,
      f.currency,
      f.manager,
      if (f.minInvest != null)
        t('markets.row.min', {
          'amount': '${f.currency} ${_commas(f.minInvest!)}',
        }),
    ].where((s) => s.isNotEmpty).join(' \u00b7 ');

    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 10.5)),
          const SizedBox(height: 3),
          Text(
            value,
            style: fructaFonts.numeric(
              color: color,
              size: 13.5,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20 + inset + 48, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRate)
            Row(
              children: [
                cell(t('basis.gross'), '${gross!.toStringAsFixed(2)}%', c.text),
                cell(
                  f.taxFree ? t('markets.row.taxFreeShort') : t('basis.net'),
                  '${(net ?? gross!).toStringAsFixed(2)}%',
                  c.text,
                ),
                cell(
                  t('today.afterInflation'),
                  real == null
                      ? t('common.dash')
                      : '${real >= 0 ? '+' : ''}${real.toStringAsFixed(2)}%',
                  real == null ? c.muted : c.delta(real),
                ),
                cell(
                  t('markets.row.week'),
                  deltaText,
                  delta == null || delta == 0 ? c.muted : c.delta(delta!),
                ),
              ],
            ),
          if (hasRate) const SizedBox(height: 10),
          Text(
            typeLine,
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onOpen,
                  child: Text(
                    t('markets.row.open'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.text,
                    minimumSize: const Size.fromHeight(40),
                    side: BorderSide(color: c.line2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () =>
                      ref.read(subscriptionsProvider.notifier).toggle(f.id),
                  child: Text(
                    t(following ? 'today.following' : 'today.follow'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _typeNames = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

String _commas(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

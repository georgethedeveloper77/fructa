import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/series_colors.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/fx_engine.dart';

/// "Run your own numbers": the page behind the currency card on Markets.
///
/// The card answers one question at one horizon for one stance. This answers
/// the same question for the stance the reader is actually in, over the horizon
/// they actually have, on an amount they actually hold, and then shows what
/// that bet would have done every time it could have been placed in the history
/// we hold.
///
/// It prices a bet. It never recommends one, and there is no version of this
/// page that says which currency to be in, because nobody knows.
class CurrencyComparePage extends ConsumerStatefulWidget {
  const CurrencyComparePage({super.key});

  @override
  ConsumerState<CurrencyComparePage> createState() =>
      _CurrencyComparePageState();
}

class _CurrencyComparePageState extends ConsumerState<CurrencyComparePage> {
  FxStance _stance = FxStance.holding;
  int _years = 1;
  int _amountIndex = 1;

  /// KES for a buyer, USD for everyone else, matching what [FxCase.projectFlat]
  /// expects and, more to the point, what the reader is holding when they open
  /// this page.
  static const _kesAmounts = <double>[100000, 500000, 1000000];
  static const _usdAmounts = <double>[1000, 5000, 10000];

  List<double> get _amounts =>
      _stance == FxStance.buying ? _kesAmounts : _usdAmounts;

  double get _amount => _amounts[_amountIndex];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = ref.watch(fxHoldingCaseProvider);
    final series = ref.watch(fxSeriesProvider);
    final pair = ref.watch(fxFundPairProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          t('markets.fx.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: base == null || series == null
          ? _empty(c)
          : _body(c, base.copyWith(stance: _stance, years: _years.toDouble()),
              series.mean, pair),
    );
  }

  Widget _empty(fructaColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
    child: Text(
      t('markets.fx.cmp.unavailable'),
      textAlign: TextAlign.center,
      style: TextStyle(color: c.muted, height: 1.6),
    ),
  );

  Widget _body(
    fructaColors c,
    FxCase fxCase,
    List<double> means,
    ({Fund kes, Fund usd})? pair,
  ) {
    final months = _years * 12;
    // The race needs a start point far enough back to run the whole horizon,
    // and the record needs at least one complete window. Both simply do not
    // render when the history is short, rather than running on a truncated
    // window and presenting it as a full one.
    final canRace = means.length > months;
    final canRecord = means.length > months + 1;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        _Quote(quote: fxCase.quote),
        _Section(t('markets.fx.cmp.stance')),
        _Segments<FxStance>(
          values: FxStance.values,
          selected: _stance,
          labelOf: _stanceLabel,
          onTap: (s) => setState(() => _stance = s),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            _stanceNote(),
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
          ),
        ),

        // Hedged takes no currency position, so there is no hurdle, no race and
        // no record. Saying that plainly is the answer; inventing a comparison
        // for someone who has nothing riding on the pair would not be.
        if (_stance == FxStance.hedged) ...[
          _Section(t('markets.fx.cmp.noBet')),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              t('markets.fx.cmp.hedgedBody'),
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.6),
            ),
          ),
        ] else ...[
          _Section(t('markets.fx.cmp.horizon')),
          _Segments<int>(
            values: const [1, 3, 5],
            selected: _years,
            labelOf: (y) => t('markets.fx.cmp.yearsN', {'n': '$y'}),
            onTap: (y) => setState(() => _years = y),
          ),
          _Hurdle(fxCase: fxCase),

          if (canRace) ...[
            _Section(
              t('markets.fx.cmp.race'),
              small: t('markets.fx.cmp.raceSub', {'n': '$_years'}),
            ),
            _AmountChips(
              amounts: _amounts,
              index: _amountIndex,
              usd: _stance != FxStance.buying,
              onTap: (k) => setState(() => _amountIndex = k),
            ),
            _Race(
              points: FxEngine.race(
                fxCase: fxCase,
                means: means,
                start: means.length - 1 - months,
                months: months,
                amount: _amount,
              ),
              usdLabel: t('markets.fx.cmp.legendUsd'),
              kesLabel: t('markets.fx.cmp.legendKes'),
            ),
          ],

          if (canRecord)
            _Record(
              record: FxEngine.rollingRecord(
                fxCase: fxCase,
                means: means,
                windowMonths: months,
              ),
              years: _years,
            ),
        ],

        _Assumptions(fxCase: fxCase, pair: pair),
        NoteCard(
          t('markets.fx.cmp.disclaimer'),
          title: t('common.goodToKnow'),
        ),
      ],
    );
  }

  String _stanceLabel(FxStance s) => switch (s) {
    FxStance.buying => t('markets.fx.cmp.stanceBuying'),
    FxStance.holding => t('markets.fx.cmp.stanceHolding'),
    FxStance.hedged => t('markets.fx.cmp.stanceHedged'),
  };

  String _stanceNote() => switch (_stance) {
    FxStance.buying => t('markets.fx.cmp.noteBuying'),
    FxStance.holding => t('markets.fx.cmp.noteHolding'),
    FxStance.hedged => t('markets.fx.cmp.noteHedged'),
  };
}

// ── pieces ────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(this.title, {this.small});
  final String title;
  final String? small;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (small != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                small!,
                textAlign: TextAlign.end,
                style: TextStyle(color: c.faint, fontSize: 9.5, height: 1.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onTap,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            for (final v in values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == selected ? c.s3 : null,
                      borderRadius: BorderRadius.circular(10),
                      // Drawn at zero alpha rather than dropped, so the pill
                      // never changes size as the selection moves across it.
                      border: Border.all(
                        color: v == selected
                            ? c.line2
                            : c.line.withValues(alpha: 0),
                      ),
                    ),
                    child: Text(
                      labelOf(v),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: v == selected ? c.text : c.muted,
                        fontSize: 12.5,
                        fontWeight: v == selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.quote});
  final FxQuote quote;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = seriesColor(2);

    Widget leg(String label, double v, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            v.toStringAsFixed(2),
            style: TextStyle(
              color: color,
              fontFamily: fructaFonts.mono,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                leg(t('markets.fx.cmp.legBuy'), quote.askRate, c.text),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: c.line,
                ),
                leg(t('markets.fx.cmp.legMean'), quote.mean, tint),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: c.line,
                ),
                leg(t('markets.fx.cmp.legSell'), quote.bidRate, c.text),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t('markets.fx.cmp.roundTrip', {
                'p': (quote.roundTrip * 100).toStringAsFixed(1),
              }),
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

/// The number the whole feature exists to print: how far the shilling has to
/// fall before the dollar side draws level.
class _Hurdle extends StatelessWidget {
  const _Hurdle({required this.fxCase});
  final FxCase fxCase;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = seriesColor(2);

    final be = fxCase.breakeven;
    final dep = fxCase.impliedDepreciation;
    final ann = fxCase.annualisedHurdle;
    final band = fxCase.hurdleBand;
    if (be == null || dep == null || ann == null) {
      return const SizedBox.shrink();
    }

    final bandLabel = switch (band) {
      FxHurdleBand.low => t('markets.fx.cmp.bandLow'),
      FxHurdleBand.moderate => t('markets.fx.cmp.bandMod'),
      FxHurdleBand.high => t('markets.fx.cmp.bandHigh'),
      null => '',
    };
    final bandColor = switch (band) {
      FxHurdleBand.low => c.up,
      FxHurdleBand.moderate => c.accent,
      FxHurdleBand.high => c.down,
      null => c.faint,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t('markets.fx.cmp.hurdle'),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (bandLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: bandColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      bandLabel,
                      style: TextStyle(
                        color: bandColor,
                        fontSize: 9.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  be.toStringAsFixed(2),
                  style: TextStyle(
                    color: tint,
                    fontFamily: fructaFonts.mono,
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t('markets.fx.cmp.perDollar'),
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t('markets.fx.cmp.hurdleBody', {
                'dep': (dep * 100).toStringAsFixed(1),
                'ann': (ann * 100).toStringAsFixed(1),
              }),
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountChips extends StatelessWidget {
  const _AmountChips({
    required this.amounts,
    required this.index,
    required this.usd,
    required this.onTap,
  });

  final List<double> amounts;
  final int index;
  final bool usd;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          for (var k = 0; k < amounts.length; k++) ...[
            if (k > 0) const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onTap(k),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: k == index ? c.text : c.s1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: k == index ? c.text : c.line),
                ),
                child: Text(
                  '${usd ? 'USD' : 'KES'} ${withCommas(amounts[k].round())}',
                  style: TextStyle(
                    color: k == index ? c.bg : c.muted,
                    fontFamily: fructaFonts.mono,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Both paths in shillings, month by month, over the horizon that has just
/// ended. Not a projection: this is what the two choices actually did to
/// somebody who made them, on the history in the snapshot.
class _Race extends StatelessWidget {
  const _Race({
    required this.points,
    required this.kesLabel,
    required this.usdLabel,
  });

  final List<FxRacePoint> points;
  final String kesLabel;
  final String usdLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kesColor = seriesColor(0);
    final usdColor = seriesColor(2);
    if (points.length < 2) return const SizedBox.shrink();

    final last = points.last;

    Widget key(Color color, String label, double value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: c.faint, fontSize: 11)),
        const SizedBox(width: 6),
        Text(
          withCommas(value.round()),
          style: TextStyle(
            color: c.text,
            fontFamily: fructaFonts.mono,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 130,
              child: CustomPaint(
                size: Size.infinite,
                painter: _RacePainter(
                  points: points,
                  kesColor: kesColor,
                  usdColor: usdColor,
                  grid: c.line,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                key(kesColor, kesLabel, last.kesPath),
                key(usdColor, usdLabel, last.usdPath),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t(
                last.usdAhead
                    ? 'markets.fx.cmp.raceUsd'
                    : 'markets.fx.cmp.raceKes',
                {
                  'amt': withCommas((last.kesPath - last.usdPath).abs().round()),
                },
              ),
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _RacePainter extends CustomPainter {
  _RacePainter({
    required this.points,
    required this.kesColor,
    required this.usdColor,
    required this.grid,
  });

  final List<FxRacePoint> points;
  final Color kesColor;
  final Color usdColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in points) {
      lo = math.min(lo, math.min(p.kesPath, p.usdPath));
      hi = math.max(hi, math.max(p.kesPath, p.usdPath));
    }
    if (!lo.isFinite || !hi.isFinite) return;
    final pad = (hi - lo) == 0 ? math.max(hi.abs() * 0.05, 1.0) : (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);

    double xOf(int i) => i / (points.length - 1) * size.width;
    double yOf(double v) => size.height - ((v - lo) / span) * size.height;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    Path pathOf(double Function(FxRacePoint) pick) {
      final p = Path()..moveTo(xOf(0), yOf(pick(points[0])));
      for (var i = 1; i < points.length; i++) {
        p.lineTo(xOf(i), yOf(pick(points[i])));
      }
      return p;
    }

    void stroke(Path p, Color color) => canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    stroke(pathOf((p) => p.kesPath), kesColor);
    stroke(pathOf((p) => p.usdPath), usdColor);

    final endKes = Offset(xOf(points.length - 1), yOf(points.last.kesPath));
    final endUsd = Offset(xOf(points.length - 1), yOf(points.last.usdPath));
    canvas.drawCircle(endKes, 3, Paint()..color = kesColor);
    canvas.drawCircle(endUsd, 3, Paint()..color = usdColor);
  }

  @override
  bool shouldRepaint(_RacePainter old) =>
      old.points != points ||
      old.kesColor != kesColor ||
      old.usdColor != usdColor;
}

/// How often the dollar side actually cleared this bar, every time the bet
/// could have been placed in the history we hold.
///
/// This is the honest counterweight to the hurdle. A hurdle on its own reads as
/// either impossible or trivial depending on the reader's priors; a record says
/// what happened.
class _Record extends StatelessWidget {
  const _Record({required this.record, required this.years});

  final FxRecord record;
  final int years;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (record.total == 0) return const SizedBox.shrink();

    final pct = (record.winRate * 100).round();
    final usdColor = seriesColor(2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('markets.fx.cmp.record'),
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            // One tick per window, in order. Sixty of them read as a texture
            // rather than a chart, which is the right weight for a fact that
            // supports the headline without competing with it.
            LayoutBuilder(
              builder: (context, cons) {
                final n = record.windows.length;
                final gap = n > 40 ? 1.0 : 2.0;
                final w = math.max((cons.maxWidth - gap * (n - 1)) / n, 1.0);
                return Row(
                  children: [
                    for (var k = 0; k < n; k++) ...[
                      if (k > 0) SizedBox(width: gap),
                      Container(
                        width: w,
                        height: 26,
                        decoration: BoxDecoration(
                          color: record.windows[k].usdWon ? usdColor : c.s3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              t('markets.fx.cmp.recordBody', {
                'wins': '${record.wins}',
                'total': '${record.total}',
                'pct': '$pct',
                'years': '$years',
              }),
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every number this page ran on, in one list.
///
/// The spread is the one to read twice. It is an assumption, not a quote, and
/// the page says so here rather than in a footnote nobody opens.
class _Assumptions extends ConsumerWidget {
  const _Assumptions({required this.fxCase, required this.pair});

  final FxCase fxCase;
  final ({Fund kes, Fund usd})? pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final spread = ref.watch(remoteConfigProvider).fxSpreadPct;

    // The two funds are named, not just their yields quoted. The first thing
    // anyone does with a figure like this is try to check it against the list
    // they just scrolled past, and a yield with no fund attached cannot be
    // checked at all.
    final rows = <({String label, String value, bool mono})>[
      (
        label: t('markets.fx.cmp.aMean'),
        value: fxCase.quote.mean.toStringAsFixed(2),
        mono: true,
      ),
      (
        label: t('markets.fx.cmp.aSpread'),
        value: '${spread.toStringAsFixed(2)}%',
        mono: true,
      ),
      if (pair != null)
        (
          label: t('markets.fx.cmp.aKesFund'),
          value: pair!.kes.name,
          mono: false,
        ),
      (
        label: t('markets.fx.cmp.aKes'),
        value: '${(fxCase.kesNet * 100).toStringAsFixed(2)}%',
        mono: true,
      ),
      if (pair != null)
        (
          label: t('markets.fx.cmp.aUsdFund'),
          value: pair!.usd.name,
          mono: false,
        ),
      (
        label: t('markets.fx.cmp.aUsd'),
        value: '${(fxCase.usdNet * 100).toStringAsFixed(2)}%',
        mono: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(t('markets.fx.cmp.assumptions')),
        for (var k = 0; k < rows.length; k++)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
            decoration: BoxDecoration(
              border: k == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows[k].label,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    rows[k].value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: c.text,
                      fontFamily: rows[k].mono ? fructaFonts.mono : null,
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      fontFeatures: rows[k].mono
                          ? const [FontFeature.tabularFigures()]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // The spread is the one assumption on this page that is not a
        // published number, so it gets the card rather than a grey line under
        // a table where it reads as a caption.
        NoteCard(
          t('markets.fx.cmp.aNote'),
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        ),
      ],
    );
  }
}

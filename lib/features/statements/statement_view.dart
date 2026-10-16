import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/reveal_note.dart';
import '../../core/widgets/reveal_text.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_analysis.dart';
import '../pro/pro_widgets.dart';
import 'statement_controller.dart';
import 'statement_match_sheet.dart';

/// The result of a statement check: headline gap, checks, charts, totals.
///
/// Free users see the headline and the tax check, then one card that explains
/// what Pro adds. Everything else is Pro (see [statementFullAccessProvider]).
class StatementFindingsView extends ConsumerWidget {
  const StatementFindingsView({super.key, required this.saved});

  final SavedStatement saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final async = ref.watch(statementAnalysisProvider(saved.id));
    final full = ref.watch(statementFullAccessProvider);
    final d = saved.data;

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('$e', style: TextStyle(color: c.down)),
      ),
      data: (r) {
        final a = r.analysis;
        final checks = a.findings.where((f) => !_isHeadline(f)).toList();
        final freeChecks = checks
            .where((f) => f.key.startsWith('statement.find.tax'))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(saved: saved),
            _Headline(result: r),
            if (full) ...[
              _Kpis(saved: saved, analysis: a),
              if (a.fullPeriods.length >= 2)
                _Card(
                  title: t('statement.chart.yield'),
                  trailing: t('statement.chart.yieldUnit'),
                  child: _YieldBars(analysis: a),
                ),
              _Checks(findings: checks),
              if (a.periods.isNotEmpty)
                _Card(
                  title: t('statement.chart.interest'),
                  trailing: d.currency,
                  child: _InterestBars(analysis: a),
                ),
              _Totals(saved: saved),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => showStatementMatchSheet(
                    context,
                    saved: saved,
                    suggested: r.fund,
                  ),
                  child: Text(
                    t('statement.match.cta'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  t('statement.match.note'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.faint, fontSize: 12),
                ),
              ),
            ] else ...[
              _Checks(findings: freeChecks),
              const _ProCard(),
            ],
          ],
        );
      },
    );
  }

  static bool _isHeadline(StatementFinding f) =>
      f.key == 'statement.find.underpaid' ||
      f.key == 'statement.find.overpaid' ||
      f.key == 'statement.find.matches';
}

class _Header extends StatelessWidget {
  const _Header({required this.saved});

  final SavedStatement saved;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = saved.data;
    final name = d.managerName.isEmpty
        ? t('statement.unknownManager')
        : d.managerName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name \u00b7 ${d.currency}',
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            t('statement.period', {
              'tail': d.accountTail,
              'from': dayLabel(d.from),
              'to': dayLabel(d.to),
            }),
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The one number: credited against published.
class _Headline extends StatelessWidget {
  const _Headline({required this.result});

  final StatementResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = result.analysis;
    final gap = a.gapPts;
    if (gap == null || a.recentCreditedPct == null) {
      return _Card(
        child: RevealText(
          t('statement.noPublished'),
          style: TextStyle(color: c.muted, fontSize: 14, height: 1.45),
        ),
      );
    }
    final under = gap <= -0.25;
    final color = under ? c.down : c.up;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: under ? c.downSoft : c.upSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('statement.finding'),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          StretchSwap(
            value: gap,
            playOnMount: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
                    style: fructaFonts.numeric(
                      color: color,
                      size: 44,
                      weight: FontWeight.w600,
                      letterSpacing: -1.2,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text:
                        '  ${t(gap < 0
                            ? 'statement.gapBelow'
                            : gap > 0
                            ? 'statement.gapAbove'
                            : 'statement.ptsYear')}',
                    style: TextStyle(color: c.muted, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t('statement.headShort', {
              'credited': a.recentCreditedPct!.toStringAsFixed(2),
              'published': a.recentPublishedPct!.toStringAsFixed(2),
            }),
            style: TextStyle(color: c.text, fontSize: 14.5, height: 1.45),
          ),
          RevealNote(
            label: t(
              result.publishedIsToday
                  ? 'statement.whyToday'
                  : 'statement.whyNotFees',
            ),
            body: t(
              result.publishedIsToday
                  ? 'statement.headlineToday'
                  : 'statement.headline',
              {
                'credited': a.recentCreditedPct!.toStringAsFixed(2),
                'published': a.recentPublishedPct!.toStringAsFixed(2),
              },
            ),
            padding: const EdgeInsets.only(top: 4),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, this.trailing});

  final Widget child;
  final String? title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// Each finding as a row: a mark, then the sentence, long ones tap-to-reveal.
/// Each check as a short title and its value, worst first. The full sentence
/// opens on tap.
class _Checks extends StatefulWidget {
  const _Checks({required this.findings});

  final List<StatementFinding> findings;

  @override
  State<_Checks> createState() => _ChecksState();
}

class _ChecksState extends State<_Checks> {
  final _open = <int>{};

  static int _rank(FindingSeverity s) => switch (s) {
    FindingSeverity.bad => 0,
    FindingSeverity.warn => 1,
    FindingSeverity.info => 2,
    FindingSeverity.ok => 3,
  };

  /// A few words and a figure for a finding; the full sentence stays its
  /// detail. A finding without a short form shows its sentence as the title.
  static (String, String)? _short(StatementFinding f) {
    final v = f.vars;
    String months() {
      final list = (v['months'] ?? '').split(', ').where((m) => m.isNotEmpty);
      return list.length == 1
          ? list.first
          : t('statement.short.monthsN', {'n': '${list.length}'});
    }

    return switch (f.key) {
      'statement.find.taxOk' => (
        t('statement.short.taxOk'),
        '${v['pct'] ?? ''}%',
      ),
      'statement.find.taxOff' => (t('statement.short.taxOff'), v['n'] ?? '!'),
      'statement.find.taxOnTaxFree' => (t('statement.short.taxOnTaxFree'), '!'),
      'statement.find.everyMonth' => (
        t('statement.short.everyMonth'),
        '${v['n']}/${v['n']}',
      ),
      'statement.find.missingMonths' => (
        t('statement.short.missing'),
        months(),
      ),
      'statement.find.withdrawalPaid' => (
        t('statement.short.withdrawal'),
        v['amount'] ?? '',
      ),
      'statement.find.creditOnArrival' => (
        t('statement.short.onArrival'),
        v['amount'] ?? '',
      ),
      'statement.find.partCredit' => (
        t('statement.short.partCredit'),
        t('statement.short.days', {'n': v['days'] ?? ''}),
      ),
      'statement.find.totalsOff' => (t('statement.short.totalsOff'), '!'),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = [...widget.findings]
      ..sort((a, b) => _rank(a.severity).compareTo(_rank(b.severity)));
    if (rows.isEmpty) return const SizedBox.shrink();
    final calm = reduceMotion(context);
    Color tone(FindingSeverity s) => switch (s) {
      FindingSeverity.ok => c.up,
      FindingSeverity.bad => c.down,
      FindingSeverity.warn => c.accentInk,
      FindingSeverity.info => c.muted,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Builder(
              builder: (context) {
                final f = rows[i];
                final full = t(f.key, f.vars);
                final short = _short(f);
                final open = _open.contains(i);
                return Container(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: c.line)),
                  ),
                  child: Semantics(
                    button: short != null,
                    expanded: short == null ? null : open,
                    child: InkWell(
                      onTap: short == null
                          ? null
                          : () => setState(
                              () => open ? _open.remove(i) : _open.add(i),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _Mark(severity: f.severity),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    short?.$1 ?? full,
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: short == null
                                          ? FontWeight.w400
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (short != null && short.$2.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    short.$2,
                                    style: fructaFonts.numeric(
                                      color: tone(f.severity),
                                      size: 13,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (short != null)
                              AnimatedSize(
                                duration: Duration(
                                  milliseconds: calm ? 0 : 200,
                                ),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topLeft,
                                child: open
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          38,
                                          8,
                                          0,
                                          0,
                                        ),
                                        child: Text(
                                          full,
                                          style: TextStyle(
                                            color: c.muted,
                                            fontSize: 12.5,
                                            height: 1.45,
                                          ),
                                        ),
                                      )
                                    : const SizedBox(width: double.infinity),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Three figures under the finding: months credited, interest, tax.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.saved, required this.analysis});

  final SavedStatement saved;
  final StatementAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = saved.data;
    final months =
        (d.to.year - d.from.year) * 12 + d.to.month - d.from.month + 1;
    final credited = {
      for (final p in analysis.periods)
        if (p.interest > 0) p.end.year * 12 + p.end.month,
    }.length;
    Widget cell(String value, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: fructaFonts.numeric(
                  color: color,
                  size: 16,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          cell(
            t('statement.kpi.monthsOf', {
              'n': '${credited.clamp(0, months)}',
              'of': '$months',
            }),
            t('statement.kpi.months'),
            credited >= months ? c.up : c.accentInk,
          ),
          const SizedBox(width: 8),
          cell(
            money(d.currency, d.interest),
            t('statement.kpi.interest'),
            c.up,
          ),
          const SizedBox(width: 8),
          cell(money(d.currency, d.tax), t('statement.kpi.tax'), c.text),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.severity});

  final FindingSeverity severity;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, fg, bg) = switch (severity) {
      FindingSeverity.ok => (Icons.check_rounded, c.up, c.upSoft),
      FindingSeverity.info => (Icons.info_outline_rounded, c.muted, c.s2),
      FindingSeverity.warn => (
        Icons.priority_high_rounded,
        c.accentInk,
        c.accentSoft,
      ),
      FindingSeverity.bad => (Icons.close_rounded, c.down, c.downSoft),
    };
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: fg),
    );
  }
}

/// Credited yield per full month as bars, published average as a dashed line.
class _YieldBars extends StatelessWidget {
  const _YieldBars({required this.analysis});

  final StatementAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final periods = analysis.fullPeriods;
    final pub = analysis.recentPublishedPct;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion(context) ? 1.0 : 0.0, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, grow, _) => SizedBox(
            height: 176,
            width: double.infinity,
            child: CustomPaint(
              painter: _YieldPainter(
                values: [for (final p in periods) p.annualPct ?? 0],
                months: [for (final p in periods) monthLabel(p.end)],
                published: pub,
                above: c.up,
                below: c.down,
                line: c.text,
                grid: c.line,
                label: c.faint,
                grow: grow,
              ),
            ),
          ),
        ),
        if (pub != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _Key(color: c.up, label: t('statement.chart.above')),
              const SizedBox(width: 14),
              _Key(color: c.down, label: t('statement.chart.below')),
              const SizedBox(width: 14),
              _Key(
                color: c.text,
                label: t('statement.chart.published', {
                  'rate': pub.toStringAsFixed(2),
                }),
                dashed: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _YieldPainter extends CustomPainter {
  _YieldPainter({
    required this.values,
    required this.months,
    required this.published,
    required this.above,
    required this.below,
    required this.line,
    required this.grid,
    required this.label,
    required this.grow,
  });

  final List<double> values;
  final List<String> months;
  final double? published;
  final Color above;
  final Color below;
  final Color line;
  final Color grid;
  final Color label;

  /// 0 to 1: how far the bars have grown in.
  final double grow;

  /// Room for the rate labels on the left and the months underneath.
  static const _left = 34.0;
  static const _bottom = 16.0;

  void _text(Canvas canvas, String s, Offset at, {double ax = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: label, fontSize: 10.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width * ax, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (published != null) {
      if (published! < lo) lo = published!;
      if (published! > hi) hi = published!;
    }
    lo = (lo - 0.6).floorToDouble();
    hi = (hi + 0.3).ceilToDouble();
    final h = size.height - _bottom;
    double y(double v) => h - (v - lo) / (hi - lo) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = lo + 1; g < hi; g += 1) {
      canvas.drawLine(Offset(_left, y(g)), Offset(size.width, y(g)), gridPaint);
      _text(canvas, g.toStringAsFixed(1), Offset(_left - 6, y(g)), ax: 1);
    }

    final n = values.length;
    const gap = 4.0;
    final w = (size.width - _left - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final x = _left + i * (w + gap);
      final under = published != null && v < published!;
      final top = h - (h - y(v)) * grow;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(x, top, x + w, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = (under ? below : above).withValues(alpha: 0.9),
      );
      if (i < months.length && (n <= 6 || i.isEven || i == n - 1)) {
        _text(canvas, months[i], Offset(x + w / 2, size.height - 6), ax: 0.5);
      }
    }

    if (published != null) {
      final py = y(published!);
      final p = Paint()
        ..color = line
        ..strokeWidth = 1.4;
      for (var x = _left; x < size.width; x += 9) {
        canvas.drawLine(
          Offset(x, py),
          Offset((x + 5).clamp(0, size.width), py),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _YieldPainter old) =>
      old.values != values ||
      old.published != published ||
      old.above != above ||
      old.grow != grow;
}

/// Gross interest per credit, split into what was kept and what was withheld.
class _InterestBars extends StatelessWidget {
  const _InterestBars({required this.analysis});

  final StatementAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final periods = analysis.periods.where((p) => p.interest > 0).toList();
    return Column(
      children: [
        SizedBox(
          height: 110,
          width: double.infinity,
          child: CustomPaint(
            painter: _InterestPainter(
              gross: [for (final p in periods) p.interest],
              tax: [for (final p in periods) p.tax],
              kept: c.up,
              withheld: c.dataInk(c.down),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Key(color: c.up, label: t('statement.chart.kept')),
            const SizedBox(width: 14),
            _Key(color: c.dataInk(c.down), label: t('statement.chart.tax')),
          ],
        ),
      ],
    );
  }
}

class _InterestPainter extends CustomPainter {
  _InterestPainter({
    required this.gross,
    required this.tax,
    required this.kept,
    required this.withheld,
  });

  final List<double> gross;
  final List<double> tax;
  final Color kept;
  final Color withheld;

  @override
  void paint(Canvas canvas, Size size) {
    if (gross.isEmpty) return;
    final mx = gross.reduce((a, b) => a > b ? a : b) * 1.08;
    final n = gross.length;
    const gap = 4.0;
    final w = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final hAll = gross[i] / mx * size.height;
      final hTax = tax[i] / mx * size.height;
      final top = size.height - hAll;
      canvas.drawRect(
        Rect.fromLTWH(x, top, w, hTax),
        Paint()..color = withheld,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, top + hTax, w, hAll - hTax),
        Paint()..color = kept,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InterestPainter old) =>
      old.gross != gross || old.kept != kept;
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dashed ? 14 : 10,
            height: dashed ? 2 : 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

/// Paid in, taken out, interest, tax and the closing balance.
class _Totals extends StatelessWidget {
  const _Totals({required this.saved});

  final SavedStatement saved;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = saved.data;
    String amt(double v) => money(d.currency, v.abs());
    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(
            value,
            style: fructaFonts.numeric(
              color: color,
              size: 14.5,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return _Card(
      title: t('statement.totals'),
      child: Column(
        children: [
          Row(
            children: [
              cell(t('statement.paidIn'), amt(d.deposits), c.text),
              cell(t('statement.takenOut'), amt(d.withdrawals), c.text),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell(t('statement.interest'), '+${amt(d.interest)}', c.up),
              cell(t('statement.tax'), '-${amt(d.tax)}', c.down),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('statement.balanceOn', {'date': dayLabel(d.to)}),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
                Text(
                  money(d.currency, d.closingBalance),
                  style: fructaFonts.numeric(
                    color: c.text,
                    size: 18,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What Pro adds to a statement check, for free users.
class _ProCard extends ConsumerWidget {
  const _ProCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProBadge(),
          const SizedBox(height: 10),
          Text(
            t('statement.pro.title'),
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          RevealText(
            t('statement.pro.body'),
            style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () =>
                  ensurePro(context, ref, source: 'statement_check'),
              child: Text(
                t('statement.pro.cta'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

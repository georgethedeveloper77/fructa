import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../statements/statement_controller.dart';
import '../wrap/wrap_engine.dart';
import '../wrap/wrap_feed.dart';

/// The archive in one screen, whatever its length.
///
/// A line of the KES money market median over the period's wraps, a calendar
/// of the same wraps coloured by how the median moved, and the selected
/// wrap's lead story as a card. Scrubbing the line, tapping a cell or tapping
/// a point all select the same wrap, so the three move together.
class ArchiveHybrid extends StatefulWidget {
  const ArchiveHybrid({
    super.key,
    required this.periods,
    required this.isFree,
    required this.onOpen,
  });

  final Map<WrapPeriod, List<ArchiveWrap>> periods;

  /// Whether a free user may open [wrap], at [index] newest first.
  final bool Function(ArchiveWrap wrap, int index) isFree;
  final void Function(ArchiveWrap wrap, bool free) onOpen;

  @override
  State<ArchiveHybrid> createState() => _ArchiveHybridState();
}

class _ArchiveHybridState extends State<ArchiveHybrid> {
  late WrapPeriod _period =
      (widget.periods[WrapPeriod.week]?.isNotEmpty ?? false)
      ? WrapPeriod.week
      : WrapPeriod.values.firstWhere(
          (p) => widget.periods[p]?.isNotEmpty ?? false,
          orElse: () => WrapPeriod.week,
        );

  /// Index into the oldest-first list; null is the newest.
  int? _sel;

  /// The year on the timeline. Every period but Years shows one year,
  /// January to December, so the line reads as a calendar.
  int _year = DateTime.now().year;

  static const _labels = {
    WrapPeriod.day: 'reports.days',
    WrapPeriod.week: 'reports.weeks',
    WrapPeriod.month: 'reports.months',
    WrapPeriod.quarter: 'reports.quarters',
    WrapPeriod.year: 'reports.years',
  };

  static const _empty = {
    WrapPeriod.day: 'reports.daysEmpty',
    WrapPeriod.week: 'reports.weeksEmpty',
    WrapPeriod.month: 'reports.monthsEmpty',
    WrapPeriod.quarter: 'reports.quartersEmpty',
    WrapPeriod.year: 'reports.yearsEmpty',
  };

  void _pick(int i, int n) {
    final k = i.clamp(0, n - 1);
    if (k == (_sel ?? n - 1)) return;
    HapticFeedback.selectionClick();
    setState(() => _sel = k);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final years = {
      for (final l in widget.periods.values)
        for (final w in l) w.to.year,
    }.toList()..sort((a, b) => b.compareTo(a));
    if (years.isNotEmpty && !years.contains(_year)) _year = years.first;
    final byYear = _period != WrapPeriod.year;
    final newest = [
      for (final w in widget.periods[_period] ?? const <ArchiveWrap>[])
        if (!byYear || w.to.year == _year) w,
    ];
    final items = newest.reversed.toList();
    final n = items.length;
    final sel = n == 0 ? 0 : (_sel ?? n - 1).clamp(0, n - 1);

    Widget tab(WrapPeriod p) {
      final on = p == _period;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            onTap: () => setState(() {
              _period = p;
              _sel = null;
            }),
            child: AnimatedContainer(
              duration: Duration(milliseconds: reduceMotion(context) ? 0 : 200),
              constraints: const BoxConstraints(minHeight: 38),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.text : c.s2.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  t(_labels[p]!),
                  style: TextStyle(
                    color: on ? c.bg : c.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (byYear && years.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: _YearPicker(
                years: years,
                year: _year,
                onPick: (y) => setState(() {
                  _year = y;
                  _sel = null;
                }),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.s2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(children: [for (final p in WrapPeriod.values) tab(p)]),
        ),
        const SizedBox(height: 12),
        if (n == 0)
          _Box(
            child: Text(
              t(_empty[_period]!),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          )
        else ...[
          _Timeline(
            items: items,
            period: _period,
            year: _year,
            selected: sel,
            onPick: (i) => _pick(i, n),
          ),
          const SizedBox(height: 12),
          _Calendar(
            items: items,
            period: _period,
            selected: sel,
            onPick: (i) => _pick(i, n),
          ),
          const SizedBox(height: 12),
          _LeadCard(
            wrap: items[sel],
            free: widget.isFree(items[sel], n - 1 - sel),
            onOpen: () => widget.onOpen(
              items[sel],
              widget.isFree(items[sel], n - 1 - sel),
            ),
          ),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// The median across the period's wraps. Drag or tap to select a wrap.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.items,
    required this.period,
    required this.year,
    required this.selected,
    required this.onPick,
  });

  final List<ArchiveWrap> items;
  final WrapPeriod period;
  final int year;
  final int selected;
  final ValueChanged<int> onPick;

  /// Where each wrap sits across the axis, 0 to 1: by date within the year,
  /// or evenly for Years.
  List<double> _xs() {
    if (period == WrapPeriod.year) {
      final n = items.length;
      return [for (var i = 0; i < n; i++) n == 1 ? 0.5 : i / (n - 1)];
    }
    final a = DateTime(year);
    final span = DateTime(year + 1).difference(a).inHours;
    return [
      for (final w in items)
        (w.to.difference(a).inHours / span).clamp(0.0, 1.0),
    ];
  }

  /// Today's place on the axis, when the year shown is this one.
  double? _today() {
    final now = DateTime.now();
    if (period == WrapPeriod.year || now.year != year) return null;
    final a = DateTime(year);
    return now.difference(a).inHours / DateTime(year + 1).difference(a).inHours;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = items[selected];
    final calm = reduceMotion(context);
    final xs = _xs();
    final today = _today();
    final ticks = switch (period) {
      WrapPeriod.year => [for (final w in items) '${w.to.year}'],
      WrapPeriod.quarter => const ['Q1', 'Q2', 'Q3', 'Q4'],
      _ => _monthShort,
    };

    return _Box(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  t('reports.medianTitle'),
                  style: TextStyle(color: c.muted, fontSize: 11.5),
                ),
              ),
              Text(
                s.median == null ? '' : '${s.median!.toStringAsFixed(2)}%',
                style: fructaFonts.numeric(
                  color: c.accentInk,
                  size: 15,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              // The wrap nearest the finger.
              int at(double x) {
                final f = (x / box.maxWidth).clamp(0.0, 1.0);
                var best = 0;
                for (var i = 1; i < xs.length; i++) {
                  if ((xs[i] - f).abs() < (xs[best] - f).abs()) best = i;
                }
                return best;
              }

              return Semantics(
                label: t('reports.medianTitle'),
                value: s.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => onPick(at(d.localPosition.dx)),
                  onHorizontalDragUpdate: (d) => onPick(at(d.localPosition.dx)),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: calm ? 1.0 : 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeInOutCubic,
                    builder: (_, v, _) => CustomPaint(
                      size: Size(box.maxWidth, 140),
                      painter: _LinePainter(
                        xs: xs,
                        today: today,
                        values: [for (final w in items) w.median],
                        moves: [for (final w in items) w.move],
                        big: [for (final w in items) w.big],
                        selected: selected,
                        progress: v,
                        line: c.accent,
                        up: c.up,
                        down: c.down,
                        grid: c.line,
                        marker: c.text,
                        bg: c.s1,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          // January to December under the year; one label per year for Years.
          Row(
            children: [
              for (final l in ticks)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 10.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.xs,
    required this.today,
    required this.values,
    required this.moves,
    required this.big,
    required this.selected,
    required this.progress,
    required this.line,
    required this.up,
    required this.down,
    required this.grid,
    required this.marker,
    required this.bg,
  });

  /// Each value's place across the axis, 0 to 1.
  final List<double> xs;

  /// Where today sits, for the current year.
  final double? today;
  final List<double?> values;
  final List<double?> moves;
  final List<bool> big;
  final int selected;
  final double progress;
  final Color line;
  final Color up;
  final Color down;
  final Color grid;
  final Color marker;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final known = [for (final v in values) ?v];
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in [size.height * 0.25, size.height * 0.65]) {
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), g);
      }
    }
    final n = values.length;
    double xAt(int i) => 2 + xs[i] * (size.width - 4);
    // The rest of the year is still to come: a faint line marks today.
    if (today != null) {
      final x = 2 + today! * (size.width - 4);
      final p = Paint()
        ..color = marker.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      for (var y = 0.0; y < size.height; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), p);
      }
    }
    if (known.length < 2) {
      _marker(canvas, size, xAt(selected), null);
      return;
    }
    final lo = known.reduce((a, b) => a < b ? a : b) - 0.05;
    final hi = known.reduce((a, b) => a > b ? a : b) + 0.05;
    double yAt(double v) =>
        size.height - 8 - (v - lo) / (hi - lo) * (size.height - 16);

    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(xAt(i), yAt(v));
      started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      started = true;
    }
    final drawn = Path();
    for (final m in path.computeMetrics()) {
      drawn.addPath(m.extractPath(0, m.length * progress), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (progress >= 1) {
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null || !big[i]) continue;
        canvas.drawCircle(
          Offset(xAt(i), yAt(v)),
          3.5,
          Paint()..color = (moves[i] ?? 0) < 0 ? down : up,
        );
      }
    }
    final v = values[selected];
    _marker(canvas, size, xAt(selected), v == null ? null : yAt(v));
  }

  void _marker(Canvas canvas, Size size, double x, double? y) {
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = marker.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
    if (y == null) return;
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = bg);
    canvas.drawCircle(
      Offset(x, y),
      6,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.selected != selected ||
      old.progress != progress ||
      old.xs != xs ||
      old.values != values ||
      old.line != line;
}

/// The same wraps as cells, coloured by the median's move. Months and
/// quarters sit in their fixed place in the year (January to December, Q1 to
/// Q4), with the months still to come left empty. Weeks are rows by month and
/// days rows by week, newest first; years one row.
class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.items,
    required this.period,
    required this.selected,
    required this.onPick,
  });

  final List<ArchiveWrap> items;
  final WrapPeriod period;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calm = reduceMotion(context);

    Color tint(double? mv) {
      if (mv == null) return c.s3;
      final a = (0.22 + mv.abs() * 2.2).clamp(0.22, 0.9);
      return (mv >= 0 ? c.up : c.down).withValues(alpha: a);
    }

    Widget cell(int? i, {bool value = true}) => Expanded(
      child: i == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.line),
                ),
              ),
            )
          : _Cell(
              wrap: items[i],
              on: i == selected,
              tint: tint(items[i].move),
              calm: calm,
              showValue: value,
              onTap: () => onPick(i),
            ),
    );

    Widget labelled(String? label, List<Widget> cells) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (label != null)
            SizedBox(
              width: 38,
              child: Text(
                label,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
          ...cells,
        ],
      ),
    );

    final rows = <Widget>[];
    switch (period) {
      case WrapPeriod.month || WrapPeriod.quarter:
        final slots = period == WrapPeriod.month ? 12 : 4;
        final at = <int, int>{
          for (var i = 0; i < items.length; i++)
            (period == WrapPeriod.month
                    ? items[i].to.month - 1
                    : (items[i].to.month - 1) ~/ 3):
                i,
        };
        rows.add(
          labelled(null, [
            for (var k = 0; k < slots; k++) cell(at[k], value: slots <= 4),
          ]),
        );
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var k = 0; k < slots; k++)
                  Expanded(
                    child: Text(
                      period == WrapPeriod.month
                          ? _monthShort[k].substring(0, 1)
                          : 'Q${k + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.faint, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
        );
      case WrapPeriod.year:
        for (var r = items.length - 1; r >= 0; r -= 6) {
          final row = [for (var i = (r - 5).clamp(0, r); i <= r; i++) i];
          rows.add(
            labelled(null, [
              for (final i in row) cell(i),
              for (var k = row.length; k < 6; k++)
                const Expanded(child: SizedBox(height: 36)),
            ]),
          );
        }
      case WrapPeriod.week || WrapPeriod.day:
        final per = period == WrapPeriod.week ? 5 : 7;
        final groups = <String, List<int>>{};
        for (var i = 0; i < items.length; i++) {
          final d = items[i].to;
          final key = period == WrapPeriod.week
              ? '${d.month}'
              : '${d.month}-${(d.day - 1) ~/ 7}';
          groups.putIfAbsent(key, () => []).add(i);
        }
        for (final g in groups.values.toList().reversed) {
          rows.add(
            labelled(_monthShort[items[g.first].to.month - 1], [
              for (var j = 0; j < per; j++)
                j < g.length
                    ? cell(g[j])
                    : const Expanded(child: SizedBox(height: 36)),
            ]),
          );
        }
    }

    return _Box(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('reports.calendarTitle'),
            style: TextStyle(color: c.muted, fontSize: 11.5),
          ),
          ...rows,
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Key(color: c.up, label: t('reports.key.rose')),
              _Key(color: c.down, label: t('reports.key.fell')),
              _Key(color: c.accent, label: t('reports.key.big'), outline: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// The year on the timeline, as a small dropdown.
class _YearPicker extends StatelessWidget {
  const _YearPicker({
    required this.years,
    required this.year,
    required this.onPick,
  });

  final List<int> years;
  final int year;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopupMenuButton<int>(
      tooltip: t('reports.year'),
      initialValue: year,
      onSelected: onPick,
      color: c.s2,
      itemBuilder: (_) => [
        for (final y in years)
          PopupMenuItem<int>(
            value: y,
            child: Text(
              '$y',
              style: fructaFonts.numeric(
                color: y == year ? c.accentInk : c.text,
                size: 14,
                weight: FontWeight.w600,
              ),
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$year',
              style: fructaFonts.numeric(
                color: c.text,
                size: 13.5,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.wrap,
    required this.on,
    required this.tint,
    required this.calm,
    required this.showValue,
    required this.onTap,
  });

  final ArchiveWrap wrap;
  final bool on;
  final Color tint;
  final bool calm;
  final bool showValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mv = wrap.move;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        button: true,
        selected: on,
        label: wrap.label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: on ? 1.06 : 1,
            duration: Duration(milliseconds: calm ? 0 : 160),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(9),
                border: on
                    ? Border.all(color: c.text, width: 2)
                    : wrap.big
                    ? Border.all(color: c.accent, width: 1.5)
                    : null,
              ),
              child: showValue && mv != null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${mv >= 0 ? '+' : ''}${mv.toStringAsFixed(2)}',
                        style: fructaFonts.numeric(
                          color: c.text,
                          size: 10.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.outline = false});

  final Color color;
  final String label;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: outline ? null : color,
            border: outline ? Border.all(color: color, width: 1.5) : null,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
      ],
    );
  }
}

/// The selected wrap's lead story, in its fund's brand glow.
class _LeadCard extends ConsumerWidget {
  const _LeadCard({
    required this.wrap,
    required this.free,
    required this.onOpen,
  });

  final ArchiveWrap wrap;
  final bool free;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    WrapSlide? lead;
    for (final s in wrap.slides) {
      if (!s.personal) {
        lead = s;
        break;
      }
    }
    final fund = lead?.fundId == null
        ? null
        : ref.watch(fundsByIdProvider)[lead!.fundId];
    final brand = fund == null ? null : ref.watch(brandColorProvider(fund.id));
    final glow = brand == null ? c.accent : c.brandOnBg(brand);
    final tone = switch (lead?.tone) {
      WrapTone.up => c.up,
      WrapTone.down => c.down,
      _ => c.accentInk,
    };
    final calm = reduceMotion(context);
    final title = wrap.label.isNotEmpty
        ? wrap.label
        : t('reports.range', {
            'from': dayLabel(wrap.from),
            'to': dayLabel(wrap.to),
          });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: calm ? 0 : 240),
        child: Material(
          key: ValueKey(wrap.id),
          color: c.s1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: c.line),
          ),
          child: InkWell(
            onTap: onOpen,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1, -1),
                  radius: 1.4,
                  colors: [
                    glow.withValues(alpha: 0.28),
                    glow.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (fund != null) ...[
                      FundLogo(
                        domain: fund.logoDomain,
                        seed: fund.manager,
                        logoUrl: ref.watch(logoUrlProvider(fund.id)),
                        brandColor: brand,
                        size: 46,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(color: c.muted, fontSize: 11.5),
                          ),
                          if (lead != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              t(lead.tagKey),
                              style: TextStyle(
                                color: tone,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              lead.title,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            t('reports.stories', {
                              'n': '${wrap.slides.length}',
                            }),
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (lead != null)
                          Text(
                            lead.big,
                            style: fructaFonts.numeric(
                              color: tone,
                              size: 24,
                              weight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(minHeight: 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: free ? c.accent : c.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                free
                                    ? Icons.play_arrow_rounded
                                    : Icons.lock_outline_rounded,
                                size: 16,
                                color: free ? c.onAccent : c.accentInk,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t(free ? 'wrap.card.play' : 'reports.pro'),
                                style: TextStyle(
                                  color: free ? c.onAccent : c.accentInk,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

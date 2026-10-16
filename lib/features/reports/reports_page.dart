import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_analysis.dart';
import '../pro/pro_widgets.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../wrap/wrap_engine.dart';
import '../wrap/wrap_viewer.dart';
import 'report_archive.dart';
import 'report_notify.dart';
import 'report_pdf.dart';

/// Every report in one place: this week's wrap, last month's, past wraps,
/// statement checks and the yearly tax pack. All of it is kept on the phone.
///
/// Free users get this week's wrap. The month wrap, past wraps, PDFs and the
/// tax pack are Pro (open to everyone while Pro is switched off remotely).
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep this week and last month in the archive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final month = ref.read(monthWrapProvider);
      ref.read(wrapArchiveProvider.notifier)
        ..saveWeek(ref.read(weeklyWrapProvider))
        ..saveMonth(month);
      // Opening Reports clears the dot on its entry rows.
      ref.read(reportSeenProvider.notifier).mark(monthId(month.from));
    });
  }

  bool get _full => ref.read(wrapPersonalUnlockedProvider);

  /// Runs [action] when the user has Pro, after the paywall otherwise.
  Future<void> _pro(String source, Future<void> Function() action) async {
    if (!_full && !await ensurePro(context, ref, source: source)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _monthPdf(MonthWrap m) => _pro('reports_month_pdf', () async {
    final statements =
        ref.read(statementsProvider).value ?? const <SavedStatement>[];
    final analyses = <StatementAnalysis>[];
    for (final s in statements.where((s) => !s.data.to.isBefore(m.from))) {
      final r = await ref.read(statementAnalysisProvider(s.id).future);
      analyses.add(r.analysis);
    }
    final bytes = await ReportPdf.month(m, statements: analyses);
    await ReportPdf.share(
      bytes,
      'fructa-${m.from.year}-${m.from.month.toString().padLeft(2, '0')}.pdf',
    );
  });

  Future<void> _statementPdf(
    SavedStatement s,
  ) => _pro('reports_statement_pdf', () async {
    final r = await ref.read(statementAnalysisProvider(s.id).future);
    final bytes = await ReportPdf.statement(s, r.analysis);
    await ReportPdf.share(
      bytes,
      'fructa-statement-${s.data.managerKey}-${s.data.to.year}-${s.data.to.month}.pdf',
    );
  });

  Future<void> _taxPdf(int year, List<TaxRow> rows) =>
      _pro('reports_tax_pdf', () async {
        final bytes = await ReportPdf.tax(year, rows);
        await ReportPdf.share(bytes, 'fructa-tax-$year.pdf');
      });

  void _openMonth(MonthWrap m) => _pro('reports_month', () async {
    await openWrap(
      context,
      WrapViewer(
        slides: m.slides,
        kicker: t('reports.monthKicker', {'month': monthName(m.from)}),
        range: '${dayLabel(m.from)} to ${dayLabel(m.to)}',
        onPdf: () => _monthPdf(m),
      ),
    );
  });

  void _openSaved(SavedWrap w) => _pro('reports_archive', () async {
    await openWrap(
      context,
      WrapViewer(
        slides: w.slides,
        kicker: w.monthly
            ? t('reports.monthKicker', {'month': monthName(w.from)})
            : t('reports.weekKicker'),
        range: '${dayLabel(w.from)} to ${dayLabel(w.to)}',
      ),
    );
  });

  /// The archived free week: market stories only, no paywall.
  void _openFreeWeek(SavedWrap w) => openWrap(
    context,
    WrapViewer(
      slides: w.slides.where((s) => !s.personal).toList(),
      kicker: t('reports.weekKicker'),
      range: '${dayLabel(w.from)} to ${dayLabel(w.to)}',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final full = ref.watch(wrapPersonalUnlockedProvider);
    final month = ref.watch(monthWrapProvider);
    final thisWeek = WrapArchive.weekId(DateTime.now());
    final thisMonth = monthId(month.from);
    final archive = ref.watch(wrapArchiveProvider).value ?? const <SavedWrap>[];
    // This week and last month have their own cards above, so the archive
    // starts after them and nothing shows twice.
    final weeks = [
      for (final w in archive)
        if (!w.monthly && w.id != thisWeek) w,
    ];
    final months = [
      for (final w in archive)
        if (w.monthly && w.id != thisMonth) w,
    ];
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final taxes = taxByYear(statements);
    final years = taxes.keys.toList()..sort((a, b) => b.compareTo(a));
    final hide = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );

    // Earnings by month for the small chart: past months from the archive,
    // then the month just ended.
    final earned = <(DateTime, double)>[
      for (final w in months.reversed)
        if (_earnedIn(w.slides) case final v?) (w.from, v),
      if (month.holdings.isNotEmpty) (month.from, month.earnedKes),
    ];
    final series = earned.length > 6
        ? earned.sublist(earned.length - 6)
        : earned;
    final monthStatements = statements
        .where((s) => !s.data.to.isBefore(month.from))
        .length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('reports.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 15, color: c.up),
                const SizedBox(width: 5),
                Text(
                  t('reports.onPhone'),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              _Heading(t('reports.thisWeek')),
              const WeeklyWrapCard(),

              _Heading(monthName(month.from).split(' ').first),
              _MonthCard(
                month: month,
                series: series,
                statements: monthStatements,
                locked: !full,
                hide: hide,
                onOpen: () => _openMonth(month),
                onPdf: () => _monthPdf(month),
              ),

              _Heading(t('reports.statements')),
              _Card(
                child: Column(
                  children: [
                    for (final s in statements)
                      _StatementRow(
                        saved: s,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StatementDetailPage(saved: s),
                          ),
                        ),
                        onPdf: () => _statementPdf(s),
                      ),
                    _ActionRow(
                      icon: Icons.upload_file_rounded,
                      label: t('statement.entry.check'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StatementCheckPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _Heading(t('reports.tax')),
              if (years.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    t('reports.taxEmpty'),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                )
              else
                for (final y in years)
                  _TaxCard(
                    year: y,
                    rows: taxes[y]!,
                    locked: !full,
                    hide: hide,
                    onTap: () => _taxPdf(y, taxes[y]!),
                  ),

              if (weeks.isNotEmpty || months.isNotEmpty) ...[
                _Heading(t('reports.archive')),
                _Archive(
                  weeks: weeks,
                  months: months,
                  full: full,
                  hide: hide,
                  onFreeWeek: _openFreeWeek,
                  onSaved: _openSaved,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                    t('reports.archiveNote'),
                    style: TextStyle(color: c.faint, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: c.bg.withValues(alpha: 0.5),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// What a saved month's "you earned" story says, in KES, or null.
double? _earnedIn(List<WrapSlide> slides) {
  for (final s in slides) {
    if (s.tagKey != 'wrap.tag.earned') continue;
    final m = RegExp(r'-?[\d,]+(?:\.\d+)?').firstMatch(s.big);
    if (m != null) return double.tryParse(m.group(0)!.replaceAll(',', ''));
  }
  return null;
}

String _kes(double v, {required bool hide}) => hide
    ? 'KES \u2022\u2022\u2022\u2022'
    : 'KES ${_grouped(v.toStringAsFixed(0))}';

/// 1896.4 reads as 1,896.40.
String _cents(double v) {
  final p = v.toStringAsFixed(2).split('.');
  return '${_grouped(p[0])}.${p[1]}';
}

String _grouped(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Small caps heading over a block.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.c.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );
}

/// The rounded surface every block sits on.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// Blurs figures a free user cannot see yet; leaves them sharp otherwise.
class _Veil extends StatelessWidget {
  const _Veil({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => on
      ? ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ExcludeSemantics(child: child),
        )
      : child;
}

/// Last month, figure first: what the user earned, a few months of history,
/// three small facts, then open and PDF. With no holdings it leads with the
/// market instead.
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.series,
    required this.statements,
    required this.locked,
    required this.hide,
    required this.onOpen,
    required this.onPdf,
  });

  final MonthWrap month;
  final List<(DateTime, double)> series;
  final int statements;
  final bool locked;
  final bool hide;
  final VoidCallback onOpen;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mine = month.holdings.isNotEmpty;
    final top = month.topFunds.isEmpty ? null : month.topFunds.first.$2;
    final n = month.holdings.length;
    final name = monthName(month.from).split(' ').first;

    return _Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(mine ? 'reports.earned' : 'reports.marketTop'),
            style: TextStyle(color: c.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          _Veil(
            on: locked && mine,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                mine
                    ? _kes(month.earnedKes, hide: hide)
                    : top == null
                    ? '-'
                    : '${top.toStringAsFixed(2)}%',
                style: fructaFonts.numeric(
                  color: mine ? c.up : c.text,
                  size: 40,
                  weight: FontWeight.w600,
                  letterSpacing: -1.2,
                  height: 1,
                ),
              ),
            ),
          ),
          if (mine && series.length >= 2) ...[
            const SizedBox(height: 14),
            _Veil(
              on: locked,
              child: _EarnedBars(series: series),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '$n',
                  label: t(
                    n == 1
                        ? 'reports.stat.holdingOne'
                        : 'reports.stat.holdingMany',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: top == null ? '-' : '${top.toStringAsFixed(2)}%',
                  label: t('reports.stat.topRate'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: '$statements',
                  label: t(
                    statements == 1
                        ? 'reports.stat.stmtOne'
                        : 'reports.stat.stmtMany',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onOpen,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          locked
                              ? t('reports.seeMonth')
                              : t('reports.open', {'month': name}),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 8),
                        const ProBadge(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PdfButton(onTap: onPdf),
            ],
          ),
        ],
      ),
    );
  }
}

/// Earnings for the last few months, the newest in green.
class _EarnedBars extends StatelessWidget {
  const _EarnedBars({required this.series});

  final List<(DateTime, double)> series;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = series.map((e) => e.$2).fold(0.0, math.max);
    const months = [
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
    return SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < series.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
                    duration: Duration(milliseconds: 500 + i * 70),
                    curve: Curves.easeOutBack,
                    builder: (_, v, _) => Container(
                      height: math.max(
                        3.0,
                        32 * (top <= 0 ? 0 : series[i].$2 / top) * v,
                      ),
                      decoration: BoxDecoration(
                        color: i == series.length - 1 ? c.up : c.line2,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    months[series[i].$1.month - 1],
                    style: TextStyle(color: c.faint, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
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
                color: c.text,
                size: 15,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// A checked statement, its gap first: red below published, green above.
class _StatementRow extends ConsumerWidget {
  const _StatementRow({
    required this.saved,
    required this.onTap,
    required this.onPdf,
  });

  final SavedStatement saved;
  final VoidCallback onTap;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final d = saved.data;
    final gap = ref
        .watch(statementAnalysisProvider(saved.id))
        .value
        ?.analysis
        .gapPts;
    final tone = gap == null
        ? c.muted
        : gap <= -0.005
        ? c.down
        : gap >= 0.005
        ? c.up
        : c.muted;
    final name = d.managerName.isEmpty
        ? t('statement.unknownManager')
        : d.managerName;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  gap == null
                      ? '-'
                      : '${gap > 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
                  style: fructaFonts.numeric(
                    color: tone,
                    size: 18,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name \u00b7 ${d.currency}',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('reports.range', {
                      'from': dayLabel(d.from),
                      'to': dayLabel(d.to),
                    }),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: t('reports.savePdf'),
              onPressed: onPdf,
              icon: Icon(
                Icons.picture_as_pdf_outlined,
                size: 20,
                color: c.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The accent action at the foot of a list.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: c.accentInk),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: c.accentInk,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One year's withholding tax, total first, ready for the KRA return.
class _TaxCard extends StatelessWidget {
  const _TaxCard({
    required this.year,
    required this.rows,
    required this.locked,
    required this.hide,
    required this.onTap,
  });

  final int year;
  final List<TaxRow> rows;
  final bool locked;
  final bool hide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final total = rows.fold(0.0, (s, r) => s + r.tax);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('reports.taxWithheld', {'year': '$year'}),
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 2),
                      _Veil(
                        on: locked,
                        child: Text(
                          hide
                              ? 'KES \u2022\u2022\u2022\u2022'
                              : 'KES ${_cents(total)}',
                          style: fructaFonts.numeric(
                            color: c.text,
                            size: 24,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t(
                          rows.length == 1
                              ? 'reports.taxFromOne'
                              : 'reports.taxFromMany',
                          {'n': '${rows.length}'},
                        ),
                        style: TextStyle(color: c.faint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (locked) const ProBadge() else _PdfButton(onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Past wraps, weeks or months, each led by its headline story.
class _Archive extends StatefulWidget {
  const _Archive({
    required this.weeks,
    required this.months,
    required this.full,
    required this.hide,
    required this.onFreeWeek,
    required this.onSaved,
  });

  final List<SavedWrap> weeks;
  final List<SavedWrap> months;
  final bool full;
  final bool hide;
  final ValueChanged<SavedWrap> onFreeWeek;
  final ValueChanged<SavedWrap> onSaved;

  @override
  State<_Archive> createState() => _ArchiveState();
}

class _ArchiveState extends State<_Archive> {
  late bool _months = widget.weeks.isEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = _months ? widget.months : widget.weeks;

    Widget tab(String label, bool on, bool months) => Expanded(
      child: Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: () => setState(() => _months = months),
          child: AnimatedContainer(
            duration: Duration(milliseconds: reduceMotion(context) ? 0 : 200),
            constraints: const BoxConstraints(minHeight: 38),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.text : c.s2.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? c.bg : c.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.s2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              tab(t('reports.weeks'), !_months, false),
              tab(t('reports.months'), _months, true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Card(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t(_months ? 'reports.monthsEmpty' : 'reports.weeksEmpty'),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _ArchiveRow(
                        wrap: items[i],
                        first: i == 0,
                        hide: widget.hide,
                        // The latest past week is free; the rest are Pro.
                        locked: !widget.full && (_months || i > 0),
                        onTap: () => !widget.full && !_months && i == 0
                            ? widget.onFreeWeek(items[i])
                            : widget.onSaved(items[i]),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({
    required this.wrap,
    required this.first,
    required this.hide,
    required this.locked,
    required this.onTap,
  });

  final SavedWrap wrap;
  final bool first;
  final bool hide;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final earned = wrap.monthly ? _earnedIn(wrap.slides) : null;
    WrapSlide? lead;
    for (final s in wrap.slides) {
      if (!s.personal) {
        lead = s;
        break;
      }
    }
    final title = wrap.monthly
        ? monthName(wrap.from)
        : t('reports.range', {
            'from': dayLabel(wrap.from),
            'to': dayLabel(wrap.to),
          });
    final figure = earned != null ? _kes(earned, hide: hide) : lead?.big ?? '';
    final what = earned != null
        ? t('reports.earnedShort')
        : lead == null
        ? t('reports.stories', {'n': '${wrap.slides.length}'})
        : lead.title;
    final tone = earned != null
        ? c.up
        : lead == null
        ? c.muted
        : switch (lead.tone) {
            WrapTone.up => c.up,
            WrapTone.down => c.down,
            _ => c.accentInk,
          };

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (figure.isNotEmpty)
                          TextSpan(
                            text: '$figure  ',
                            style: fructaFonts.numeric(
                              color: tone,
                              size: 12,
                              weight: FontWeight.w700,
                            ),
                          ),
                        TextSpan(text: what),
                      ],
                    ),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (locked) ...[const ProBadge(), const SizedBox(width: 6)],
            Icon(Icons.chevron_right_rounded, color: c.faint, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Bordered PDF action, sized for a thumb.
class _PdfButton extends StatelessWidget {
  const _PdfButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: t('reports.savePdf'),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.line2),
          minimumSize: const Size(46, 46),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(
          t('reports.pdf'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Portfolio's (and You's) way into Reports. Shows a dot and says so when
/// last month's report is ready and not yet opened.
class ReportsEntryRow extends ConsumerWidget {
  const ReportsEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final ready = ref.watch(newReportProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ReportsPage())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.summarize_outlined,
                    size: 19,
                    color: c.accentInk,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('reports.title'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ready == null
                            ? t('reports.entrySub')
                            : t('reports.ready', {
                                'month': monthName(ready.from).split(' ').first,
                              }),
                        style: TextStyle(
                          color: ready == null ? c.muted : c.accentInk,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ready != null) ...[
                  Semantics(
                    label: t('common.new'),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

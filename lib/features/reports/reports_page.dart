import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_analysis.dart';
import '../pro/pro_widgets.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../wrap/wrap_engine.dart';
import '../wrap/wrap_viewer.dart';
import 'report_archive.dart';
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
      ref.read(wrapArchiveProvider.notifier)
        ..saveWeek(ref.read(weeklyWrapProvider))
        ..saveMonth(ref.read(monthWrapProvider));
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final full = ref.watch(wrapPersonalUnlockedProvider);
    final month = ref.watch(monthWrapProvider);
    final thisWeek = WrapArchive.weekId(DateTime.now());
    final archive =
        (ref.watch(wrapArchiveProvider).value ?? const <SavedWrap>[])
            .where((w) => w.id != thisWeek)
            .toList();
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final taxes = taxByYear(statements);
    final years = taxes.keys.toList()..sort((a, b) => b.compareTo(a));

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
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  t('reports.sub'),
                  style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4),
                ),
              ),
              const WeeklyWrapCard(),

              _Heading(t('reports.monthHeading')),
              _Row(
                icon: Icons.calendar_month_outlined,
                title: t('reports.monthTitle', {
                  'month': monthName(month.from),
                }),
                sub: month.holdings.isEmpty
                    ? t('reports.monthSubMarket')
                    : t('reports.monthSub', {'n': '${month.holdings.length}'}),
                locked: !full,
                onTap: () => _openMonth(month),
                trailing: _PdfButton(onTap: () => _monthPdf(month)),
              ),

              if (archive.isNotEmpty) ...[
                _Heading(t('reports.past')),
                for (var i = 0; i < archive.length; i++)
                  _Row(
                    icon: archive[i].monthly
                        ? Icons.calendar_month_outlined
                        : Icons.auto_stories_outlined,
                    title: archive[i].monthly
                        ? t('reports.monthTitle', {
                            'month': monthName(archive[i].from),
                          })
                        : t('reports.weekTitle', {
                            'date': dayLabel(archive[i].to),
                          }),
                    sub: t('reports.stories', {
                      'n': '${archive[i].slides.length}',
                    }),
                    // The most recent past wrap is free; older ones are Pro.
                    locked: !full && i > 0,
                    onTap: () => i == 0 && !full
                        ? openWrap(
                            context,
                            WrapViewer(
                              slides: archive[i].slides
                                  .where((s) => !s.personal)
                                  .toList(),
                              kicker: t('reports.weekKicker'),
                              range:
                                  '${dayLabel(archive[i].from)} to ${dayLabel(archive[i].to)}',
                            ),
                          )
                        : _openSaved(archive[i]),
                  ),
              ],

              _Heading(t('reports.statements')),
              if (statements.isEmpty)
                _Row(
                  icon: Icons.fact_check_outlined,
                  title: t('statement.entry.check'),
                  sub: t('statement.entry.checkSub'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StatementCheckPage(),
                    ),
                  ),
                )
              else
                for (final s in statements)
                  _Row(
                    icon: Icons.fact_check_outlined,
                    title: '${s.data.managerName} \u00b7 ${s.data.currency}',
                    sub: '${dayLabel(s.data.from)} to ${dayLabel(s.data.to)}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StatementDetailPage(saved: s),
                      ),
                    ),
                    trailing: _PdfButton(onTap: () => _statementPdf(s)),
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
                  _Row(
                    icon: Icons.receipt_long_outlined,
                    title: t('reports.taxTitle', {'year': '$y'}),
                    sub: t('reports.taxSub', {
                      'amount': taxes[y]!
                          .fold(0.0, (s, r) => s + r.tax)
                          .toStringAsFixed(2),
                      'n': '${taxes[y]!.length}',
                    }),
                    locked: !full,
                    onTap: () => _taxPdf(y, taxes[y]!),
                    trailing: _PdfButton(onTap: () => _taxPdf(y, taxes[y]!)),
                  ),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.locked = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool locked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: c.accentInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: c.faint,
                ),
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
  }
}

class _PdfButton extends StatelessWidget {
  const _PdfButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return IconButton(
      tooltip: t('reports.savePdf'),
      onPressed: onTap,
      icon: Icon(Icons.picture_as_pdf_outlined, size: 20, color: c.muted),
    );
  }
}

/// Portfolio's way into Reports.
class ReportsEntryRow extends StatelessWidget {
  const ReportsEntryRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                        t('reports.entrySub'),
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

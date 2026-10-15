import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/statements/statement_store.dart';
import '../alerts/alerts_page.dart';
import '../reports/reports_page.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../wrap/wrap_viewer.dart';
import 'pro_widgets.dart';
import 'switch_page.dart';

/// One place for everything Pro: this week's wrap, the checks on the user's
/// own money (statements, smart alerts, reports) and the tools.
class ProHomePage extends ConsumerWidget {
  const ProHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final latest = statements.isEmpty ? null : statements.first;
    final gap = latest == null
        ? null
        : ref
              .watch(statementAnalysisProvider(latest.id))
              .value
              ?.analysis
              .gapPts;
    final seen = ref.watch(alertsSeenProvider);
    final newSmart = ref
        .watch(smartAlertsProvider)
        .where((a) => a.at.isAfter(seen))
        .length;
    final pro = ref.watch(proProvider);

    void go(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('proHome.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: ProBadge()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('proHome.heading'),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('proHome.sub'),
                  style: TextStyle(color: c.muted, fontSize: 13.5),
                ),
              ],
            ),
          ),
          const WeeklyWrapCard(),
          _Heading(t('proHome.checks')),
          _Row(
            icon: Icons.fact_check_outlined,
            tone: gap != null && gap <= -0.25 ? c.down : c.accentInk,
            title: t('proHome.statements'),
            sub: latest == null
                ? t('proHome.statementsNone')
                : '${latest.data.managerName} \u00b7 ${dayLabel(latest.data.to)}',
            value: gap == null
                ? null
                : '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)} pts',
            onTap: () => go(
              latest == null
                  ? const StatementCheckPage()
                  : const StatementHistoryPage(),
            ),
          ),
          _Row(
            icon: Icons.notifications_active_outlined,
            tone: c.accentInk,
            title: t('proHome.alerts'),
            sub: t('proHome.alertsSub'),
            value: newSmart == 0 ? null : t('proHome.new', {'n': '$newSmart'}),
            onTap: () => go(const AlertsPage()),
          ),
          _Row(
            icon: Icons.summarize_outlined,
            tone: c.accentInk,
            title: t('reports.title'),
            sub: t('reports.entrySub'),
            onTap: () => go(const ReportsPage()),
          ),
          _Heading(t('proHome.tools')),
          _Row(
            icon: Icons.swap_horiz_rounded,
            tone: c.up,
            title: t('switch.title'),
            sub: t('proHome.switchSub'),
            onTap: () => go(const SwitchPage()),
          ),
          if (pro.active)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                pro.expiresAt == null
                    ? t('proHome.planActive')
                    : t(pro.willRenew ? 'proHome.renews' : 'proHome.ends', {
                        'date': dayLabel(pro.expiresAt!),
                      }),
                style: TextStyle(color: c.faint, fontSize: 12),
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tone,
    required this.title,
    required this.sub,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String sub;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: c.isDark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 19, color: tone),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: fructaFonts.numeric(
                      color: tone,
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Portfolio's way into Pro home. Free users go through the paywall first.
class ProHomeEntryRow extends ConsumerWidget {
  const ProHomeEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final open = !ref.watch(proEnabledProvider) || ref.watch(isProProvider);
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
          onTap: () async {
            if (!open && !await ensurePro(context, ref, source: 'pro_home'))
              return;
            if (!context.mounted) return;
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProHomePage()));
          },
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
                    Icons.workspace_premium_outlined,
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
                        t('proHome.title'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('proHome.entrySub'),
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

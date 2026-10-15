import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';

import '../core/analytics.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/backup_service.dart';
import '../data/providers.dart';
import '../features/alerts/smart_alerts.dart';
import '../features/backup/backup_ui.dart';
import '../features/learn/learn_home_page.dart';
import '../features/markets/markets_page.dart';
import '../features/portfolio/portfolio_page.dart';
import '../features/settings/settings_page.dart';
import '../features/today/today_page.dart';
import 'deep_link.dart';

/// Page indices for [selectedTabProvider].
///
/// These are positions in the IndexedStack, NOT positions in the nav bar.
/// Markets, Portfolio and Settings keep the indices they always had (0, 1, 2),
/// so every existing jump (deep links, Portfolio's empty-state CTA) still lands
/// where it did. Today was appended as 3 and is drawn FIRST in the bar.
abstract final class AppTab {
  static const markets = 0;
  static const portfolio = 1;
  static const you = 2;
  static const today = 3;

  /// Left-to-right order in the nav bar.
  static const navOrder = [today, markets, portfolio, you];
}

/// Selected page index (see [AppTab]). Opens on Today.
final selectedTabProvider = StateProvider<int>((ref) => AppTab.today);

/// Four tabs: Today, Markets, Portfolio, You. Add-holding lives in the
/// Portfolio topbar; Compare is a mode inside Markets.
///
/// Stateful so it can, once mounted: (1) offer to restore a cloud backup when
/// this device is empty, then prompt for a store update (Android); (2) auto-
/// back-up the portfolio, debounced, on every change; and (3) replay a
/// notification tap that cold-started the app.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  // Indexed by AppTab, not by nav position.
  static const _pages = [
    MarketsPage(),
    PortfolioPage(),
    SettingsPage(),
    TodayPage(),
  ];

  Timer? _backupDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      drainPendingTarget(); // replay a cold-start notification tap, if any
      await runLaunchTasks(context, ref);
      if (mounted) _maybeOpenLearn();
    });
  }

  /// A completely-new user (chose "I'm new to this" at onboarding) is taken
  /// straight into Learn the first time they land, once, then never again.
  /// A pending notification tap or a restore prompt takes precedence above.
  void _maybeOpenLearn() {
    final box = Hive.box('settings');
    final persona = box.get('onboarding_persona', defaultValue: 'rates');
    final shown = box.get('learn_intro_shown', defaultValue: false) as bool;
    if (persona == 'learn' && !shown) {
      box.put('learn_intro_shown', true);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LearnHomePage()));
    }
  }

  @override
  void dispose() {
    _backupDebounce?.cancel();
    super.dispose();
  }

  void _scheduleBackup() {
    _backupDebounce?.cancel();
    _backupDebounce = Timer(const Duration(seconds: 3), () async {
      try {
        final at = await ref.read(backupServiceProvider).backup();
        if (mounted) ref.read(lastBackupProvider.notifier).state = at;
      } catch (_) {
        /* offline / transient, the next change retries */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final index = ref.watch(selectedTabProvider);
    // Keeps the smart-alert engine alive for the app's lifetime; it listens to
    // rates and statements and raises alerts itself.
    ref.watch(smartAlertsRunnerProvider);

    // Auto-backup on any portfolio change (debounced). Empty books aren't
    // backed up, so a fresh user never creates a code for nothing.
    ref.listen(holdingsProvider, (prev, next) {
      if (next.isNotEmpty) _scheduleBackup();
    });

    // Android back: step home before leaving. From any tab other than Today,
    // back returns to Today; only from Today does the OS close the app.
    // Without this the scaffold puts nothing on the route stack, so back would
    // exit the app from every tab. Pushed routes (fund pages, alerts, add
    // holding) sit above this scaffold and pop on their own first.
    return PopScope(
      canPop: index == AppTab.today,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(selectedTabProvider.notifier).state = AppTab.today;
      },
      child: Scaffold(
        backgroundColor: c.bg,
        extendBody: true,
        // Hidden tabs stay alive (IndexedStack) but are frozen: their tickers
        // stop and they leave the semantics tree. Without this, Today's
        // ticker and bubble kept animating behind Markets or Portfolio, laying
        // out a subtree the accessibility pass was reading, which tripped
        // Flutter's '_needsLayout' semantics assertion. Also saves battery.
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _pages.length; i++)
              TickerMode(
                enabled: i == index,
                child: ExcludeSemantics(
                  excluding: i != index,
                  child: _pages[i],
                ),
              ),
          ],
        ),
        bottomNavigationBar: _NavBar(
          index: index,
          onTap: (i) {
            // IndexedStack means no route is pushed, so the navigator observer
            // never sees a tab change. Without this line Portfolio and Settings
            // are invisible in analytics no matter how often they are opened.
            if (i != index) Analytics.selectTab(_items[i].analytics);
            ref.read(selectedTabProvider.notifier).state = i;
          },
        ),
      ),
    );
  }
}

/// One nav destination. Active and inactive share one glyph family so a tab
/// never changes shape when selected, only weight and colour.
class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.labelKey, this.analytics);
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;

  /// Stable analytics name, independent of the display language.
  final String analytics;
}

/// Indexed by AppTab.
const _items = <_NavItem>[
  _NavItem(
    Icons.show_chart_rounded,
    Icons.show_chart_rounded,
    'nav.markets',
    'Markets',
  ),
  _NavItem(
    Icons.pie_chart_outline,
    Icons.pie_chart,
    'nav.portfolio',
    'Portfolio',
  ),
  _NavItem(
    Icons.person_outline_rounded,
    Icons.person_rounded,
    'nav.you',
    'You',
  ),
  _NavItem(
    Icons.wb_sunny_outlined,
    Icons.wb_sunny_rounded,
    'nav.today',
    'Today',
  ),
];

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + bottomInset,
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: c.bg.withValues(alpha: 0.84),
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              for (final i in AppTab.navOrder)
                Expanded(
                  child: _NavCell(
                    item: _items[i],
                    selected: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = selected ? c.accentInk : c.muted;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.bg.withValues(alpha: 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.activeIcon : item.icon, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            t(item.labelKey),
            style: TextStyle(
              fontSize: 11,
              height: 1,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

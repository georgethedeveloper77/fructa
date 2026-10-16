import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/pro/pro_service.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../statements/statement_controller.dart';

/// One Pro feature: a short label, one sentence revealed on tap.
///
/// Only features that ship in this build belong here. Both stores reject
/// paywalls that sell what the app does not have.
typedef _Feature = ({IconData icon, String label, String more});

List<_Feature> _features() => [
  (
    icon: Icons.fact_check_outlined,
    label: t('pw.f.statement'),
    more: t('pw.f.statementMore'),
  ),
  (
    icon: Icons.notifications_active_outlined,
    label: t('pw.f.alerts'),
    more: t('pw.f.alertsMore'),
  ),
  (
    icon: Icons.swap_horiz_rounded,
    label: t('pw.f.switch'),
    more: t('pw.f.switchMore'),
  ),
  (
    icon: Icons.flag_outlined,
    label: t('pw.f.goals'),
    more: t('pw.f.goalsMore'),
  ),
  (
    icon: Icons.health_and_safety_outlined,
    label: t('pw.f.watch'),
    more: t('pw.f.watchMore'),
  ),
  (
    icon: Icons.auto_stories_outlined,
    label: t('pw.f.wraps'),
    more: t('pw.f.wrapsMore'),
  ),
  (
    icon: Icons.receipt_long_outlined,
    label: t('pw.f.tax'),
    more: t('pw.f.taxMore'),
  ),
  (
    icon: Icons.show_chart_rounded,
    label: t('pw.f.history'),
    more: t('pw.f.historyMore'),
  ),
];

/// The Pro paywall.
///
/// Short by design: one headline (the user's own statement gap when they have
/// one, a plain promise otherwise), eight one-line features that reveal a
/// sentence on tap, two plans and one button. The price, period and automatic
/// renewal stay visible in one line under the button, as both stores require;
/// the full renewal terms are one tap away.
class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key, required this.source});

  /// Analytics label for the surface that opened the paywall.
  final String source;

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  PackageType _selected = PackageType.annual;
  bool _buying = false;
  bool _restoring = false;
  int _open = -1;
  bool _legal = false;

  bool get _busy => _buying || _restoring;

  @override
  void initState() {
    super.initState();
    Analytics.paywallView(widget.source);
  }

  /// Annual first (the anchor), then monthly; whatever the offering carries
  /// when neither standard type is set.
  List<Package> _plans(Offering o) {
    final out = [?o.annual, ?o.monthly];
    return out.isNotEmpty ? out : o.availablePackages;
  }

  Package? _selectedIn(List<Package> plans) {
    for (final p in plans) {
      if (p.packageType == _selected) return p;
    }
    return plans.isEmpty ? null : plans.first;
  }

  void _toast(ScaffoldMessengerState m, String msg) {
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buy(Package p) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final plan = p.packageType.name;
    setState(() => _buying = true);
    Analytics.purchaseStart(plan: plan, source: widget.source);

    final outcome = await ref.read(proProvider.notifier).purchase(p);
    Analytics.purchaseResult(plan: plan, outcome: outcome.name);
    if (!mounted) return;
    setState(() => _buying = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        _toast(messenger, t('pw.welcome'));
        Navigator.of(context).pop(true);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.pending:
        _toast(messenger, t('pw.pending'));
      case PurchaseOutcome.alreadyOwned:
        await _restore();
      case PurchaseOutcome.offline:
        _toast(messenger, t('pw.offline'));
      case PurchaseOutcome.failed:
        _toast(messenger, t('pw.failed'));
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _restoring = true);

    final outcome = await ref.read(proProvider.notifier).restore();
    Analytics.restorePurchases(outcome: outcome.name);
    if (!mounted) return;
    setState(() => _restoring = false);

    switch (outcome) {
      case PurchaseOutcome.success:
        _toast(messenger, t('pw.restored'));
        Navigator.of(context).pop(true);
      case PurchaseOutcome.offline:
        _toast(messenger, t('pw.offline'));
      default:
        _toast(messenger, t('pw.noneFound'));
    }
  }

  Future<void> _link(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[fructa] paywall link failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final offering = ref.watch(proOfferingProvider);
    final cfg = ref.watch(remoteConfigProvider);

    // A pending payment that clears while the paywall is open, or a purchase
    // restored elsewhere, lands here.
    ref.listen(isProProvider, (was, now) {
      if (now && !(was ?? false) && !_busy && mounted) {
        Navigator.of(context).pop(true);
      }
    });

    // The personal headline: the user's latest statement gap, when it shows
    // their fund paid meaningfully less than it published.
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final gap = statements.isEmpty
        ? null
        : ref
              .watch(statementAnalysisProvider(statements.first.id))
              .value
              ?.analysis
              .gapPts;
    final personal = gap != null && gap <= -0.25;

    final plans = switch (offering) {
      AsyncData(:final value) when value != null => _plans(value),
      _ => const <Package>[],
    };
    final chosen = _selectedIn(plans);
    final trial = chosen == null ? null : _trialLabel(chosen.storeProduct);
    final saving = _annualSaving(plans);
    final features = _features();
    final glow = personal ? c.down : c.accent;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.1),
                  radius: 1.1,
                  colors: [
                    glow.withValues(alpha: c.isDark ? 0.22 : 0.16),
                    c.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: t('common.close'),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: Icon(Icons.close_rounded, color: c.text),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : _restore,
                        style: TextButton.styleFrom(
                          foregroundColor: c.accentInk,
                        ),
                        child: _restoring
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.accentInk,
                                ),
                              )
                            : Text(
                                t('pw.restore'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t('pw.badge'),
                            style: TextStyle(
                              color: c.onAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (personal) ...[
                        Text(
                          gap.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: fructaFonts.numeric(
                            color: c.down,
                            size: 54,
                            weight: FontWeight.w600,
                            letterSpacing: -2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('pw.personal'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 19,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else
                        Text(
                          t('pw.generic'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Material(
                        color: c.s1,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: c.line),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < features.length; i++)
                              _FeatureRow(
                                feature: features[i],
                                open: _open == i,
                                last: i == features.length - 1,
                                onTap: () =>
                                    setState(() => _open = _open == i ? -1 : i),
                              ),
                          ],
                        ),
                      ),
                      if (_legal) ...[
                        const SizedBox(height: 14),
                        Text(
                          _legalText(trial != null),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.faint,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _Bottom(
                  offering: offering,
                  plans: plans,
                  chosen: chosen,
                  saving: saving,
                  busy: _buying,
                  enabled: !_busy,
                  trial: trial,
                  onSelect: (p) => setState(() => _selected = p.packageType),
                  onRetry: () => ref.invalidate(proOfferingProvider),
                  onBuy: chosen == null || _busy ? null : () => _buy(chosen),
                  onDetails: () => setState(() => _legal = !_legal),
                  onTerms: () => _link(
                    cfg.string(
                      'legal.terms_url',
                      'https://fructa.africa/terms',
                    ),
                  ),
                  onPrivacy: () => _link(
                    cfg.string(
                      'legal.privacy_url',
                      'https://fructa.africa/privacy',
                    ),
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

String _legalText(bool trial) {
  final account = defaultTargetPlatform == TargetPlatform.iOS
      ? 'Apple ID'
      : 'Google Play account';
  return '${trial ? 'After the free trial, payment' : 'Payment'} is charged to your $account. '
      'The subscription renews automatically unless cancelled at least 24 hours before the end '
      'of the current period. Manage or cancel anytime in your $account settings.';
}

// ── Plan helpers ─────────────────────────────────────────────────────────────

String _unitWord(PeriodUnit u) => switch (u) {
  PeriodUnit.day => 'day',
  PeriodUnit.week => 'week',
  PeriodUnit.month => 'month',
  PeriodUnit.year => 'year',
  PeriodUnit.unknown => 'day',
};

/// "7-day free trial" when the product carries a free phase, else null.
/// Google reports trials as a free pricing phase; Apple as a zero-priced
/// introductory price. Both are checked.
String? _trialLabel(StoreProduct p) {
  final free = p.defaultOption?.freePhase?.billingPeriod;
  if (free != null) return '${free.value}-${_unitWord(free.unit)} free trial';
  final intro = p.introductoryPrice;
  if (intro != null && intro.price == 0) {
    return '${intro.periodNumberOfUnits}-${_unitWord(intro.periodUnit)} free trial';
  }
  return null;
}

/// Whole-percent saving of annual over twelve monthly payments.
int? _annualSaving(List<Package> plans) {
  StoreProduct? m, a;
  for (final p in plans) {
    if (p.packageType == PackageType.monthly) m = p.storeProduct;
    if (p.packageType == PackageType.annual) a = p.storeProduct;
  }
  if (m == null ||
      a == null ||
      m.currencyCode != a.currencyCode ||
      m.price <= 0) {
    return null;
  }
  final pct = ((1 - a.price / (m.price * 12)) * 100).round();
  return pct >= 5 ? pct : null;
}

String _period(Package p) => switch (p.packageType) {
  PackageType.annual => t('pw.year'),
  PackageType.monthly => t('pw.month'),
  _ => p.storeProduct.title,
};

String _planName(Package p) => switch (p.packageType) {
  PackageType.annual => t('pw.annual'),
  PackageType.monthly => t('pw.monthly'),
  _ => p.storeProduct.title,
};

// ── Pieces ───────────────────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.feature,
    required this.open,
    required this.last,
    required this.onTap,
  });

  final _Feature feature;
  final bool open;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(feature.icon, size: 16, color: c.accentInk),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature.label,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: c.faint,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (open)
                Padding(
                  padding: const EdgeInsets.only(left: 42, top: 6),
                  child: Text(
                    feature.more,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.offering,
    required this.plans,
    required this.chosen,
    required this.saving,
    required this.busy,
    required this.enabled,
    required this.trial,
    required this.onSelect,
    required this.onRetry,
    required this.onBuy,
    required this.onDetails,
    required this.onTerms,
    required this.onPrivacy,
  });

  final AsyncValue<Offering?> offering;
  final List<Package> plans;
  final Package? chosen;
  final int? saving;
  final bool busy;
  final bool enabled;
  final String? trial;
  final ValueChanged<Package> onSelect;
  final VoidCallback onRetry;
  final VoidCallback? onBuy;
  final VoidCallback onDetails;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = chosen;
    final renew = p == null
        ? ''
        : t('pw.renews', {
            'price': p.storeProduct.priceString,
            'period': _period(p),
          });

    Widget link(String label, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            color: c.faint,
            fontSize: 11,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (offering) {
            AsyncLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            ),
            AsyncData() when plans.isNotEmpty => Row(
              children: [
                for (var i = 0; i < plans.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PlanCard(
                      package: plans[i],
                      selected: plans[i] == p,
                      badge:
                          plans[i].packageType == PackageType.annual &&
                              saving != null
                          ? t('pw.save', {'pct': '$saving'})
                          : null,
                      onTap: enabled ? () => onSelect(plans[i]) : null,
                    ),
                  ),
                ],
              ],
            ),
            _ => Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: c.muted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('pw.unavailable'),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
                TextButton(onPressed: onRetry, child: Text(t('pw.retry'))),
              ],
            ),
          },
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onBuy,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                disabledBackgroundColor: c.s3,
                disabledForegroundColor: c.faint,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: c.onAccent,
                      ),
                    )
                  : Text(
                      trial != null
                          ? t('pw.startTrial', {'trial': trial!})
                          : (p?.packageType == PackageType.monthly
                                ? t('pw.startMonthly')
                                : t('pw.start')),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              if (renew.isNotEmpty)
                Text(renew, style: TextStyle(color: c.faint, fontSize: 11)),
              link(t('pw.details'), onDetails),
              link(t('pw.terms'), onTerms),
              link(t('pw.privacy'), onPrivacy),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final Package package;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? c.accent : c.line, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _planName(package),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                    if (badge != null)
                      TextSpan(
                        text: '  $badge',
                        style: TextStyle(
                          color: c.accentInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                package.storeProduct.priceString,
                style: fructaFonts.numeric(
                  color: c.text,
                  size: 18,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

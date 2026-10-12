import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/theme.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/pro/pro_service.dart';
import '../../data/snapshot_providers.dart';
import 'pro_widgets.dart';

/// One benefit line on the paywall.
typedef _Benefit = ({IconData icon, String title, String sub});

/// Benefits listed on the paywall.
///
/// Only features that ship in the build carrying this paywall belong here.
/// Both stores reject paywalls that sell features the app does not have, and a
/// subscriber who pays for a missing feature asks for a refund. Append smart
/// alerts and the switch analyzer when they land.
const List<_Benefit> _benefits = [
  (
    icon: Icons.lock_open_outlined,
    title: 'Statement import',
    sub: 'Unlocks and reads your password-protected fund statements',
  ),
  (
    icon: Icons.insights_outlined,
    title: 'Credited vs published yield',
    sub: 'Check the rate you were paid against the rate advertised',
  ),
  (
    icon: Icons.receipt_long_outlined,
    title: 'Tax and annual reports',
    sub: 'Withholding tax per year, and a PDF of your year',
  ),
  (
    icon: Icons.shield_outlined,
    title: 'Private by design',
    sub: 'Statements are read on your phone and never uploaded',
  ),
];

/// Fructa Pro paywall.
///
/// Plans, prices and trial lengths all come from the store through the
/// RevenueCat offering, so they are always in the user's currency and always
/// match what the store sheet will charge. Nothing price-related is hardcoded.
///
/// Pops `true` when the user leaves with Pro active.
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

  bool get _busy => _buying || _restoring;

  @override
  void initState() {
    super.initState();
    Analytics.paywallView(widget.source);
  }

  /// Plans in display order: annual first (the anchor), then monthly. Falls
  /// back to whatever the offering carries if neither standard type is set.
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
    final c = context.c;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
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
        _toast(messenger, 'Welcome to Fructa Pro.');
        Navigator.of(context).pop(true);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.pending:
        _toast(
          messenger,
          'Payment pending. Pro unlocks as soon as the store confirms it.',
        );
      case PurchaseOutcome.alreadyOwned:
        await _restore();
      case PurchaseOutcome.offline:
        _toast(messenger, 'You appear to be offline. Connect and try again.');
      case PurchaseOutcome.failed:
        _toast(
          messenger,
          'The store could not complete the purchase. Please try again.',
        );
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
        _toast(messenger, 'Fructa Pro restored.');
        Navigator.of(context).pop(true);
      case PurchaseOutcome.offline:
        _toast(messenger, 'You appear to be offline. Connect and try again.');
      default:
        _toast(
          messenger,
          'No active Fructa Pro subscription was found on this store account.',
        );
    }
  }

  Future<void> _open(String url) async {
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
    // restored on another device, lands here through the listener.
    ref.listen(isProProvider, (was, now) {
      if (now && !(was ?? false) && !_busy && mounted) {
        Navigator.of(context).pop(true);
      }
    });

    final plans = switch (offering) {
      AsyncData(:final value) when value != null => _plans(value),
      _ => const <Package>[],
    };
    final chosen = _selectedIn(plans);
    final trial = chosen == null ? null : _trialLabel(chosen.storeProduct);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              restoring: _restoring,
              onClose: _busy ? null : () => Navigator.of(context).pop(false),
              onRestore: _busy ? null : _restore,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  const _Hero(),
                  const SizedBox(height: 22),
                  for (final b in _benefits) _BenefitRow(benefit: b),
                  const SizedBox(height: 14),
                  switch (offering) {
                    AsyncLoading() => const _PlansLoading(),
                    AsyncData() when plans.isNotEmpty => _PlanList(
                      plans: plans,
                      selected: chosen,
                      enabled: !_busy,
                      onSelect: (p) =>
                          setState(() => _selected = p.packageType),
                    ),
                    _ => _PlansUnavailable(
                      onRetry: () => ref.invalidate(proOfferingProvider),
                    ),
                  },
                ],
              ),
            ),
            _BottomBar(
              label: trial != null
                  ? 'Start $trial'
                  : 'Continue with ${chosen == null ? 'Pro' : _planName(chosen)}',
              busy: _buying,
              onTap: chosen == null || _busy ? null : () => _buy(chosen),
              trial: trial != null,
              onTerms: () => _open(
                cfg.string('legal.terms_url', 'https://fructa.africa/terms'),
              ),
              onPrivacy: () => _open(
                cfg.string(
                  'legal.privacy_url',
                  'https://fructa.africa/privacy',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan helpers ─────────────────────────────────────────────────────────────

String _planName(Package p) => switch (p.packageType) {
  PackageType.annual => 'Annual',
  PackageType.monthly => 'Monthly',
  PackageType.sixMonth => '6 months',
  PackageType.threeMonth => '3 months',
  PackageType.weekly => 'Weekly',
  PackageType.lifetime => 'Lifetime',
  _ => p.storeProduct.title,
};

String _unitWord(PeriodUnit u) => switch (u) {
  PeriodUnit.day => 'day',
  PeriodUnit.week => 'week',
  PeriodUnit.month => 'month',
  PeriodUnit.year => 'year',
  PeriodUnit.unknown => 'day',
};

/// "7-day free trial" when the product carries a free phase, else null.
///
/// Google reports trials as a free pricing phase on the default subscription
/// option; Apple reports them as a zero-priced introductory price. Both are
/// checked so the label is right on either store.
String? _trialLabel(StoreProduct p) {
  final free = p.defaultOption?.freePhase?.billingPeriod;
  if (free != null) return '${free.value}-${_unitWord(free.unit)} free trial';
  final intro = p.introductoryPrice;
  if (intro != null && intro.price == 0) {
    return '${intro.periodNumberOfUnits}-${_unitWord(intro.periodUnit)} '
        'free trial';
  }
  return null;
}

/// Whole-percent saving of annual over twelve monthly payments, or null when
/// the two cannot be compared or the saving is too small to be worth saying.
int? _annualSaving(List<Package> plans) {
  StoreProduct? m, a;
  for (final p in plans) {
    if (p.packageType == PackageType.monthly) m = p.storeProduct;
    if (p.packageType == PackageType.annual) a = p.storeProduct;
  }
  if (m == null || a == null || m.currencyCode != a.currencyCode) return null;
  if (m.price <= 0) return null;
  final pct = ((1 - a.price / (m.price * 12)) * 100).round();
  return pct >= 5 ? pct : null;
}

String _planSub(Package p) => switch (p.packageType) {
  PackageType.annual =>
    p.storeProduct.pricePerMonthString != null
        ? '${p.storeProduct.pricePerMonthString} a month, billed yearly'
        : 'Billed yearly',
  PackageType.monthly => 'Billed monthly, cancel anytime',
  _ => p.storeProduct.description,
};

// ── Pieces ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.restoring,
    required this.onClose,
    required this.onRestore,
  });

  final bool restoring;
  final VoidCallback? onClose;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(Icons.close, color: c.muted),
          ),
          const Spacer(),
          TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(foregroundColor: c.accentInk),
            child: restoring
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accentInk,
                    ),
                  )
                : const Text(
                    'Restore purchases',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        Positioned(
          right: -8,
          top: 0,
          child: CustomPaint(
            size: const Size(150, 86),
            painter: _SparkPainter(color: c.accent.withValues(alpha: 0.35)),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ProBadge(label: 'FRUCTA PRO'),
            const SizedBox(height: 14),
            Text(
              'Know what your money actually earned.',
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Read your fund statements, see real returns after tax, and '
              'check every rate you were paid.',
              style: TextStyle(color: c.muted, fontSize: 14.5, height: 1.5),
            ),
          ],
        ),
      ],
    );
  }
}

/// A quiet rising line behind the headline, drawn in the accent so it follows
/// the user's accent choice. Decorative only.
class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.color});

  final Color color;

  // Normalised points, left to right, 0 at the top.
  static const _pts = [
    Offset(0, 0.86),
    Offset(0.16, 0.78),
    Offset(0.32, 0.82),
    Offset(0.48, 0.6),
    Offset(0.64, 0.64),
    Offset(0.8, 0.34),
    Offset(1, 0.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final p = Offset(_pts[i].dx * size.width, _pts[i].dy * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color;
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});

  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(benefit.icon, size: 19, color: c.accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  benefit.title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  benefit.sub,
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList({
    required this.plans,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final List<Package> plans;
  final Package? selected;
  final bool enabled;
  final ValueChanged<Package> onSelect;

  @override
  Widget build(BuildContext context) {
    final saving = _annualSaving(plans);
    return Column(
      children: [
        for (final p in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanCard(
              package: p,
              selected: identical(p, selected),
              badge: p.packageType == PackageType.annual && saving != null
                  ? 'SAVE $saving%'
                  : null,
              onTap: enabled ? () => onSelect(p) : null,
            ),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final Package package;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final trial = _trialLabel(package.storeProduct);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.accentSoft : c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? c.accent : c.line2,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            child: Row(
              children: [
                _RadioDot(on: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _planName(package),
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badge != null) ProBadge(label: badge!),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        trial != null
                            ? '$trial, then ${_planSub(package).toLowerCase()}'
                            : _planSub(package),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  package.storeProduct.priceString,
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on ? c.accent : c.line2, width: 2),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: on ? 10 : 0,
        height: on ? 10 : 0,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
      ),
    );
  }
}

class _PlansLoading extends StatelessWidget {
  const _PlansLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        for (var i = 0; i < 2; i++)
          Container(
            height: 70,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
          ),
      ],
    );
  }
}

class _PlansUnavailable extends StatelessWidget {
  const _PlansUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: c.muted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Plans could not load. Check your connection and try again.',
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.45),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: c.accentInk),
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.label,
    required this.busy,
    required this.onTap,
    required this.trial,
    required this.onTerms,
    required this.onPrivacy,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;
  final bool trial;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final account = ios ? 'Apple ID' : 'Google Play account';
    final legal =
        '${trial ? 'After the free trial, payment' : 'Payment'} is charged to '
        'your $account. The subscription renews automatically unless cancelled '
        'at least 24 hours before the end of the current period. Manage or '
        'cancel anytime in your $account settings.';

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                disabledBackgroundColor: c.s3,
                disabledForegroundColor: c.faint,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            legal,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.5),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onTerms,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text(
                  'Terms of Use',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Text('\u00b7', style: TextStyle(color: c.faint)),
              TextButton(
                onPressed: onPrivacy,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text(
                  'Privacy Policy',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurance_type.dart';
import '../../data/models/insurer.dart';
import '../../data/models/remote_config.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_motor_page.dart';
import 'insure_travel_page.dart';
import 'insurer_detail_page.dart';
import 'insurer_directory_page.dart';

/// Insurance home. Full page pushed from the Markets spotlight (class name kept
/// as InsureOverlay so the existing entry in markets_page is unchanged).
///
/// Apple 2.1: no coming-soon / teaser content. A category appears ONLY when it
/// has a live comparison flow with real data behind it. Admin can add types
/// (Life, Medical, ...) but they stay invisible here until a flow ships, so the
/// screen never advertises something a user can't use.
class InsureOverlay extends ConsumerWidget {
  const InsureOverlay({super.key});

  // Only motor and travel have flows today, and only when data exists.
  bool _runnable(InsuranceType type, List<Insurer> insurers) {
    if (!type.isLive) return false;
    return switch (type.key) {
      'motor' => insurers.any((i) => i.hasMotor),
      'travel' => insurers.any((i) => i.hasTravel),
      _ => false,
    };
  }

  String _desc(InsuranceType type, List<Insurer> insurers) {
    if (type.key == 'motor') {
      final motor = insurers.where((i) => i.hasMotor).toList();
      double? minRate;
      for (final i in motor) {
        final r = i.motorRate;
        if (r != null && (minRate == null || r < minRate)) minRate = r;
      }
      final rate = minRate == null ? '' : minRate.toStringAsFixed(2);
      return motor.length == 1
          ? t('insure.motorGridOne', {'rate': rate})
          : t('insure.motorGrid', {'n': '${motor.length}', 'rate': rate});
    }
    if (type.key == 'travel') {
      num? from;
      for (final i in insurers) {
        final f = i.travelFrom;
        if (f != null && (from == null || f < from)) from = f;
      }
      return from == null ? '' : t('insure.travelGrid', {'amt': kes(from)});
    }
    return type.sub ?? '';
  }

  List<String> _bullets(RemoteConfig rc) => rcBullets(
        rc,
        'insure.why_bullets',
        [
          t('insure.why.1'),
          t('insure.why.2'),
          t('insure.why.3'),
          t('insure.why.4'),
        ],
      );

  void _open(BuildContext context, InsuranceType type) {
    if (type.key == 'motor') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const InsureMotorPage()));
    } else if (type.key == 'travel') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const InsureTravelPage()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rc = ref.watch(remoteConfigProvider);
    final insurers = ref.watch(insurersProvider);
    final types = ref
        .watch(insuranceTypesProvider)
        .where((tp) => _runnable(tp, insurers))
        .toList();
    final n = insurers.where((i) => i.hasMotor || i.hasTravel).length;
    final liveWord = n == 1
        ? t('insure.insurerLiveOne')
        : t('insure.insurersLive', {'n': '$n'});

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          DisplayHeader(
            title: t('insure.title'),
            sub: n > 0
                ? '${rcText(rc, 'insure.homeSub')} \u00b7 $liveWord'
                : rcText(rc, 'insure.homeSub'),
          ),
          const SizedBox(height: 12),
          if (types.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(t('insure.emptyHome'),
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.5)),
            )
          else
            Column(
              children: [
                for (var i = 0; i < types.length; i++)
                  _CategoryRow(
                    icon: insureTypeIcon(types[i].icon),
                    lottieUrl: types[i].lottieUrl,
                    lottieAsset: 'assets/lottie/${types[i].key}.json',
                    title: types[i].label,
                    desc: _desc(types[i], insurers),
                    last: i == types.length - 1,
                    onTap: () => _open(context, types[i]),
                  ),
              ],
            ),
          // Every licensed insurer, not just the priced ones. This is where the
          // IRA register surfaces: regulatory standing for the whole market.
          if (insurers.length > types.length)
            _DirectoryRow(
              count: insurers.length,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const InsurerDirectoryPage()),
              ),
            ),
          Disclaimer(rcText(rc, 'insure.disc.home')),
          _TrustedStrip(insurers: insurers),
          InsureH2(rcText(rc, 'insure.why.title'),
              small: rcText(rc, 'insure.why.sub')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (var i = 0; i < _bullets(rc).length; i++)
                  _WhyRow(_bullets(rc)[i],
                      tint: i.isEven ? c.accent : c.up,
                      last: i == _bullets(rc).length - 1),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(rcText(rc, 'insure.privacyNote'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9.5,
                    fontFamily: fructaFonts.mono)),
          ),
        ],
      ),
    );
  }
}

/// A category launcher row: accent icon tile + title/description + chevron.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
    this.lottieUrl,
    this.lottieAsset,
    this.last = false,
  });

  final IconData icon;
  final String? lottieUrl;
  final String? lottieAsset;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border:
              last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: TypeIcon(
                  icon: icon,
                  lottieUrl: lottieUrl,
                  lottieAsset: lottieAsset,
                  color: c.accent,
                  size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(desc,
                        style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }
}

/// Trusted-insurers deck: a horizontal row of tappable cards. Each card shows
/// the insurer, what it offers (Motor / Travel), and opens that insurer. When an
/// insurer offers both, a small sheet lets the user pick which cover to compare.
class _TrustedStrip extends StatelessWidget {
  const _TrustedStrip({required this.insurers});
  final List<Insurer> insurers;

  static const double _motorValue = 3450000;

  void _openMotor(BuildContext context, Insurer i) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InsurerDetailPage.motor(i, value: _motorValue),
      ));

  void _openTravel(BuildContext context, Insurer i) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            InsurerDetailPage.travel(i, region: 'af', days: 7, pax: 1),
      ));

  void _open(BuildContext context, Insurer i) {
    final motor = i.hasMotor;
    final travel = i.hasTravel;
    if (motor && travel) {
      _pickCover(context, i);
    } else if (motor) {
      _openMotor(context, i);
    } else if (travel) {
      _openTravel(context, i);
    }
  }

  void _pickCover(BuildContext context, Insurer i) {
    final c = context.c;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.s1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Text(i.name,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            _CoverPick(
              icon: Icons.directions_car_outlined,
              label: t('insure.motor'),
              onTap: () {
                Navigator.of(sheet).pop();
                _openMotor(context, i);
              },
            ),
            _CoverPick(
              icon: Icons.flight_outlined,
              label: t('insure.travel'),
              onTap: () {
                Navigator.of(sheet).pop();
                _openTravel(context, i);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shown = insurers.where((i) => i.hasMotor || i.hasTravel).toList();
    if (shown.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text(t('insure.trusted'),
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (_, i) => _InsurerCard(
                insurer: shown[i],
                onTap: () => _open(context, shown[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable insurer card in the trusted deck.
class _InsurerCard extends StatelessWidget {
  const _InsurerCard({required this.insurer, required this.onTap});
  final Insurer insurer;
  final VoidCallback onTap;

  // Trim only trailing corporate boilerplate so the name fits without ever
  // truncating the meaningful part (e.g. "... Company (K) Limited" -> dropped).
  static String _shortName(String n) {
    var s = n;
    for (final re in <RegExp>[
      RegExp(r'\s*Company\s*\(K\)\s*Limited$', caseSensitive: false),
      RegExp(r'\s*Company\s*Limited$', caseSensitive: false),
      RegExp(r'\s*\(K\)\s*Limited$', caseSensitive: false),
      RegExp(r'\s*\(Kenya\)\s*Limited$', caseSensitive: false),
      RegExp(r'\s*Limited$', caseSensitive: false),
      RegExp(r'\s*Company$', caseSensitive: false),
    ]) {
      s = s.replaceFirst(re, '');
    }
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    final offers = <String>[
      if (i.hasMotor) t('insure.motor'),
      if (i.hasTravel) t('insure.travel'),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FundLogo(
              domain: i.logoDomain,
              seed: i.name,
              size: 40,
              brandColor: insurerBrand(context, i),
            ),
            const SizedBox(height: 11),
            Text(_shortName(i.name),
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: TextStyle(
                    color: c.text,
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final o in offers)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(o,
                        style: TextStyle(
                            color: c.accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row in the "which cover?" sheet for insurers offering both.
class _CoverPick extends StatelessWidget {
  const _CoverPick(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c.accent, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, color: c.faint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _WhyRow extends StatelessWidget {
  const _WhyRow(this.text, {required this.tint, this.last = false});
  final String text;
  final Color tint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child:
                Text(text, style: TextStyle(color: c.muted, fontSize: 12.5)),
          ),
          Icon(Icons.check_rounded, size: 16, color: c.up),
        ],
      ),
    );
  }
}

/// Entry to the full insurer directory (the IRA register, in the app).
class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.s3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.verified_outlined, size: 20, color: c.text),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('insure.dir.title'),
                      style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(t('insure.dir.entry', {'n': '$count'}),
                      style: TextStyle(color: c.muted, fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }
}

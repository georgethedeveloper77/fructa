import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurer.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_motion.dart';
import 'insure_shell.dart';
import 'insurer_detail_page.dart';

enum TravelSort { cheapest, cover, claims }

extension TravelSortX on TravelSort {
  String get label => switch (this) {
    TravelSort.cheapest => t('insure.filter.cheapest'),
    TravelSort.cover => t('insure.filter.cover'),
    TravelSort.claims => t('insure.filter.claims'),
  };
}

class InsureTravelPage extends ConsumerStatefulWidget {
  const InsureTravelPage({super.key});

  @override
  ConsumerState<InsureTravelPage> createState() => _InsureTravelPageState();
}

class _InsureTravelPageState extends ConsumerState<InsureTravelPage> {
  String _region = 'af';
  int _days = 7;
  int _pax = 1;
  TravelSort _sort = TravelSort.cheapest;

  void _bumpDays(int d) {
    setState(() {
      final step = d > 0
          ? (_days >= 30
                ? 7
                : _days >= 14
                ? 3
                : 1)
          : (_days > 30
                ? -7
                : _days > 14
                ? -3
                : -1);
      _days = (_days + step).clamp(3, 90);
    });
  }

  void _bumpPax(int d) => setState(() => _pax = (_pax + d).clamp(1, 6));

  double _price(Insurer i) =>
      i.travelPrice(_region, days: _days, pax: _pax) ?? 0;

  List<Insurer> _sorted(List<Insurer> travel) {
    final list = travel.where((i) => _price(i) > 0).toList();
    int claims(Insurer i) => i.claimsDays ?? 1 << 30;
    switch (_sort) {
      case TravelSort.cheapest:
        list.sort((a, b) => _price(a).compareTo(_price(b)));
      case TravelSort.cover:
        list.sort(
          (a, b) => coverNum(b.travelCover).compareTo(coverNum(a.travelCover)),
        );
      case TravelSort.claims:
        list.sort((a, b) => claims(a).compareTo(claims(b)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rc = ref.watch(remoteConfigProvider);
    final travel = ref
        .watch(insurersProvider)
        .where((i) => i.hasTravel)
        .toList();

    if (travel.isEmpty) {
      return _shell([
        _head(0),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
          child: Text(
            t('insure.emptyTravel'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.6),
          ),
        ),
      ]);
    }

    final sorted = _sorted(travel);
    final best = sorted.isEmpty ? null : sorted.first;

    return _shell([
      _head(sorted.length),
      KpiStrip([
        KpiCell(
          label: t('insure.motor.kpiInsurers'),
          value: '${sorted.length}',
        ),
        KpiCell(
          label: t('insure.motor.kpiCheapest'),
          value: best == null ? '' : kesCompact(_price(best)),
          color: c.accent,
        ),
        KpiCell(
          label: t('insure.travel.kpiTrip'),
          value: t('insure.days', {'n': '$_days'}),
        ),
      ]),
      _TravelBox(
        region: _region,
        days: _days,
        pax: _pax,
        onRegion: (r) => setState(() => _region = r),
        onDays: _bumpDays,
        onPax: _bumpPax,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: SlidingSegments<TravelSort>(
          values: TravelSort.values,
          selected: _sort,
          labelOf: (s) => s.label,
          onTap: (s) => setState(() => _sort = s),
        ),
      ),
      for (var qi = 0; qi < sorted.length; qi++)
        Stagger(
          index: qi,
          child: _quoteRow(
            context,
            sorted[qi],
            best,
            sorted.isEmpty
                ? 0
                : _price(
                    sorted.reduce((a, b) => _price(a) >= _price(b) ? a : b),
                  ),
          ),
        ),
      _TravelFoot(sorted: sorted, region: _region, price: _price),
      Disclaimer(rcText(rc, 'insure.disc.travel')),
    ]);
  }

  /// Travel prices move with the region, the length of the trip and the number
  /// of travellers, so the count in the kicker is a live figure and the node
  /// pulses.
  Widget _head(int n) => InsureHead(
    kicker: t('insure.travel.kicker', {'n': '$n'}),
    title: t('insure.travel'),
    sub: t('insure.travel.sub'),
  );

  Widget _quoteRow(
    BuildContext context,
    Insurer i,
    Insurer? best,
    double dearest,
  ) => InsureQuoteRow(
    name: i.name,
    logoDomain: i.logoDomain,
    brand: insurerBrand(context, i),
    // Travel is priced per traveller per region, not as a percentage of
    // anything, so there is no rate mechanic to show. The cover ceiling is
    // the thing that separates these quotes.
    rateLabel: i.travelCover,
    meta: i.claimsDays == null
        ? null
        : t('insure.claimsDays', {'d': '${i.claimsDays}'}),
    priceText: withCommas(_price(i).round()),
    priceUnit: t('insure.paxDays', {
      'pax': _pax > 1 ? '$_pax \u00b7 ' : '',
      'days': '$_days',
    }),
    barFraction: dearest <= 0 ? null : _price(i) / dearest,
    best: best != null && i.id == best.id,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InsurerDetailPage.travel(
          i,
          region: _region,
          days: _days,
          pax: _pax,
        ),
      ),
    ),
  );

  Widget _shell(List<Widget> children) =>
      InsureScaffold(navTitle: t('insure.travel'), children: children);
}

class _TravelBox extends StatelessWidget {
  const _TravelBox({
    required this.region,
    required this.days,
    required this.pax,
    required this.onRegion,
    required this.onDays,
    required this.onPax,
  });

  final String region;
  final int days;
  final int pax;
  final ValueChanged<String> onRegion;
  final ValueChanged<int> onDays;
  final ValueChanged<int> onPax;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget regionPill(String key) {
      final on = key == region;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onRegion(key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? c.text : c.s1,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: on ? c.text : c.line),
            ),
            child: Text(
              regionLabel(key),
              style: TextStyle(
                color: on ? c.bg : c.muted,
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [for (final r in TravelRegions.keys) regionPill(r)],
            ),
          ),
          _Stepper(
            label: t('insure.tripLength'),
            value: t('insure.days', {'n': '$days'}),
            onMinus: () => onDays(-1),
            onPlus: () => onDays(1),
          ),
          _Stepper(
            label: t('insure.travellers'),
            value: pax == 1
                ? t('insure.adult', {'n': '$pax'})
                : t('insure.adults', {'n': '$pax'}),
            onMinus: () => onPax(-1),
            onPlus: () => onPax(1),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget btn(IconData icon, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.s3,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.line2),
        ),
        child: Icon(icon, size: 18, color: c.text),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 9,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          btn(Icons.remove, onMinus),
          const SizedBox(width: 7),
          btn(Icons.add, onPlus),
        ],
      ),
    );
  }
}

class _TravelFoot extends StatelessWidget {
  const _TravelFoot({
    required this.sorted,
    required this.region,
    required this.price,
  });
  final List<Insurer> sorted;
  final String region;
  final double Function(Insurer) price;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (sorted.isEmpty) return const SizedBox.shrink();
    final cheap = [...sorted]..sort((a, b) => price(a).compareTo(price(b)));
    final deep = [...sorted]
      ..sort(
        (a, b) => coverNum(b.travelCover).compareTo(coverNum(a.travelCover)),
      );
    final parts = <String>[
      if (region == 'sch') t('insure.schengenWarn'),
      t('insure.travelGapCheap', {
        'name': cheap.first.name,
        'amt': kes(price(cheap.first)),
      }),
      t('insure.travelGapDeep', {
        'name': deep.first.name,
        'cover': deep.first.travelCover ?? '',
      }),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        parts.join(' '),
        style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.5),
      ),
    );
  }
}

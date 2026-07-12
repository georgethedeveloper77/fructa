import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurer.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insurer_detail_page.dart';

enum TravelSort { cheapest, cover, claims }

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
          ? (_days >= 30 ? 7 : _days >= 14 ? 3 : 1)
          : (_days > 30 ? -7 : _days > 14 ? -3 : -1);
      _days = (_days + step).clamp(3, 90);
    });
  }

  void _bumpPax(int d) => setState(() => _pax = (_pax + d).clamp(1, 6));

  double _price(Insurer i) => i.travelPrice(_region, days: _days, pax: _pax) ?? 0;

  List<Insurer> _sorted(List<Insurer> travel) {
    final list = travel.where((i) => _price(i) > 0).toList();
    int claims(Insurer i) => i.claimsDays ?? 1 << 30;
    switch (_sort) {
      case TravelSort.cheapest:
        list.sort((a, b) => _price(a).compareTo(_price(b)));
      case TravelSort.cover:
        list.sort(
            (a, b) => coverNum(b.travelCover).compareTo(coverNum(a.travelCover)));
      case TravelSort.claims:
        list.sort((a, b) => claims(a).compareTo(claims(b)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rc = ref.watch(remoteConfigProvider);
    final travel =
        ref.watch(insurersProvider).where((i) => i.hasTravel).toList();

    if (travel.isEmpty) {
      return _shell(
        c,
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(t('insure.emptyTravel'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted)),
          ),
        ),
      );
    }

    final sorted = _sorted(travel);
    final best = sorted.isEmpty ? null : sorted.first;

    return _shell(
      c,
      ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          DisplayHeader(title: t('insure.travel'), sub: rcText(rc, 'insure.travelSub')),
          _TravelBox(
            region: _region,
            days: _days,
            pax: _pax,
            onRegion: (r) => setState(() => _region = r),
            onDays: _bumpDays,
            onPax: _bumpPax,
          ),
          _FilterPills(sort: _sort, onSort: (s) => setState(() => _sort = s)),
          const SizedBox(height: 4),
          for (final i in sorted)
            InsureQuoteRow(
              name: i.name,
              logoDomain: i.logoDomain,
              brand: insurerBrand(context, i),
              stars: i.rating,
              meta: [
                if (i.travelCover != null) i.travelCover!,
                if (i.claimsDays != null)
                  t('insure.claimsDays', {'d': '${i.claimsDays}'}),
              ].join('  \u00b7  '),
              benefits: i.benefits,
              priceText: kes(_price(i)),
              subText: t('insure.paxDays', {
                'pax': _pax > 1 ? '$_pax \u00b7 ' : '',
                'days': '$_days',
              }),
              best: best != null && i.id == best.id,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InsurerDetailPage.travel(
                  i,
                  region: _region,
                  days: _days,
                  pax: _pax,
                ),
              )),
            ),
          _TravelFoot(sorted: sorted, region: _region, price: _price),
          Disclaimer(rcText(rc, 'insure.disc.travel')),
        ],
      ),
    );
  }

  Widget _shell(fructaColors c, Widget body) => Scaffold(
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
        body: body,
      );
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
            child: Text(regionLabel(key),
                style: TextStyle(
                    color: on ? c.bg : c.muted,
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
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
            child: Row(children: [
              for (final r in TravelRegions.keys) regionPill(r),
            ]),
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
                Text(label,
                    style: TextStyle(
                        color: c.faint,
                        fontSize: 9,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        color: c.text,
                        fontFamily: fructaFonts.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.sort, required this.onSort});
  final TravelSort sort;
  final ValueChanged<TravelSort> onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget pill(TravelSort s, String label) {
      final on = s == sort;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSort(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            decoration: BoxDecoration(
              color: on ? c.text : c.s1,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: on ? c.text : c.line),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? c.bg : c.muted,
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          pill(TravelSort.cheapest, t('insure.filter.cheapest')),
          pill(TravelSort.cover, t('insure.filter.cover')),
          pill(TravelSort.claims, t('insure.filter.claims')),
        ]),
      ),
    );
  }
}

class _TravelFoot extends StatelessWidget {
  const _TravelFoot(
      {required this.sorted, required this.region, required this.price});
  final List<Insurer> sorted;
  final String region;
  final double Function(Insurer) price;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (sorted.isEmpty) return const SizedBox.shrink();
    final cheap = [...sorted]..sort((a, b) => price(a).compareTo(price(b)));
    final deep = [...sorted]..sort(
        (a, b) => coverNum(b.travelCover).compareTo(coverNum(a.travelCover)));
    final parts = <String>[
      if (region == 'sch') t('insure.schengenWarn'),
      t('insure.travelGapCheap',
          {'name': cheap.first.name, 'amt': kes(price(cheap.first))}),
      t('insure.travelGapDeep', {
        'name': deep.first.name,
        'cover': deep.first.travelCover ?? '',
      }),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(parts.join(' '),
          style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.5)),
    );
  }
}

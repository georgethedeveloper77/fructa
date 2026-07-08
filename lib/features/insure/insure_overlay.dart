import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurer.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

enum InsureSort { cheapest, benefits, value }

enum InsureMode { motor, travel }

class InsureOverlay extends ConsumerStatefulWidget {
  const InsureOverlay({super.key});

  @override
  ConsumerState<InsureOverlay> createState() => _InsureOverlayState();
}

class _InsureOverlayState extends ConsumerState<InsureOverlay> {
  double _value = 3450000; // KES vehicle value
  InsureSort _sort = InsureSort.cheapest;
  InsureMode? _mode; // resolved on first build from available data

  List<Insurer> _sorted(List<Insurer> motor) {
    final list = [...motor];
    switch (_sort) {
      case InsureSort.cheapest:
        list.sort((a, b) => a.premium(_value).compareTo(b.premium(_value)));
      case InsureSort.benefits:
        list.sort((a, b) => b.benefits.length.compareTo(a.benefits.length));
      case InsureSort.value:
        double score(Insurer i) =>
            i.premium(_value) / (i.benefits.length + (i.rating ?? 0) + 1);
        list.sort((a, b) => score(a).compareTo(score(b)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(insurersProvider);
    final motor = all.where((i) => i.hasMotor).toList();
    final travel = all.where((i) => i.plans.isNotEmpty).toList();

    final hasMotor = motor.isNotEmpty;
    final hasTravel = travel.isNotEmpty;
    // Resolve the active mode from what's available.
    final mode = _mode ?? (hasMotor ? InsureMode.motor : InsureMode.travel);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
      ),
      body: (!hasMotor && !hasTravel)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(t('insure.emptyMotor'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted)),
              ),
            )
          : Column(
              children: [
                DisplayHeader(
                  title: t('insure.title'),
                  sub: t('insure.sub'),
                ),
                const SizedBox(height: 10),
                if (hasMotor && hasTravel)
                  _ModeTabs(mode: mode, onMode: (m) => setState(() => _mode = m)),
                Expanded(
                  child: mode == InsureMode.motor
                      ? _motorBody(motor)
                      : _travelBody(travel),
                ),
              ],
            ),
    );
  }

  Widget _motorBody(List<Insurer> motor) {
    final sorted = _sorted(motor);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _ValueCard(value: _value, onChanged: (v) => setState(() => _value = v)),
        const SizedBox(height: 12),
        _SortRow(sort: _sort, onSort: (s) => setState(() => _sort = s)),
        const SizedBox(height: 8),
        if (sorted.length >= 2) _GapSignal(sorted, value: _value),
        for (final i in sorted) _InsurerCard(insurer: i, value: _value),
        Disclaimer(t('insure.disclaimer')),
      ],
    );
  }

  Widget _travelBody(List<Insurer> travel) {
    double cheapest(Insurer i) => i.plans
        .map((p) => p.price.toDouble())
        .fold(double.infinity, (a, b) => b < a ? b : a);
    final sorted = [...travel]..sort((a, b) => cheapest(a).compareTo(cheapest(b)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final i in sorted) _TravelCard(insurer: i),
        Disclaimer(t('insure.disclaimer')),
      ],
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onMode});
  final InsureMode mode;
  final ValueChanged<InsureMode> onMode;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tab(InsureMode m, String label) {
      final on = m == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onMode(m),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: on ? c.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: on ? c.text : c.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        tab(InsureMode.motor, t('insure.motor')),
        tab(InsureMode.travel, t('insure.travel')),
      ]),
    );
  }
}

class _TravelCard extends StatelessWidget {
  const _TravelCard({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = categoryColor('insurance');
    final plans = [...insurer.plans]
      ..sort((a, b) => a.price.compareTo(b.price));
    final from = plans.isEmpty ? null : plans.first.price;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FundLogo(
                  domain: insurer.logoDomain,
                  seed: insurer.name,
                  size: 38,
                  brandColor: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(insurer.name,
                    style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              if (from != null)
                Text(
                  t('insure.from',
                      {'amt': '${insurer.currency} ${withCommas(from.round())}'}),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in plans)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(p.name,
                        style: TextStyle(color: c.muted, fontSize: 13)),
                  ),
                  Text('${insurer.currency} ${withCommas(p.price.round())}',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('insure.vehicleValue'),
                  style: TextStyle(color: c.muted, fontSize: 13)),
              Text('KES ${withCommas(value.round())}',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
          Slider(
            value: value,
            min: 500000,
            max: 10000000,
            divisions: 190,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onSort});
  final InsureSort sort;
  final ValueChanged<InsureSort> onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget pill(InsureSort s, String label) {
      final on = s == sort;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSort(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: on ? c.s3 : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: on ? c.line2 : c.line),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? c.text : c.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Row(children: [
      pill(InsureSort.cheapest, t('insure.sort.cheapest')),
      pill(InsureSort.benefits, t('insure.sort.benefits')),
      pill(InsureSort.value, t('insure.sort.value')),
    ]);
  }
}

class _GapSignal extends StatelessWidget {
  const _GapSignal(this.sorted, {required this.value});
  final List<Insurer> sorted;
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final byPrice = [...sorted]
      ..sort((a, b) => a.premium(value).compareTo(b.premium(value)));
    final cheap = byPrice.first;
    final exp = byPrice.last;
    final gap = exp.premium(value) - cheap.premium(value);
    if (gap <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1, right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: c.line, borderRadius: BorderRadius.circular(6)),
            child: Text('GAP',
                style: TextStyle(
                    color: c.muted,
                    fontSize: 8.5,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(
              t('insure.gap', {
                'name': exp.name,
                'amt': 'KES ${withCommas(gap.round())}',
                'cheap': cheap.name,
              }),
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsurerCard extends StatelessWidget {
  const _InsurerCard({required this.insurer, required this.value});
  final Insurer insurer;
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = categoryColor('insurance');
    final premium = insurer.premium(value);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FundLogo(
                  domain: insurer.logoDomain,
                  seed: insurer.name,
                  size: 38,
                  brandColor: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insurer.name,
                        style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    if (insurer.rating != null) ...[
                      const SizedBox(height: 2),
                      Text('\u2605' * insurer.rating!,
                          style: TextStyle(color: c.accent, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Text('KES ${withCommas(premium.round())}',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (insurer.excessLabel.isNotEmpty)
                _meta(c, t('insure.excess', {'v': insurer.excessLabel})),
              if (insurer.claimsDays != null)
                _meta(c, t('insure.claims', {'d': '${insurer.claimsDays}'})),
            ],
          ),
          if (insurer.benefits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in insurer.benefits)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: c.s3,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(b,
                        style: TextStyle(color: c.muted, fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(fructaColors c, String text) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Text(text, style: TextStyle(color: c.faint, fontSize: 12)),
      );
}

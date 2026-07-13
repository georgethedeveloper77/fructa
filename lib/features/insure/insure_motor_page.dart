import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'motor_cover_selector.dart';

enum MotorSort { cheapest, claims, benefits, value }

/// Labels for the sort segments. These lived inline in the old _FilterPills;
/// SlidingSegments takes a labelOf callback, so they move onto the enum where
/// the travel page's sort already keeps them.
extension MotorSortX on MotorSort {
  String get label => switch (this) {
    MotorSort.cheapest => t('insure.filter.cheapest'),
    MotorSort.claims => t('insure.filter.claims'),
    MotorSort.benefits => t('insure.filter.benefits'),
    MotorSort.value => t('insure.filter.value'),
  };
}

const _kMinValue = 500000.0;
const _kMaxValue = 15000000.0;

class InsureMotorPage extends ConsumerStatefulWidget {
  const InsureMotorPage({super.key});

  @override
  ConsumerState<InsureMotorPage> createState() => _InsureMotorPageState();
}

class _InsureMotorPageState extends ConsumerState<InsureMotorPage> {
  double _value = 3450000;
  MotorSort _sort = MotorSort.cheapest;
  MotorClass _cls = MotorClass.private;
  CoverType _cover = CoverType.comprehensive;

  /// The price for the CURRENT selection. Never null here: callers only reach
  /// this for insurers already filtered to those that offer the selection.
  double _price(Insurer i) => i.quote(_value, cls: _cls, cover: _cover) ?? 0;

  List<Insurer> _sorted(List<Insurer> motor) {
    final list = [...motor];
    int claims(Insurer i) => i.claimsDays ?? 1 << 30;
    switch (_sort) {
      case MotorSort.cheapest:
        list.sort((a, b) => _price(a).compareTo(_price(b)));
      case MotorSort.claims:
        list.sort((a, b) => claims(a).compareTo(claims(b)));
      case MotorSort.benefits:
        list.sort((a, b) => b.benefits.length.compareTo(a.benefits.length));
      case MotorSort.value:
        double score(Insurer i) =>
            _price(i) / (i.benefits.length + (i.rating ?? 0) + 1);
        list.sort((a, b) => score(a).compareTo(score(b)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final levyPct = cfg.number('insure.levy_pct', 0.45).toDouble();
    final stamp = cfg.number('insure.stamp_kes', 40).toDouble();

    final all = ref.watch(insurersProvider).where((i) => i.hasMotor).toList();

    // Which classes anyone writes, so we never offer a choice that empties the
    // page, and whether TPO is published by anyone for the chosen class.
    final availableClasses = <MotorClass>{
      for (final i in all)
        for (final cls in MotorClass.values)
          if (i.writesClass(cls)) cls,
    };
    final tpoAvailable =
        all.any((i) => i.offers(_cls, CoverType.tpo));

    // Only insurers that actually publish a price for this class and cover.
    // An insurer that does not write PSV, or does not publish TPO, is absent
    // rather than shown at zero. Absence is the honest answer.
    final motor = all.where((i) => i.offers(_cls, _cover)).toList();

    if (motor.isEmpty) {
      return _shell(
        [
          _head(0),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Text(
              t('insure.emptyMotor'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.6),
            ),
          ),
        ],
      );
    }

    final sorted = _sorted(motor);
    final best = sorted.first;

    final byPrice = [...sorted]..sort((a, b) => _price(a).compareTo(_price(b)));
    final cheap = byPrice.first;
    final exp = byPrice.last;
    final gap = _price(exp) - _price(cheap);

    double landed(Insurer i) =>
        landedPremium(_price(i), levyPct: levyPct, stamp: stamp);

    return _shell([
      _head(sorted.length),
      // The three numbers this page exists to produce. The spread is the
      // whole argument, so it leads, and it is computed from the SAME
      // landed premiums the rows below show: the strip can never claim a
      // gap the list then fails to display.
      KpiStrip([
        KpiCell(
          label: t('insure.motor.kpiInsurers'),
          value: '${sorted.length}',
        ),
        KpiCell(
          label: t('insure.motor.kpiCheapest'),
          value: kesCompact(landed(cheap)),
          color: c.accent,
        ),
        KpiCell(
          label: t('insure.motor.kpiSpread'),
          value: gap <= 0
              ? '1.0x'
              : '${(landed(exp) / landed(cheap)).toStringAsFixed(1)}x',
          color: gap > 0 ? c.down : null,
        ),
      ]),
      MotorCoverSelector(
        cls: _cls,
        cover: _cover,
        availableClasses: availableClasses,
        tpoAvailable: tpoAvailable,
        onClass: (v) => setState(() {
          _cls = v;
          // Selecting a class nobody prices TPO for must not strand the
          // user on an empty list.
          if (_cover == CoverType.tpo &&
              !all.any((i) => i.offers(v, CoverType.tpo))) {
            _cover = CoverType.comprehensive;
          }
        }),
        onCover: (v) => setState(() => _cover = v),
      ),
      // TPO is a flat annual figure. Vehicle value does not enter into it,
      // so asking for one would be theatre.
      if (_cover == CoverType.comprehensive)
        _VehicleValueCard(
          value: _value,
          onChanged: (v) => setState(() => _value = v),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text(
          rcText(cfg, 'insure.indicativeNote'),
          style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.4),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: SlidingSegments<MotorSort>(
          values: MotorSort.values,
          selected: _sort,
          labelOf: (s) => s.label,
          onTap: (s) => setState(() => _sort = s),
        ),
      ),
      for (var qi = 0; qi < sorted.length; qi++)
        Stagger(
          index: qi,
          child: _quoteRow(context, sorted[qi], best, landed, landed(exp)),
        ),
      InsureH2(t('insure.whyPriciest')),
      if (gap > 0)
        SignalRow(
          tag: t('insure.gapTag'),
          tone: SignalTone.neutral,
          text: t('insure.gap', {
            'name': exp.name,
            'amt': kes(gap),
            'cheap': cheap.name,
          }),
          showDivider: exp.signals.isNotEmpty,
        ),
      for (var s = 0; s < exp.signals.length; s++)
        SignalRow(
          tag: exp.signals[s].label,
          text: exp.signals[s].text,
          tone: _tone(exp.signals[s].tag),
          showDivider: s < exp.signals.length - 1,
        ),
      InsureFoot(t('insure.motorFoot')),
      Disclaimer(rcText(cfg, 'insure.disc.motor')),
    ]);
  }

  /// The head block. Under TPO the screen is a different question, so it gets a
  /// different title and a line explaining what the cover actually buys: the
  /// legal minimum, and nothing at all for your own car. Under comprehensive
  /// the word "Motor" is enough, and a subtitle would only push the price down
  /// the screen.
  Widget _head(int n) {
    final tpo = _cover == CoverType.tpo;
    return InsureHead(
      kicker: t('insure.motor.kicker', {'n': '$n'}),
      title: tpo ? t('insure.motor.h1Tpo') : t('insure.motor'),
      sub: tpo ? t('insure.motor.subTpo') : null,
    );
  }


  /// The rate mechanics line, DERIVED from the quote rather than read off a
  /// column.
  ///
  /// base / value is the effective rate this insurer actually charged for THIS
  /// car, so it stays true whichever band the value lands in and it cannot
  /// drift from the price beside it. Reading motor_rate instead would print
  /// "3.00%" for CIC on a 1M car when the band charged 6.00%, which is the kind
  /// of quiet lie a rate comparison cannot afford.
  String _rateLabel(Insurer i) {
    if (_cover == CoverType.tpo) return t('insure.flatAnnual');
    final base = _price(i);
    if (base <= 0 || _value <= 0) return '';
    final pct = base / _value * 100;
    return t('insure.pctOfValue', {'pct': pct.toStringAsFixed(2)});
  }

  Widget _quoteRow(
    BuildContext context,
    Insurer i,
    Insurer best,
    double Function(Insurer) landed,
    double dearest,
  ) =>
      InsureQuoteRow(
        name: i.name,
        logoDomain: i.logoDomain,
        brand: insurerBrand(context, i),
        rateLabel: _rateLabel(i),
        meta: i.excessLabel.isEmpty
            ? null
            : t('insure.excessShort', {'v': i.excessLabel}),
        priceText: withCommas(landed(i).round()),
        priceUnit: t('insure.perYear'),
        barFraction: dearest <= 0 ? null : landed(i) / dearest,
        best: i.id == best.id,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InsurerDetailPage.motor(
              i,
              value: _value,
              cls: _cls,
              cover: _cover,
            ),
          ),
        ),
      );

  Widget _shell(List<Widget> children) =>
      InsureScaffold(navTitle: t('insure.motor'), children: children);
}

SignalTone _tone(String tag) => switch (tag.toUpperCase()) {
      'STRENGTH' => SignalTone.positive,
      'WATCH' => SignalTone.negative,
      _ => SignalTone.neutral,
    };

/// Vehicle value input: its own card with a slider AND a typed field, two-way
/// synced. The field drives the slider; the slider reformats the field when it
/// isn't being edited.
class _VehicleValueCard extends StatefulWidget {
  const _VehicleValueCard({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_VehicleValueCard> createState() => _VehicleValueCardState();
}

class _VehicleValueCardState extends State<_VehicleValueCard> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: withCommas(widget.value.round()));
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
      if (!_focus.hasFocus) _syncText();
    });
  }

  @override
  void didUpdateWidget(covariant _VehicleValueCard old) {
    super.didUpdateWidget(old);
    // Reformat from the slider only when the user isn't typing.
    if (!_focus.hasFocus && widget.value != old.value) _syncText();
  }

  void _syncText() {
    final text = withCommas(widget.value.round());
    if (_ctrl.text != text) _ctrl.text = text;
  }

  void _onTyped(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final v = double.parse(digits).clamp(_kMinValue, _kMaxValue);
    widget.onChanged(v.toDouble());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Compact "1M / 500K" label for range endpoints and quick-pick chips.
  String _short(double v) {
    final m = v / 1000000;
    return m >= 1
        ? '${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)}M'
        : '${(v / 1000).round()}K';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const quick = <double>[1000000, 3000000, 5000000, 10000000];

    Widget chip(double v) {
      final on = (widget.value - v).abs() < 1;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(v),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.accentSoft : c.s2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? Colors.transparent : c.line),
            ),
            child: Text(_short(v),
                style: TextStyle(
                    color: on ? c.accent : c.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: fructaFonts.mono)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
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
              Expanded(
                child: Text(t('insure.yourCar'),
                    style: TextStyle(
                        color: c.faint,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600)),
              ),
              Text(t('insure.coverType'),
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 10.5,
                      fontFamily: fructaFonts.mono)),
            ],
          ),
          const SizedBox(height: 12),
          // An unmistakable input: a tappable field box with an edit glyph and
          // an accent focus ring. Typing drives the slider; the slider reformats
          // this when it is not being edited. Numeric keyboards on iOS have no
          // return key, so dismissal is handled by the page tap and the slider.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focus.requestFocus,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _focused ? c.accent : c.line,
                    width: _focused ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Text('KES',
                      style: TextStyle(
                          color: c.faint,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: fructaFonts.mono)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      onChanged: _onTyped,
                      onSubmitted: (_) {
                        _syncText();
                        FocusScope.of(context).unfocus();
                      },
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                      ],
                      textAlign: TextAlign.left,
                      cursorColor: c.accent,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        fontFamily: fructaFonts.mono,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined,
                      size: 16, color: _focused ? c.accent : c.faint),
                ],
              ),
            ),
          ),
          Slider(
            value: widget.value.clamp(_kMinValue, _kMaxValue),
            min: _kMinValue,
            max: _kMaxValue,
            divisions: 290,
            onChangeStart: (_) => FocusScope.of(context).unfocus(),
            onChanged: widget.onChanged,
          ),
          Row(
            children: [
              Text('KES ${_short(_kMinValue)}',
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 10,
                      fontFamily: fructaFonts.mono)),
              const Spacer(),
              Text('KES ${_short(_kMaxValue)}',
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 10,
                      fontFamily: fructaFonts.mono)),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              for (var k = 0; k < quick.length; k++) ...[
                if (k > 0) const SizedBox(width: 7),
                chip(quick[k]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}


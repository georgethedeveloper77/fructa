import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_colors.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/models/remote_config.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

enum _View { fundType, assetClass }

const _fundTypeLabels = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

const _assetClassLabels = {
  'gok': 'Govt securities',
  'fixed_deposits': 'Fixed deposits',
  'cash': 'Cash & demand',
  'unlisted': 'Unlisted securities',
  'listed': 'Listed securities',
  'offshore': 'Offshore',
  'other_cis': 'Other CIS',
  'alternative': 'Alternative',
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// One slice: label + colour + share, plus AUM where the view has it
/// (fund-type only; asset classes carry percentages, not AUM).
class _Slice {
  const _Slice(this.label, this.color, this.share, this.aum);
  final String label;
  final Color color;
  final double share;
  final double? aum;
}

/// Compact KES: 852.0B → "852B", 4.75B → "4.8B", 442.2B → "442B".
String _compactKes(double v) {
  if (v >= 1e12) {
    final t = v / 1e12;
    return '${t >= 10 ? t.round() : t.toStringAsFixed(1)}T';
  }
  if (v >= 1e9) {
    final b = v / 1e9;
    return '${b >= 10 ? b.round() : b.toStringAsFixed(1)}B';
  }
  if (v >= 1e6) return '${(v / 1e6).round()}M';
  return v.round().toString();
}

/// 51.9 → "51.9", 44.0 → "44", 23.9 → "23.9".
String _pct(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// "2026-03-31" → "Q1 '26"; unparseable passes through.
String _asOfTag(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final year = m.group(1)!.substring(2);
  final q = ((int.parse(m.group(2)!) - 1) ~/ 3) + 1;
  return "Q$q '$year";
}

/// "2026-03-31" → "31 Mar 2026"; unparseable passes through.
String _prettyDate(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final mo = int.parse(m.group(2)!);
  if (mo < 1 || mo > 12) return iso;
  return '${int.parse(m.group(3)!)} ${_months[mo - 1]} ${m.group(1)}';
}

class MarketByAumPage extends ConsumerStatefulWidget {
  const MarketByAumPage({super.key});

  @override
  ConsumerState<MarketByAumPage> createState() => _MarketByAumPageState();
}

class _MarketByAumPageState extends ConsumerState<MarketByAumPage> {
  _View _view = _View.fundType;
  int _sel = -1;

  List<_Slice> _slices(RemoteConfig cfg) {
    if (_view == _View.fundType) {
      return [
        for (final t in cfg.marketFundTypes())
          _Slice(
            _fundTypeLabels[t.type] ?? t.type,
            fundTypeColor(t.type),
            t.share,
            t.aumKes,
          ),
      ];
    }
    return [
      for (final a in cfg.marketAssetClasses())
        _Slice(
          _assetClassLabels[a.clazz] ?? a.clazz,
          assetClassColor(a.clazz),
          a.share,
          null,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final slices = _slices(cfg);

    final asOf = _view == _View.fundType
        ? cfg.marketAsOf
        : cfg.marketAssetsAsOf;
    final tag = asOf != null ? _asOfTag(asOf) : null;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Market by AUM',
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _caption(c, tag),
          const SizedBox(height: 12),
          _segmented(c),
          const SizedBox(height: 16),
          _donut(c, slices),
          const SizedBox(height: 8),
          for (var i = 0; i < slices.length; i++) _legendRow(c, slices[i], i),
          const SizedBox(height: 20),
          _sourceCard(c, cfg, asOf),
        ],
      ),
    );
  }

  Widget _caption(fructaColors c, String? tag) {
    return Center(
      child: Text(
        'CMA CIS${tag != null ? " · $tag" : ""}',
        style: TextStyle(
          color: c.faint,
          fontFamily: fructaFonts.mono,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _segmented(fructaColors c) {
    Widget seg(String label, _View v) {
      final on = _view == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _view = v;
            _sel = -1;
          }),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.s1 : null,
              borderRadius: BorderRadius.circular(9),
              border: on ? Border.all(color: c.line2) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: on ? c.text : c.muted,
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          seg('By fund type', _View.fundType),
          seg('By asset class', _View.assetClass),
        ],
      ),
    );
  }

  Widget _donut(fructaColors c, List<_Slice> slices) {
    return SizedBox(
      height: 226,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 64,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, resp) {
                  if (!event.isInterestedForInteractions ||
                      resp?.touchedSection == null) {
                    setState(() => _sel = -1);
                    return;
                  }
                  setState(
                    () => _sel = resp!.touchedSection!.touchedSectionIndex,
                  );
                },
              ),
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].share,
                    color: (_sel < 0 || _sel == i)
                        ? slices[i].color
                        : slices[i].color.withValues(alpha: 0.30),
                    radius: i == _sel ? 42 : 34,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          _center(c, slices),
        ],
      ),
    );
  }

  Widget _center(fructaColors c, List<_Slice> slices) {
    late final String big;
    late final String sub;
    late final Color subColor;

    if (_sel >= 0 && _sel < slices.length) {
      big = '${_pct(slices[_sel].share)}%';
      sub = slices[_sel].label.toUpperCase();
      subColor = slices[_sel].color;
    } else if (_view == _View.fundType) {
      final total = slices.fold<double>(0, (a, b) => a + (b.aum ?? 0));
      big = _compactKes(total);
      sub = 'KES AUM';
      subColor = c.faint;
    } else {
      big = '100%';
      sub = 'OF MARKET';
      subColor = c.faint;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          big,
          style: TextStyle(
            color: c.text,
            fontFamily: fructaFonts.mono,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 96,
          child: Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subColor,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendRow(fructaColors c, _Slice s, int i) {
    final selected = i == _sel;
    return InkWell(
      onTap: () => setState(() => _sel = selected ? -1 : i),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.label,
                    style: TextStyle(
                      color: selected ? c.text : c.muted,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_pct(s.share)}%',
                  style: TextStyle(
                    color: selected ? c.text : c.muted,
                    fontFamily: fructaFonts.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (s.aum != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 46,
                    child: Text(
                      _compactKes(s.aum!),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: c.faint,
                        fontFamily: fructaFonts.mono,
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (s.share / 100).clamp(0.02, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected
                          ? s.color
                          : s.color.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard(fructaColors c, RemoteConfig cfg, String? asOf) {
    final source =
        (_view == _View.fundType ? cfg.marketSource : cfg.marketAssetsSource) ??
        'CMA CIS Quarterly Report';
    final dated = asOf != null ? ', as of ${_prettyDate(asOf)}' : '';

    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
    final tracked = funds.where((f) => f.retail).length;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.info_outline, size: 16, color: c.faint),
              const SizedBox(width: 8),
              Text(
                'How this is sourced',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$source$dated. SACCOs sit in a separate SASRA market and are not '
            'part of this CIS set.',
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
          ),
          if (tracked > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Fructa tracks $tracked retail '
              '${tracked == 1 ? 'fund' : 'funds'} against this benchmark.',
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/projection_engine.dart';

/// Add a holding — multi-step, on-device.
///
/// 1) Type   — big cards bucketed by `fund_type` × `currency` (authoritative,
///    never legacy `category`). MMF therefore splits into "Money market · KES"
///    and "Money market · USD", which is the whole reason for the type step.
///    Cards size to their content (IntrinsicHeight rows) so nothing overflows,
///    even at the largest text scale.
/// 2) Fund   — a big search inside the chosen bucket that loads only the top 3
///    by rate until you type; every row carries the manager's real logo +
///    brand tint + its own sparkline + the live rate.
/// 3) Balance — amount with a live growth chart: what it becomes in a year,
///    net of tax, at today's rate.
///
/// Dark-mode contrast: surfaces use `s2`/`s3` (not `s1`) and borders use
/// `line2`, so cards and rows read against the near-black background.
class AddHoldingPage extends ConsumerStatefulWidget {
  const AddHoldingPage({super.key});
  @override
  ConsumerState<AddHoldingPage> createState() => _AddHoldingPageState();
}

typedef _Bucket = ({String type, String currency});

const _typeOrder = ['mmf', 'fixed_income', 'equity', 'balanced', 'special'];
const _typeLabels = {
  'mmf': 'Money market',
  'fixed_income': 'Fixed income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};
IconData _typeIcon(String t) => switch (t) {
      'mmf' => Icons.savings_outlined,
      'fixed_income' => Icons.account_balance_outlined,
      'equity' => Icons.trending_up_rounded,
      'balanced' => Icons.balance_rounded,
      'special' => Icons.workspace_premium_outlined,
      _ => Icons.category_outlined,
    };
int _ccyRank(String x) => x == 'KES' ? 0 : (x == 'USD' ? 1 : 2);

class _AddHoldingPageState extends ConsumerState<AddHoldingPage> {
  _Bucket? _bucket; // null → falls back to the first bucket present
  String _query = '';
  Fund? _fund;
  final _balance = TextEditingController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _balance.dispose();
    _search.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_balance.text.replaceAll(',', ''));

  bool _match(Fund f, String q) =>
      f.name.toLowerCase().contains(q) ||
      f.manager.toLowerCase().contains(q);

  Future<void> _save() async {
    final f = _fund;
    final amount = _amount;
    if (f == null || amount == null || amount <= 0) return;
    await ref
        .read(holdingsProvider.notifier)
        .setBalance(f.id, f.currency, amount);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final q = _query.trim().toLowerCase();

    final rateable = all.where((f) => f.currentRate != null).toList();
    final retail = rateable.where((f) => f.retail).toList();

    // Buckets = (fund_type × currency) present in the retail cut, ordered by
    // type then KES-before-USD. No legacy category, no empty buckets.
    final buckets = <_Bucket>[];
    for (final t in _typeOrder) {
      final ccys = retail
          .where((f) => f.fundType == t)
          .map((f) => f.currency)
          .toSet()
          .toList()
        ..sort((a, b) {
          final d = _ccyRank(a) - _ccyRank(b);
          return d != 0 ? d : a.compareTo(b);
        });
      for (final ccy in ccys) buckets.add((type: t, currency: ccy));
    }
    final active = _bucket ?? (buckets.isNotEmpty ? buckets.first : null);

    final pool = q.isEmpty ? retail : rateable; // search widens past retail
    final matches = active == null
        ? const <Fund>[]
        : (pool
            .where((f) =>
                f.fundType == active.type &&
                f.currency == active.currency &&
                (q.isEmpty || _match(f, q)))
            .toList()
          ..sort((a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0)));

    // The "two or three" rule: only the top 3 until the user searches.
    final shown = (q.isEmpty ? matches.take(3) : matches.take(12)).toList();
    final canSave = _fund != null && (_amount ?? 0) > 0;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 40),
        children: [
          const DisplayHeader(
            title: 'Add a holding',
            sub: 'Stays on this device',
          ),
          const SizedBox(height: 14),

          // ── Step 1 — Type (cards, bucketed by type × currency) ────────
          _StepLabel(n: '1', label: 'Type'),
          const SizedBox(height: 12),
          _typeGrid(buckets, active, retail),
          const SizedBox(height: 24),

          // ── Step 2 — Fund (big search, top 3) ─────────────────────────
          _StepLabel(n: '2', label: 'Fund'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: c.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search this type',
                hintStyle: TextStyle(color: c.muted, fontSize: 15),
                prefixIcon: Icon(Icons.search, color: c.muted, size: 22),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, color: c.muted, size: 18),
                        onPressed: () => setState(() {
                          _query = '';
                          _search.clear();
                        }),
                      ),
                filled: true,
                fillColor: c.s2,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.line2)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.accent, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (q.isEmpty && shown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
              child: Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 15, color: c.accent),
                  const SizedBox(width: 6),
                  Text('Top rates',
                      style: TextStyle(
                          color: c.muted,
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Text(
                q.isEmpty
                    ? 'No funds available in this type yet.'
                    : 'No fund matches that. Try the manager\u2019s name.',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            )
          else
            for (final f in shown) _fundRow(f),

          // ── Step 3 — Balance (appears once a fund is chosen) ──────────
          if (_fund != null) ...[
            const SizedBox(height: 24),
            _StepLabel(n: '3', label: 'Balance'),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _balanceSection(_fund!),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    disabledBackgroundColor: c.s3,
                    disabledForegroundColor: c.muted,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Add to portfolio'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Type grid — IntrinsicHeight rows so cards fit their content ───────
  Widget _typeGrid(List<_Bucket> buckets, _Bucket? active, List<Fund> retail) {
    final rows = <Widget>[];
    for (var i = 0; i < buckets.length; i += 2) {
      final left = buckets[i];
      final right = (i + 1 < buckets.length) ? buckets[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _typeCardFor(left, active, retail)),
              const SizedBox(width: 11),
              Expanded(
                child: right != null
                    ? _typeCardFor(right, active, retail)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }

  Widget _typeCardFor(_Bucket b, _Bucket? active, List<Fund> retail) {
    final n = retail
        .where((f) => f.fundType == b.type && f.currency == b.currency)
        .length;
    return _TypeCard(
      icon: _typeIcon(b.type),
      title: _typeLabels[b.type] ?? b.type,
      sub: '${b.currency} \u00b7 $n ${n == 1 ? 'fund' : 'funds'}',
      active: active != null && active.type == b.type && active.currency == b.currency,
      onTap: () => setState(() {
        _bucket = b;
        _fund = null;
      }),
    );
  }

  // ── Fund row — real logo + brand tint + sparkline + rate ──────────────
  Widget _fundRow(Fund f) {
    final c = context.c;
    final brand =
        ref.watch(brandColorProvider(f.id)) ?? fundTypeColor(f.fundType);
    final logoUrl = ref.watch(logoUrlProvider(f.id));
    final active = _fund?.id == f.id;

    return InkWell(
      onTap: () => setState(() => _fund = f),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.s2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? c.accent : c.line2, width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            FundLogo(
                domain: f.logoDomain,
                logoUrl: logoUrl,
                brandColor: brand,
                seed: f.manager,
                size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(f.manager,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11)),
                ],
              ),
            ),
            if (f.spark.length >= 2) ...[
              const SizedBox(width: 10),
              SizedBox(width: 54, height: 26, child: _Spark(f.spark, brand)),
            ],
            const SizedBox(width: 10),
            if (f.currentRate != null)
              Text('${f.currentRate!.toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: brand,
                      fontFamily: fructaFonts.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Balance section — field + live growth chart ───────────────────────
  Widget _balanceSection(Fund f) {
    final c = context.c;
    final brand =
        ref.watch(brandColorProvider(f.id)) ?? fundTypeColor(f.fundType);
    final rate = f.currentRate ?? 0;
    final amt = _amount ?? 0;

    final series = amt > 0
        ? ProjectionEngine.series(amt, rate, 12, net: true)
        : const <double>[];
    final yearEnd = series.isNotEmpty ? series.last : amt;
    final gain = yearEnd - amt;

    final fx = ref.watch(usdKesProvider);
    final kesNote = (f.currency == 'USD' && fx != null && yearEnd > 0)
        ? ' \u00b7 ${money('KES', (yearEnd * fx).round())}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _balance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style:
              TextStyle(color: c.text, fontSize: 22, fontFamily: fructaFonts.mono),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: '${f.currency}  ',
            prefixStyle: TextStyle(color: c.muted, fontSize: 18),
            hintText: '0',
            hintStyle: TextStyle(color: c.muted),
            filled: true,
            fillColor: c.s2,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.accent, width: 1.5)),
          ),
        ),
        if (amt > 0 && rate > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IN A YEAR, NET OF TAX',
                    style: TextStyle(
                        color: c.muted,
                        fontFamily: fructaFonts.mono,
                        fontSize: 9.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${money(f.currency, yearEnd)}$kesNote',
                    style: TextStyle(
                        color: c.text,
                        fontFamily: fructaFonts.mono,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.trending_up_rounded, size: 15, color: c.up),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                          '+${money(f.currency, gain)} at ${rate.toStringAsFixed(2)}%',
                          style: TextStyle(
                              color: c.up,
                              fontFamily: fructaFonts.mono,
                              fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(height: 60, child: _GrowthChart(series, brand)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'fructa tracks this daily from today. Illustration at today\u2019s rate held flat \u2014 not a promise.',
            style: TextStyle(color: c.muted, fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }
}

// ── Type card (content-sized) ────────────────────────────────────────────
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String sub;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.s2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? c.accent : c.line2, width: active ? 1.6 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? c.accent.withValues(alpha: 0.18) : c.s3,
                borderRadius: BorderRadius.circular(11),
              ),
              child:
                  Icon(icon, color: active ? c.accentInk : c.muted, size: 21),
            ),
            const SizedBox(height: 12),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

// ── Step label (numbered) ────────────────────────────────────────────────
class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.n, required this.label});
  final String n;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: Text(n,
                style: TextStyle(
                    color: c.onAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Row sparkline (from fund.spark) ──────────────────────────────────────
class _Spark extends StatelessWidget {
  const _Spark(this.data, this.color);
  final List<double> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lo = data.reduce((a, b) => a < b ? a : b);
    final hi = data.reduce((a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minX: 0,
      maxX: (data.length - 1).toDouble(),
      minY: lo,
      maxY: hi + (hi - lo) * 0.08,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.3,
          color: color,
          barWidth: 1.8,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}

// ── Balance growth chart (12-month projection series) ────────────────────
class _GrowthChart extends StatelessWidget {
  const _GrowthChart(this.series, this.color);
  final List<double> series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) return const SizedBox.shrink();
    final lo = series.reduce((a, b) => a < b ? a : b);
    final hi = series.reduce((a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minX: 0,
      maxX: (series.length - 1).toDouble(),
      minY: lo,
      maxY: hi + (hi - lo) * 0.05,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < series.length; i++)
              FlSpot(i.toDouble(), series[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.28,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.20),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    ));
  }
}

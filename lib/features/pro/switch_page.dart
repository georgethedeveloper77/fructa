import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../core/widgets/reveal_text.dart';
import '../../data/models/fund.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/portfolio_math.dart';
import '../company/company_contact.dart';
import '../company/company_page.dart';

/// Should I switch? The real gain from moving money between two funds of the
/// same kind and currency: the extra net interest a year, less what is lost
/// while the money is in transit and earning nothing.
///
/// Fructa never moves money. The bottom half says how to do it for real:
/// ask the current manager to withdraw, open an account with the new one and
/// deposit, then record both in Fructa so the portfolio matches. Each manager's
/// own phone, WhatsApp, email and website sit right there.
class SwitchPage extends ConsumerStatefulWidget {
  const SwitchPage({super.key, this.fromFundId, this.toFundId});

  /// A fund the user holds. Defaults to their largest eligible holding.
  final String? fromFundId;

  /// Defaults to the best net rate among the holding's peers.
  final String? toFundId;

  @override
  ConsumerState<SwitchPage> createState() => _SwitchPageState();
}

class _SwitchPageState extends ConsumerState<SwitchPage> {
  late String? _from = widget.fromFundId;
  late String? _to = widget.toFundId;
  double? _amount;
  int _days = 3;

  double _net(Fund f, double wht) => f.taxFree || !f.whtStillDue
      ? f.currentRate!
      : f.currentRate! * (1 - wht / 100);

  List<Fund> _peers(Fund f, Iterable<Fund> all) => all
      .where(
        (x) =>
            x.retail &&
            x.showsYield &&
            x.currentRate != null &&
            x.currency == f.currency &&
            x.fundType == f.fundType,
      )
      .toList();

  Future<void> _pickTarget(Fund from, List<Fund> peers, double wht) async {
    final c = context.c;
    final sorted = [...peers]
      ..sort((a, b) => _net(b, wht).compareTo(_net(a, wht)));
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.s1,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in sorted)
                if (f.id != from.id)
                  ListTile(
                    title: Text(
                      f.name,
                      style: TextStyle(color: c.text, fontSize: 14.5),
                    ),
                    trailing: Text(
                      '${_net(f, wht).toStringAsFixed(2)}%',
                      style: fructaFonts.numeric(
                        color: c.text,
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => Navigator.of(ctx).pop(f.id),
                  ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _to = picked);
  }

  /// Records the move: a withdrawal from the old holding and a deposit into
  /// the new one, both dated today. Only after the user says the money moved.
  Future<void> _record(Holding h, Fund to, double amount) async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.s2,
        title: Text(
          t('switch.record.title'),
          style: TextStyle(color: c.text, fontSize: 17),
        ),
        content: Text(
          t('switch.record.body', {
            'amount': money(h.currency, amount),
            'to': to.name,
          }),
          style: TextStyle(color: c.muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('switch.record.confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = ref.read(holdingsProvider.notifier);
    final today = DateTime.now();
    await n.addTxn(h.fundId, -amount, today);
    final existing = ref
        .read(holdingsProvider)
        .where((x) => x.fundId == to.id)
        .firstOrNull;
    if (existing != null) {
      await n.addTxn(to.id, amount, today);
    } else {
      await n.setBalance(to.id, h.currency, amount);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('switch.record.done', {'to': to.name}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final funds = ref.watch(fundsByIdProvider);
    final companies = ref.watch(companiesProvider);
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final holdings = ref
        .watch(holdingsProvider)
        .where(
          (h) =>
              !h.isSacco &&
              funds[h.fundId]?.currentRate != null &&
              funds[h.fundId]!.showsYield,
        )
        .toList();

    Scaffold page(Widget body) => Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('switch.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: body,
    );

    if (holdings.isEmpty) {
      return page(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              t('switch.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 15, height: 1.45),
            ),
          ),
        ),
      );
    }

    final h = holdings.firstWhere(
      (x) => x.fundId == _from,
      orElse: () => holdings.first,
    );
    final from = funds[h.fundId]!;
    final peers = _peers(from, funds.values);
    final best = ([
      ...peers,
    ]..sort((a, b) => _net(b, wht).compareTo(_net(a, wht)))).first;
    final to =
        (_to != null ? funds[_to] : null) ??
        (best.id == from.id && peers.length > 1
            ? ([...peers]
                ..sort((a, b) => _net(b, wht).compareTo(_net(a, wht))))[1]
            : best);
    final value = PortfolioMath.value(
      h,
      ratePercent: from.currentRate,
      taxFree: from.taxFree,
      usdKes: null,
    ).valueNative;
    final amount = _amount ?? value;

    final a = _net(from, wht);
    final b = _net(to, wht);
    final yearly = amount * (b - a) / 100;
    final transit = amount * b / 100 * _days / 365;
    final gain = yearly - transit;
    final floor = h.currency == 'USD' ? 5.0 : 500.0;
    final worth = gain >= floor;
    final breakEvenWeeks = yearly <= 0
        ? null
        : (transit / (yearly / 365) / 7).ceil();
    String m(double v) => money(h.currency, v.abs());

    return page(
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          // ── From / to ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _FundBox(
                  label: t('switch.from'),
                  fund: from,
                  rate: a,
                  accent: c.line,
                  onTap: holdings.length > 1
                      ? () => setState(() {
                          final i = holdings.indexOf(h);
                          _from = holdings[(i + 1) % holdings.length].fundId;
                          _to = null;
                          _amount = null;
                        })
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: c.faint,
                  size: 18,
                ),
              ),
              Expanded(
                child: _FundBox(
                  label: t('switch.to'),
                  fund: to,
                  rate: b,
                  accent: c.up,
                  onTap: () => _pickTarget(from, peers, wht),
                ),
              ),
            ],
          ),

          // ── Amount and transit days ────────────────────────────────────────
          const SizedBox(height: 16),
          Text(
            t('switch.amount'),
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in <double>{
                if (value > 10000) 10000,
                if (value > 50000) 50000,
                if (value > 100000) 100000,
                value,
              })
                ChoiceChip(
                  label: Text(
                    v == value ? t('switch.all', {'amount': m(v)}) : m(v),
                  ),
                  selected: (amount - v).abs() < 0.5,
                  onSelected: (_) => setState(() => _amount = v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('switch.days'),
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
              IconButton(
                tooltip: t('switch.fewer'),
                onPressed: _days > 1 ? () => setState(() => _days--) : null,
                icon: Icon(Icons.remove_rounded, color: c.text),
              ),
              Text(
                t('switch.daysN', {'n': '$_days'}),
                style: fructaFonts.numeric(
                  color: c.text,
                  size: 15,
                  weight: FontWeight.w600,
                ),
              ),
              IconButton(
                tooltip: t('switch.more'),
                onPressed: _days < 14 ? () => setState(() => _days++) : null,
                icon: Icon(Icons.add_rounded, color: c.text),
              ),
            ],
          ),

          // ── Verdict ────────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: worth ? c.upSoft : c.s2,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(worth ? 'switch.worth' : 'switch.notWorth'),
                  style: TextStyle(
                    color: worth ? c.up : c.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${gain >= 0 ? '+' : '-'}${m(gain)}',
                  style: fructaFonts.numeric(
                    color: worth ? c.up : c.text,
                    size: 40,
                    weight: FontWeight.w600,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  worth && breakEvenWeeks != null
                      ? t('switch.breakEven', {'n': '$breakEvenWeeks'})
                      : t('switch.belowFloor', {'floor': m(floor)}),
                  style: TextStyle(color: c.text, fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),

          // ── Breakdown ──────────────────────────────────────────────────────
          const SizedBox(height: 12),
          _Rows(
            rows: [
              (t('switch.row.extra'), '+${m(yearly)}', c.up),
              (t('switch.row.transit'), '-${m(transit)}', c.down),
              (
                t('switch.row.diff'),
                '${b - a >= 0 ? '+' : ''}${(b - a).toStringAsFixed(2)} pts',
                c.text,
              ),
              (
                t('switch.row.gain'),
                '${gain >= 0 ? '+' : '-'}${m(gain)}',
                gain >= 0 ? c.up : c.down,
              ),
            ],
          ),

          // ── How to switch, for real ────────────────────────────────────────
          const SizedBox(height: 26),
          Text(
            t('switch.how'),
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          RevealText(
            t('switch.howSub'),
            style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          _Step(
            n: 1,
            title: t('switch.step1', {'from': from.name}),
            sub: t('switch.step1Sub', {'amount': m(amount)}),
            child: CompanyContact(company: companies[from.companyId]),
          ),
          _Step(
            n: 2,
            title: t('switch.step2', {'to': to.name}),
            sub: t('switch.step2Sub'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CompanyContact(company: companies[to.companyId]),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.text,
                    side: BorderSide(color: c.line2),
                  ),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => CompanyPage(to))),
                  child: Text(t('switch.openFund', {'to': to.name})),
                ),
              ],
            ),
          ),
          _Step(
            n: 3,
            title: t('switch.step3'),
            sub: t('switch.step3Sub'),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: amount > h.balance + 0.5
                  ? null
                  : () => _record(h, to, amount),
              child: Text(t('switch.recordCta')),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t('switch.disclaimer'),
            style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FundBox extends ConsumerWidget {
  const _FundBox({
    required this.label,
    required this.fund,
    required this.rate,
    required this.accent,
    this.onTap,
  });

  final String label;
  final Fund fund;
  final double rate;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent, width: accent == c.line ? 1 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.swap_vert_rounded, size: 14, color: c.faint),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  FundLogo(
                    domain: fund.logoDomain,
                    logoUrl: ref.watch(logoUrlProvider(fund.id)),
                    seed: fund.manager,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fund.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t('switch.net', {'rate': rate.toStringAsFixed(2)}),
                style: fructaFonts.numeric(
                  color: accent == c.line ? c.muted : c.up,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<(String, String, Color)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(
                        color: i == rows.length - 1 ? c.text : c.muted,
                        fontSize: 13.5,
                        fontWeight: i == rows.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: fructaFonts.numeric(
                      color: rows[i].$3,
                      size: 14,
                      weight: FontWeight.w600,
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

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.sub,
    required this.child,
  });

  final int n;
  final String title;
  final String sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: fructaFonts.numeric(
                color: c.accentInk,
                size: 13,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

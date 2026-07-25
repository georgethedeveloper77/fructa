import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/follow_star.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../company/company_page.dart';

/// The funds this device follows, read straight from [subscriptionsProvider]
/// (the same set that drives the `follow_<id>` push tags and the rate-move
/// alerts). Each row unfollows in place with the same star control the fund
/// pages use, and unfollowing drops it from the list live. Held funds are
/// auto-followed, so they appear here too.
class FollowingPage extends ConsumerWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final subs = ref.watch(subscriptionsProvider);
    final byId = ref.watch(fundsByIdProvider);

    // Resolve to funds (a followed id whose fund is not in the current snapshot
    // is skipped rather than shown blank), leaders first.
    final funds = subs.map((id) => byId[id]).whereType<Fund>().toList()
      ..sort((a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: c.text),
        title: Text(
          'Following',
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: funds.isEmpty
          ? const _Empty()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: funds.length,
              itemBuilder: (_, i) => _FollowRow(fund: funds[i]),
            ),
    );
  }
}

class _FollowRow extends ConsumerWidget {
  const _FollowRow({required this.fund});

  final Fund fund;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rate = fund.currentRate;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => CompanyPage(fund))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fund.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _meta(fund),
                      style: TextStyle(
                        color: c.faint,
                        fontFamily: fructaFonts.mono,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (rate != null)
                Text(
                  '${rate.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              FollowStar(
                following: true,
                tint: c.accent,
                onToggle: () =>
                    ref.read(subscriptionsProvider.notifier).toggle(fund.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _meta(Fund f) {
  const names = {
    'mmf': 'Money Market',
    'fixed_income': 'Fixed Income',
    'equity': 'Equity',
    'balanced': 'Balanced',
    'special': 'Special',
  };
  final t = names[f.fundType];
  return t != null ? '$t \u00b7 ${f.currency}' : f.currency;
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border_rounded, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(
              'You are not following any funds yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap Follow on a fund to get an alert when its rate moves.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

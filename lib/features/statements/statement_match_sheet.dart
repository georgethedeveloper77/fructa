import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';
import '../../data/statements/statement_store.dart';
import 'statement_controller.dart';

/// Match a checked statement to a holding.
///
/// Shows which fund it belongs to (suggested, or picked from the manager's
/// funds in that currency), the deposits and withdrawals that will be
/// recorded with their real dates, the balance that becomes the holding's
/// confirmed balance, and how many entries you typed that the statement will
/// replace. Nothing changes until the user confirms.
Future<void> showStatementMatchSheet(
  BuildContext context, {
  required SavedStatement saved,
  required Fund? suggested,
}) {
  final c = context.c;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.s1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MatchSheet(saved: saved, suggested: suggested),
  );
}

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet({required this.saved, required this.suggested});

  final SavedStatement saved;
  final Fund? suggested;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  late String? _fundId = widget.saved.fundId ?? widget.suggested?.id;
  bool _busy = false;

  Future<void> _apply(Fund fund) async {
    setState(() => _busy = true);
    final d = widget.saved.data;
    await ref
        .read(holdingsProvider.notifier)
        .applyStatement(
          fundId: fund.id,
          currency: d.currency,
          kind: HoldingKind.fund,
          flows: flowsOf(d),
          anchor: anchorOf(d),
        );
    await ref
        .read(statementsProvider.notifier)
        .setFund(widget.saved.id, fund.id);
    if (d.managerKey != 'unknown') await Push.tagStatementManager(d.managerKey);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('statement.match.done', {'name': fund.name}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = widget.saved.data;
    final funds = ref.watch(fundsByIdProvider);
    final options = candidateFunds(d, funds.values);
    if (widget.suggested != null &&
        !options.any((f) => f.id == widget.suggested!.id)) {
      options.insert(0, widget.suggested!);
    }
    final fund = _fundId == null ? null : funds[_fundId];
    final existing = ref
        .watch(holdingsProvider)
        .where((h) => h.fundId == _fundId)
        .firstOrNull;
    final replaced = existing == null
        ? 0
        : existing.transactions
              .where((t) => !t.fromStatement && !t.date.isAfter(d.to))
              .length;
    final flows = flowsOf(d);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              t('statement.match.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('statement.match.sub', {
                'name': d.managerName.isEmpty
                    ? t('statement.unknownManager')
                    : d.managerName,
                'ccy': d.currency,
                'tail': d.accountTail,
              }),
              style: TextStyle(color: c.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            if (options.isEmpty)
              Text(
                t('statement.match.noFund'),
                style: TextStyle(color: c.down, fontSize: 14),
              )
            else
              for (final f in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Choice(
                    title: f.name,
                    sub:
                        ref.watch(holdingsProvider).any((h) => h.fundId == f.id)
                        ? t('statement.match.inPortfolio')
                        : t('statement.match.newHolding'),
                    selected: f.id == _fundId,
                    onTap: () => setState(() => _fundId = f.id),
                  ),
                ),
            const SizedBox(height: 10),
            Text(
              t('statement.match.willAdd'),
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final x in flows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Icon(
                      x.isWithdrawal
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      size: 16,
                      color: x.isWithdrawal ? c.down : c.up,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${t(x.isWithdrawal ? 'ledger.withdrawal' : 'ledger.deposit')} \u00b7 ${dayLabel(x.date)}',
                        style: TextStyle(color: c.text, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${x.isWithdrawal ? '-' : '+'}${money(d.currency, x.amount.abs())}',
                      style: fructaFonts.numeric(
                        color: x.isWithdrawal ? c.down : c.up,
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('statement.match.balanceSet', {'date': dayLabel(d.to)}),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ),
                  Text(
                    money(d.currency, d.closingBalance),
                    style: fructaFonts.numeric(
                      color: c.text,
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (replaced > 0)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  t('statement.match.replaces', {
                    'n': '$replaced',
                    'date': dayLabel(d.to),
                  }),
                  style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: fund == null || _busy ? null : () => _apply(fund),
              child: Text(
                t(
                  existing == null
                      ? 'statement.match.add'
                      : 'statement.match.update',
                ),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('statement.match.undo'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.faint, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.s2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? c.accent : c.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? c.accent : c.faint,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

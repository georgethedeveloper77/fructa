import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// [subject] is what the holding is held in: a fund or a SACCO. Resolved by the
/// caller, because only the caller knows the holding's kind.
void showManageHolding(
  BuildContext context,
  Holding holding,
  HoldingSubject? subject,
) {
  final c = context.c;
  showModalBottomSheet(
    context: context,
    backgroundColor: c.s1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ManageSheet(holding: holding, fund: subject),
  );
}

class _ManageSheet extends ConsumerStatefulWidget {
  final Holding holding;
  final HoldingSubject? fund;
  const _ManageSheet({required this.holding, required this.fund});
  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  late final int _decimals = widget.holding.currency == 'USD' ? 2 : 0;
  late final TextEditingController _balance = TextEditingController(
    text: groupedAmount(widget.holding.balance, decimals: _decimals),
  );

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_balance.text.replaceAll(',', ''));
    if (amount == null || amount < 0) return;
    await ref
        .read(holdingsProvider.notifier)
        .setBalance(widget.holding.fundId, widget.holding.currency, amount);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.s1,
        title: Text(t('portfolio.manage.removeTitle'),
            style: TextStyle(color: c.text)),
        content: Text(
          t('portfolio.manage.removeBody', {
            'name': widget.fund?.name ?? widget.holding.fundId,
          }),
          style: TextStyle(color: c.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('common.cancel'), style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('common.remove'), style: TextStyle(color: c.down)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(holdingsProvider.notifier).remove(widget.holding.fundId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = widget.holding;
    final f = widget.fund;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              FundLogo(
                domain: f?.logoDomain,
                logoUrl: f?.logoUrl,
                brandColor: f?.brandColor,
                seed: f?.manager ?? h.fundId,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f?.name ?? h.fundId,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (f != null && f.ratePercent != null)
                      Text(
                        t('portfolio.manage.rateManager', {
                          'rate': f.ratePercent!.toStringAsFixed(2),
                          'manager': f.manager ?? '',
                        }),
                        style: TextStyle(color: c.faint, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            f != null && f.isSacco
                ? 'Your deposits (savings only, not share capital)'
                : t('portfolio.manage.balance'),
            style: TextStyle(color: c.faint, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsInputFormatter(decimals: _decimals)],
            style: TextStyle(color: c.text, fontSize: 20),
            decoration: InputDecoration(
              prefixText: '${h.currency}  ',
              prefixStyle: TextStyle(color: c.muted, fontSize: 18),
              filled: true,
              fillColor: c.s2,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.accent),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('portfolio.manage.was',
                {'amt': money(h.currency, h.balance)}),
            style: TextStyle(color: c.faint, fontSize: 11),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(t('common.save')),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _remove,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.down,
                  side: BorderSide(color: c.line),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 18,
                  ),
                ),
                child: Text(t('common.remove')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

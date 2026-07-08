import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/fund.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';

void showManageHolding(BuildContext context, Holding holding, Fund? fund) {
  final c = context.c;
  showModalBottomSheet(
    context: context,
    backgroundColor: c.s1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ManageSheet(holding: holding, fund: fund),
  );
}

class _ManageSheet extends ConsumerStatefulWidget {
  final Holding holding;
  final Fund? fund;
  const _ManageSheet({required this.holding, required this.fund});
  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  late final TextEditingController _balance = TextEditingController(
    text: widget.holding.balance.toStringAsFixed(0),
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
        title: Text('Remove holding?', style: TextStyle(color: c.text)),
        content: Text(
          'This removes ${widget.fund?.name ?? widget.holding.fundId} from your portfolio. Your money isn’t touched  this is just tracking.',
          style: TextStyle(color: c.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: c.down)),
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
                    if (f?.currentRate != null)
                      Text(
                        '${f!.currentRate!.toStringAsFixed(2)}% · ${f.manager}',
                        style: TextStyle(color: c.faint, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Balance', style: TextStyle(color: c.faint, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            'Was ${money(h.currency, h.balance)} · a change is logged as a deposit or withdrawal.',
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
                  child: const Text('Save'),
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
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

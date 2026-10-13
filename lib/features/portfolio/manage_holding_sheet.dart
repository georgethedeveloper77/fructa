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
        title: Text(
          t('portfolio.manage.removeTitle'),
          style: TextStyle(color: c.text),
        ),
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

  /// Opens the dated entry form for a deposit or a withdrawal.
  Future<void> _record({required bool withdrawal}) async {
    final ok = await showRecordTxnSheet(
      context,
      holding: _live,
      withdrawal: withdrawal,
    );
    if (ok == true && mounted) {
      // Keep the balance field in step, or a later Save would write the old
      // figure back and silently reverse the entry just recorded.
      setState(() {
        _balance.text = groupedAmount(_live.balance, decimals: _decimals);
      });
    }
  }

  /// The holding as stored now, so the sheet reflects entries just recorded.
  Holding _find(List<Holding> all) => all.firstWhere(
    (x) => x.fundId == widget.holding.fundId,
    orElse: () => widget.holding,
  );

  Holding get _live => _find(ref.read(holdingsProvider));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = _find(ref.watch(holdingsProvider));
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
            t('portfolio.manage.was', {'amt': money(h.currency, h.balance)}),
            style: TextStyle(color: c.faint, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _record(withdrawal: false),
                  icon: Icon(Icons.add_rounded, size: 18, color: c.up),
                  label: Text(t('ledger.recordDeposit')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.text,
                    side: BorderSide(color: c.line2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: h.balance > 0
                      ? () => _record(withdrawal: true)
                      : null,
                  icon: Icon(Icons.remove_rounded, size: 18, color: c.down),
                  label: Text(t('ledger.recordWithdrawal')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.text,
                    side: BorderSide(color: c.line2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          if (h.isVerified) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 16, color: c.up),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t('ledger.verified', {'label': h.anchor!.label}),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (h.transactions.isNotEmpty) _Activity(holding: h),
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

/// The holding's ledger, newest first: what went in, what came out, and who
/// recorded it. Entries the user typed can be deleted; statement lines cannot.
class _Activity extends ConsumerWidget {
  const _Activity({required this.holding});

  final Holding holding;

  static const _mon = [
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final items = [...holding.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final shown = items.take(8).toList();
    final decimals = holding.currency == 'USD' ? 2 : 0;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('ledger.activity'),
            style: TextStyle(color: c.faint, fontSize: 12),
          ),
          const SizedBox(height: 4),
          for (final x in shown)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(
                            x.isWithdrawal
                                ? 'ledger.withdrawal'
                                : 'ledger.deposit',
                          ),
                          style: TextStyle(color: c.text, fontSize: 14),
                        ),
                        Text(
                          '${x.date.day} ${_mon[x.date.month - 1]} ${x.date.year} \u00b7 ${t(x.fromStatement ? 'ledger.fromStatement' : 'ledger.fromYou')}',
                          style: TextStyle(color: c.faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${x.isWithdrawal ? '-' : '+'}${groupedAmount(x.amount.abs(), decimals: decimals)}',
                    style: fructaFonts.numeric(
                      color: x.isWithdrawal ? c.down : c.up,
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                  if (!x.fromStatement)
                    IconButton(
                      tooltip: t('common.remove'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => ref
                          .read(holdingsProvider.notifier)
                          .removeTxn(holding.fundId, x),
                      icon: Icon(Icons.close_rounded, size: 16, color: c.faint),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet to record a dated deposit or withdrawal. Resolves true when an
/// entry was saved.
Future<bool?> showRecordTxnSheet(
  BuildContext context, {
  required Holding holding,
  required bool withdrawal,
}) {
  final c = context.c;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: c.s1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RecordSheet(holding: holding, withdrawal: withdrawal),
  );
}

class _RecordSheet extends ConsumerStatefulWidget {
  const _RecordSheet({required this.holding, required this.withdrawal});

  final Holding holding;
  final bool withdrawal;

  @override
  ConsumerState<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<_RecordSheet> {
  late final int _decimals = widget.holding.currency == 'USD' ? 2 : 0;
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.holding.openedAt.subtract(const Duration(days: 3650)),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final v = double.tryParse(_amount.text.replaceAll(',', ''));
    if (v == null || v <= 0) {
      setState(() => _error = t('ledger.err.amount'));
      return;
    }
    final ok = await ref
        .read(holdingsProvider.notifier)
        .addTxn(widget.holding.fundId, widget.withdrawal ? -v : v, _date);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = t('ledger.err.tooMuch'));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = widget.holding;
    final d = _date;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              widget.withdrawal
                  ? 'ledger.recordWithdrawal'
                  : 'ledger.recordDeposit',
            ),
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(
              widget.withdrawal
                  ? 'ledger.withdrawalHint'
                  : 'ledger.depositHint',
            ),
            style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsInputFormatter(decimals: _decimals)],
            style: fructaFonts.numeric(color: c.text, size: 20),
            decoration: InputDecoration(
              prefixText: '${h.currency}  ',
              prefixStyle: TextStyle(color: c.muted, fontSize: 18),
              errorText: _error,
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
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('ledger.on', {
                        'date':
                            '${d.day} ${_Activity._mon[d.month - 1]} ${d.year}',
                      }),
                      style: TextStyle(color: c.text, fontSize: 15),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.faint),
                ],
              ),
            ),
          ),
          if (widget.withdrawal) ...[
            const SizedBox(height: 8),
            Text(
              t('ledger.available', {'amount': money(h.currency, h.balance)}),
              style: TextStyle(color: c.faint, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
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
        ],
      ),
    );
  }
}

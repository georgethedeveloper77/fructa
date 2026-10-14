import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../core/widgets/reveal_text.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_parser.dart';
import '../../engine/statement/statement_reader.dart';
import 'statement_controller.dart';
import 'statement_view.dart';

enum _Stage { pick, reading, locked, done, error }

/// Add a statement, unlock it if needed, read it, show what it found.
class StatementCheckPage extends ConsumerStatefulWidget {
  const StatementCheckPage({super.key});

  @override
  ConsumerState<StatementCheckPage> createState() => _StatementCheckPageState();
}

class _StatementCheckPageState extends ConsumerState<StatementCheckPage> {
  _Stage _stage = _Stage.pick;
  Uint8List? _bytes;
  String _fileName = '';
  String? _error;
  bool _wrong = false;
  bool _remember = true;
  bool _showPw = false;
  SavedStatement? _saved;
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked.isEmpty) return;
    Uint8List? bytes;
    try {
      bytes = await picked.single.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _stage = _Stage.error;
        _error = t('statement.err.unreadable');
      });
      return;
    }
    _bytes = bytes;
    _fileName = picked.single.name;
    await _read();
  }

  /// Tries remembered passwords first, or [typed] when the user entered one.
  Future<void> _read({String? typed}) async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _stage = _Stage.reading;
      _error = null;
    });
    try {
      final passwords = typed != null
          ? [typed]
          : await StatementPasswords.all();
      final read = await StatementReader.readText(bytes, passwords: passwords);
      final cfg = ref.read(remoteConfigProvider);
      final data = StatementParser.parse(read.text, extra: configManagers(cfg));
      final fund = matchFund(data, ref.read(fundsByIdProvider).values);
      final saved = await ref
          .read(statementsProvider.notifier)
          .save(data, fundId: fund?.id);
      if (data.managerKey != 'unknown') {
        if (typed != null && _remember) {
          await StatementPasswords.remember(data.managerKey, typed);
        }
        await Push.tagStatementManager(data.managerKey);
      }
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _stage = _Stage.done;
      });
    } on StatementLockedException {
      if (!mounted) return;
      setState(() {
        _wrong = typed != null;
        _stage = _Stage.locked;
      });
    } on StatementParseException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = t(e.reason);
      });
    } on StatementUnreadableException {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = t('statement.err.unreadable');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t(_stage == _Stage.done ? 'statement.titleDone' : 'statement.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: switch (_stage) {
          _Stage.pick => _PickView(onPick: _pick),
          _Stage.reading => const Center(child: CircularProgressIndicator()),
          _Stage.locked => _lockedView(context),
          _Stage.error => _ErrorView(message: _error ?? '', onRetry: _pick),
          _Stage.done => ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              StatementFindingsView(saved: _saved!),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const StatementHistoryPage(),
                  ),
                ),
                child: Text(
                  t('statement.allStatements'),
                  style: TextStyle(
                    color: c.accentInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _lockedView(BuildContext context) {
    final c = context.c;
    final hints = [
      for (final m in ref.watch(remoteConfigProvider).statementManagers)
        if (m.passwordHint != null && m.passwordHint!.isNotEmpty)
          '${m.name}: ${m.passwordHint}',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.lock_outline_rounded, size: 30, color: c.text),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t('statement.locked.title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _fileName,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        if (hints.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('statement.locked.hints'),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                for (final h in hints)
                  Text(
                    h,
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _pw,
          autofocus: true,
          obscureText: !_showPw,
          onSubmitted: (v) => v.isEmpty ? null : _read(typed: v),
          style: fructaFonts.numeric(color: c.text, size: 17),
          decoration: InputDecoration(
            labelText: t('statement.locked.password'),
            errorText: _wrong ? t('statement.locked.wrong') : null,
            filled: true,
            fillColor: c.s1,
            suffixIcon: IconButton(
              tooltip: t('statement.locked.show'),
              onPressed: () => setState(() => _showPw = !_showPw),
              icon: Icon(
                _showPw
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: c.muted,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _remember,
          activeTrackColor: c.accent,
          onChanged: (v) => setState(() => _remember = v),
          title: Text(
            t('statement.locked.remember'),
            style: TextStyle(
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            t('statement.locked.rememberSub'),
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () {
            final v = _pw.text.trim();
            if (v.isNotEmpty) _read(typed: v);
          },
          child: Text(
            t('statement.locked.unlock'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PickView extends ConsumerWidget {
  const _PickView({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final names = [
      for (final m in ref.watch(remoteConfigProvider).statementManagers) m.name,
    ];
    final checks = [
      ('statement.check.yield', 'statement.check.yieldSub'),
      ('statement.check.missing', 'statement.check.missingSub'),
      ('statement.check.tax', 'statement.check.taxSub'),
      ('statement.check.match', 'statement.check.matchSub'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          t('statement.pick.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t('statement.pick.body'),
          style: TextStyle(color: c.muted, fontSize: 14.5, height: 1.45),
        ),
        const SizedBox(height: 20),
        Material(
          color: c.s1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: c.line2, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.upload_file_rounded,
                      color: c.accentInk,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t('statement.pick.cta'),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('statement.pick.where'),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.upSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: c.up, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('statement.pick.private'),
                  style: TextStyle(color: c.text, fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          t('statement.pick.weCheck'),
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < checks.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '0${i + 1}',
                    style: fructaFonts.numeric(
                      color: c.accentInk,
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(checks[i].$1),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t(checks[i].$2),
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 12),
          RevealText(
            t('statement.pick.managers', {'names': names.join(', ')}),
            style: TextStyle(color: c.faint, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 40, color: c.muted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.text,
              side: BorderSide(color: c.line2),
            ),
            child: Text(t('statement.tryAnother')),
          ),
        ],
      ),
    );
  }
}

/// Every statement checked on this phone, newest period first.
class StatementHistoryPage extends ConsumerWidget {
  const StatementHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final list = ref.watch(statementsProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('statement.history.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StatementCheckPage())),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('statement.history.add')),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: c.down)),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    t('statement.history.empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                children: [
                  Text(
                    t('statement.history.sub', {'n': '${items.length}'}),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  for (final s in items) _HistoryRow(saved: s),
                ],
              ),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.saved});

  final SavedStatement saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final d = saved.data;
    final gap = ref
        .watch(statementAnalysisProvider(saved.id))
        .value
        ?.analysis
        .gapPts;
    final credited = ref
        .watch(statementAnalysisProvider(saved.id))
        .value
        ?.analysis
        .recentCreditedPct;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StatementDetailPage(saved: saved)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.managerName.isEmpty ? t('statement.unknownManager') : d.managerName} \u00b7 ${d.currency}',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dayLabel(d.from)} to ${dayLabel(d.to)}',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (credited != null)
                  Text(
                    '${credited.toStringAsFixed(2)}%',
                    style: fructaFonts.numeric(
                      color: c.text,
                      size: 15,
                      weight: FontWeight.w600,
                    ),
                  ),
                if (gap != null)
                  Text(
                    t('today.pts', {
                      'v': '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
                    }),
                    style: TextStyle(
                      color: gap <= -0.25 ? c.down : c.up,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One saved statement's findings, with delete.
class StatementDetailPage extends ConsumerWidget {
  const StatementDetailPage({super.key, required this.saved});

  final SavedStatement saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('statement.titleDone'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: t('common.remove'),
            onPressed: () async {
              await ref.read(statementsProvider.notifier).remove(saved.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: Icon(Icons.delete_outline_rounded, color: c.muted),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [StatementFindingsView(saved: saved)],
      ),
    );
  }
}

/// Portfolio's way in: check a statement, and the latest result when there is
/// one. Hidden while `statements.enabled` is off.
class StatementEntryCard extends ConsumerWidget {
  const StatementEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteConfigProvider).statementsEnabled) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final items =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final latest = items.isEmpty ? null : items.first;
    final gap = latest == null
        ? null
        : ref
              .watch(statementAnalysisProvider(latest.id))
              .value
              ?.analysis
              .gapPts;

    Widget row({
      required IconData icon,
      required String title,
      required String sub,
      required VoidCallback onTap,
      Color? subColor,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: c.accentInk),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      color: subColor ?? c.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.faint),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          row(
            icon: Icons.fact_check_outlined,
            title: t('statement.entry.check'),
            sub: t('statement.entry.checkSub'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatementCheckPage()),
            ),
          ),
          if (latest != null) ...[
            Divider(height: 1, color: c.line),
            row(
              icon: Icons.history_rounded,
              title: t('statement.entry.history', {'n': '${items.length}'}),
              sub: gap == null
                  ? '${latest.data.managerName} \u00b7 ${dayLabel(latest.data.to)}'
                  : t('statement.entry.latestGap', {
                      'name': latest.data.managerName,
                      'gap': '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
                    }),
              subColor: gap != null && gap <= -0.25 ? c.down : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatementHistoryPage()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

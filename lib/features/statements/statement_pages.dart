import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_parser.dart';
import '../../engine/statement/statement_reader.dart';
import '../pro/pro_widgets.dart';
import 'statement_controller.dart';
import 'statement_view.dart';

enum _Stage { pick, reading, locked, done, error }

/// One finished step of reading a statement, with an optional figure.
typedef _Step = ({String label, String value});

const _monthsShort = [
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

String _dayMon(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

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
  int _attempts = 0;
  bool _remember = true;
  bool _showPw = false;
  SavedStatement? _saved;
  final _steps = <_Step>[];
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

  /// Ticks off a reading step as it really completes.
  void _step(String label, [String value = '']) {
    if (!mounted) return;
    setState(() => _steps.add((label: label, value: value)));
  }

  /// Tries remembered passwords first, or [typed] when the user entered one.
  Future<void> _read({String? typed}) async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _stage = _Stage.reading;
      _error = null;
      _steps.clear();
    });
    try {
      final passwords = typed != null
          ? [typed]
          : await StatementPasswords.all();
      final read = await StatementReader.readText(bytes, passwords: passwords);
      _step(t('statement.step.opened'));

      final cfg = ref.read(remoteConfigProvider);
      final data = StatementParser.parse(read.text, extra: configManagers(cfg));
      _step(
        t('statement.step.found', {
          'name': data.managerName.isEmpty
              ? t('statement.unknownManager')
              : data.managerName,
        }),
        data.currency,
      );
      _step(t('statement.step.lines'), '${data.entries.length}');

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
      final months = {
        for (final e in data.entries) e.date.year * 12 + e.date.month,
      }.length;
      _step(t('statement.step.months'), '$months');

      // Let the last tick land before the findings replace it.
      if (mounted && !reduceMotion(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
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
        if (_wrong) _attempts++;
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

  void _unlock() {
    final v = _pw.text.trim();
    if (v.isNotEmpty) _read(typed: v);
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
          _Stage.reading => _ReadingView(fileName: _fileName, steps: _steps),
          _Stage.locked => _LockedView(
            fileName: _fileName,
            controller: _pw,
            wrong: _wrong,
            attempts: _attempts,
            showPw: _showPw,
            remember: _remember,
            onShowPw: () => setState(() => _showPw = !_showPw),
            onRemember: (v) => setState(() => _remember = v),
            onUnlock: _unlock,
          ),
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
}

// ── Pick ────────────────────────────────────────────────────────────────────

/// Start of a check: one line of headline, one button, privacy in a line,
/// what is checked as four tiles that open on tap, and the managers read.
/// A returning user sees their last check first, figure first.
class _PickView extends ConsumerStatefulWidget {
  const _PickView({required this.onPick});

  final VoidCallback onPick;

  @override
  ConsumerState<_PickView> createState() => _PickViewState();
}

class _PickViewState extends ConsumerState<_PickView> {
  bool _how = false;
  bool _private = false;
  final _open = <int>{};
  late final Future<List<String>> _remembered = StatementPasswords.managers();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final full = ref.watch(statementFullAccessProvider);
    final managers = ref.watch(remoteConfigProvider).statementManagers;
    final items =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final latest = items.isEmpty ? null : items.first;

    final checks = [
      (
        Icons.bar_chart_rounded,
        'statement.check.yieldShort',
        'statement.check.yieldSub',
        false,
      ),
      (
        Icons.do_not_disturb_on_outlined,
        'statement.check.missingShort',
        'statement.check.missingSub',
        false,
      ),
      (
        Icons.receipt_long_outlined,
        'statement.check.taxShort',
        'statement.check.taxSub',
        false,
      ),
      (
        Icons.link_rounded,
        'statement.check.match',
        'statement.check.matchSub',
        true,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (latest != null) ...[
          _LastCheck(saved: latest, count: items.length),
          const SizedBox(height: 22),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t(
              latest == null
                  ? 'statement.pick.titleShort'
                  : 'statement.pick.titleAgain',
            ),
            style: TextStyle(
              color: c.text,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        _Disclosure(
          label: t('statement.pick.how'),
          open: _how,
          onTap: () => setState(() => _how = !_how),
        ),
        _Reveal(
          open: _how,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              t('statement.pick.howBody'),
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: widget.onPick,
          icon: const Icon(Icons.upload_file_rounded, size: 22),
          label: Text(t('statement.pick.cta')),
        ),
        const SizedBox(height: 8),
        Text(
          t('statement.pick.where'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 16),

        // Privacy in one line; the detail opens on tap.
        Material(
          color: c.upSoft,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _private = !_private),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, color: c.up, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('statement.pick.privateShort'),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Reveal(
                    open: _private,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 6, 0, 0),
                      child: Text(
                        t('statement.pick.privateMore'),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        _Heading(t('statement.pick.weCheck')),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < checks.length; i++)
                  SizedBox(
                    width: w,
                    child: _CheckTile(
                      icon: checks[i].$1,
                      title: t(checks[i].$2),
                      sub: t(checks[i].$3),
                      locked: checks[i].$4 && !full,
                      open: _open.contains(i),
                      onTap: () => setState(() {
                        if (!_open.remove(i)) _open.add(i);
                      }),
                    ),
                  ),
              ],
            );
          },
        ),

        if (managers.isNotEmpty) ...[
          _Heading(t('statement.pick.readsFrom')),
          FutureBuilder<List<String>>(
            future: _remembered,
            builder: (context, snap) {
              final keys = snap.data ?? const <String>[];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in managers)
                    _ManagerChip(
                      name: m.name,
                      remembered: keys.contains(m.key),
                    ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              t('statement.pick.others'),
              style: TextStyle(color: c.faint, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ],
    );
  }
}

/// The last statement checked, figure first, with the way to all of them and
/// when the next one is usually out.
class _LastCheck extends ConsumerWidget {
  const _LastCheck({required this.saved, required this.count});

  final SavedStatement saved;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final d = saved.data;
    final gap = ref
        .watch(statementAnalysisProvider(saved.id))
        .value
        ?.analysis
        .gapPts;
    final day = ref
        .watch(remoteConfigProvider)
        .statementManager(d.managerKey)
        ?.releaseDay;
    DateTime? due;
    if (day != null) {
      final now = DateTime.now();
      due = DateTime(now.year, now.month, day);
      if (due.isBefore(DateTime(now.year, now.month, now.day))) {
        due = DateTime(now.year, now.month + 1, day);
      }
    }
    final name = d.managerName.isEmpty
        ? t('statement.unknownManager')
        : d.managerName;
    final under = gap != null && gap <= -0.005;
    final over = gap != null && gap >= 0.005;

    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatementDetailPage(saved: saved)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('statement.last.kicker', {
                  'name': name,
                  'month': _monthsShort[d.to.month - 1],
                }).toUpperCase(),
                style: TextStyle(
                  color: c.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              if (gap != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      '${gap > 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
                      style: fructaFonts.numeric(
                        color: under ? c.down : (over ? c.up : c.text),
                        size: 44,
                        weight: FontWeight.w600,
                        letterSpacing: -1.2,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        t(
                          under
                              ? 'statement.last.below'
                              : over
                              ? 'statement.last.above'
                              : 'statement.last.inLine',
                        ),
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Pill(
                      label: t('statement.last.all', {'n': '$count'}),
                      color: c.s2,
                      ink: c.text,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StatementHistoryPage(),
                        ),
                      ),
                    ),
                  ),
                  if (due != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Pill(
                        icon: Icons.event_outlined,
                        label: t('statement.last.due', {'date': _dayMon(due)}),
                        color: c.accentSoft,
                        ink: c.accentInk,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.ink,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color ink;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: ink),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What one check covers: a short title, its explanation on tap.
class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.locked,
    required this.open,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool locked;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      expanded: open,
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: open ? c.accent : c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 17, color: c.accentInk),
                      ),
                      const Spacer(),
                      if (locked) const ProBadge(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _Reveal(
                    open: open,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        sub,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A manager Fructa reads, with a lock when its password is remembered.
class _ManagerChip extends StatelessWidget {
  const _ManagerChip({required this.name, required this.remembered});

  final String name;
  final bool remembered;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mono = name
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.s3, shape: BoxShape.circle),
            child: Text(
              mono,
              style: TextStyle(
                color: c.text,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (remembered) ...[
            const SizedBox(width: 6),
            Semantics(
              label: t('statement.pick.remembered'),
              child: Icon(Icons.lock_outline_rounded, size: 13, color: c.up),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Reading ─────────────────────────────────────────────────────────────────

/// A document with a moving scan line, a bar that fills as steps finish, and
/// each step ticking off with its figure as it really completes.
class _ReadingView extends StatefulWidget {
  const _ReadingView({required this.fileName, required this.steps});

  final String fileName;
  final List<_Step> steps;

  @override
  State<_ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<_ReadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_scan.isAnimating) {
      _scan.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final still = reduceMotion(context);
    final progress = (widget.steps.length / 4).clamp(0.08, 1.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 104,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line2),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in const [0.7, 1.0, 0.85, 1.0, 0.6]) ...[
                        FractionallySizedBox(
                          widthFactor: f,
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: c.line2,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                if (!still)
                  AnimatedBuilder(
                    animation: _scan,
                    builder: (_, _) => Positioned(
                      left: 0,
                      right: 0,
                      top: 10 + 62 * Curves.easeInOut.transform(_scan.value),
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              c.accentSoft.withValues(alpha: 0),
                              c.accentSoft,
                            ],
                          ),
                          border: Border(
                            bottom: BorderSide(color: c.accent, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          t('statement.reading'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.fileName,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 22),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: Duration(milliseconds: still ? 0 : 400),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 4,
              backgroundColor: c.s2,
              color: c.accent,
            ),
          ),
        ),
        const SizedBox(height: 26),
        for (final s in widget.steps)
          _StepRow(key: ValueKey(s.label), step: s, still: still),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 15, color: c.up),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t('statement.reading.private'),
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One finished step: the tick pops in, the row rises into place.
class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.step, required this.still});

  final _Step step;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 450),
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.upSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 15, color: c.up),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.label,
                style: TextStyle(color: c.text, fontSize: 15),
              ),
            ),
            if (step.value.isNotEmpty)
              Text(
                step.value,
                style: fructaFonts.numeric(color: c.muted, size: 13),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Locked ──────────────────────────────────────────────────────────────────

/// Password for a locked statement. Hints per manager open on tap; a wrong
/// password shakes the field.
class _LockedView extends ConsumerStatefulWidget {
  const _LockedView({
    required this.fileName,
    required this.controller,
    required this.wrong,
    required this.attempts,
    required this.showPw,
    required this.remember,
    required this.onShowPw,
    required this.onRemember,
    required this.onUnlock,
  });

  final String fileName;
  final TextEditingController controller;
  final bool wrong;

  /// Bumps on every wrong try, so the shake replays each time.
  final int attempts;
  final bool showPw;
  final bool remember;
  final VoidCallback onShowPw;
  final ValueChanged<bool> onRemember;
  final VoidCallback onUnlock;

  @override
  ConsumerState<_LockedView> createState() => _LockedViewState();
}

class _LockedViewState extends ConsumerState<_LockedView> {
  bool _hints = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hints = [
      for (final m in ref.watch(remoteConfigProvider).statementManagers)
        if (m.passwordHint != null && m.passwordHint!.isNotEmpty)
          (m.name, m.passwordHint!),
    ];
    final still = reduceMotion(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: c.s2,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 24,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('statement.locked.title'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('statement.locked.sub'),
                      style: TextStyle(color: c.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.fileName,
                      style: TextStyle(color: c.faint, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Keyed by attempt, so each wrong try replays the shake.
              TweenAnimationBuilder<double>(
                key: ValueKey(widget.attempts),
                tween: Tween(begin: widget.wrong && !still ? 0 : 1, end: 1),
                duration: const Duration(milliseconds: 420),
                builder: (_, v, child) => Transform.translate(
                  offset: Offset(math.sin(v * math.pi * 4) * 6 * (1 - v), 0),
                  child: child,
                ),
                child: TextField(
                  controller: widget.controller,
                  autofocus: true,
                  obscureText: !widget.showPw,
                  onSubmitted: (_) => widget.onUnlock(),
                  style: fructaFonts.numeric(color: c.text, size: 17),
                  decoration: InputDecoration(
                    labelText: t('statement.locked.password'),
                    errorText: widget.wrong
                        ? t('statement.locked.wrong')
                        : null,
                    filled: true,
                    fillColor: c.s1,
                    suffixIcon: IconButton(
                      tooltip: t('statement.locked.show'),
                      onPressed: widget.onShowPw,
                      icon: Icon(
                        widget.showPw
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: c.muted,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.accent, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.down, width: 1.5),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.down, width: 1.5),
                    ),
                  ),
                ),
              ),
              if (hints.isNotEmpty) ...[
                _Disclosure(
                  label: t('statement.locked.hints'),
                  open: _hints,
                  onTap: () => setState(() => _hints = !_hints),
                ),
                _Reveal(
                  open: _hints,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.s1,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < hints.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              border: i == 0
                                  ? null
                                  : Border(top: BorderSide(color: c.line)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hints[i].$1,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    hints[i].$2,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('statement.locked.remember'),
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('statement.locked.rememberShort'),
                            style: TextStyle(color: c.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    fructaToggle(
                      value: widget.remember,
                      onChanged: widget.onRemember,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: widget.onUnlock,
            child: Text(
              t('statement.locked.unlock'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared pieces ───────────────────────────────────────────────────────────

/// Accent text that opens a section, with a chevron that turns.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.accentInk,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: c.accentInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [child] when [open], growing into place.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: Duration(milliseconds: reduceMotion(context) ? 0 : 220),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topLeft,
    child: open ? child : const SizedBox(width: double.infinity),
  );
}

/// Small caps heading over a block.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.c.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );
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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.description_outlined, size: 24, color: c.muted),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onRetry,
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

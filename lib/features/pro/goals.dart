import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/portfolio_math.dart';
import '../statements/statement_controller.dart';

/// A savings target with a date, drawing on some or all of the user's holdings.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.target,
    required this.by,
    this.fundIds = const [],
    this.monthly = 0,
  });

  final String id;
  final String name;

  /// In KES.
  final double target;
  final DateTime by;

  /// Holdings that count towards it; empty means the whole portfolio.
  final List<String> fundIds;

  /// Planned top-up each month, KES.
  final double monthly;

  Goal copyWith({double? monthly}) => Goal(
    id: id,
    name: name,
    target: target,
    by: by,
    fundIds: fundIds,
    monthly: monthly ?? this.monthly,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'target': target,
    'by': by.toIso8601String(),
    'funds': fundIds,
    'monthly': monthly,
  };

  static Goal fromMap(Map m) => Goal(
    id: m['id'] as String,
    name: m['name'] as String,
    target: (m['target'] as num).toDouble(),
    by: DateTime.parse(m['by'] as String),
    fundIds: ((m['funds'] as List?) ?? const []).cast<String>(),
    monthly: ((m['monthly'] as num?) ?? 0).toDouble(),
  );
}

/// Goals kept on the phone, in their own Hive box opened on first use.
class GoalsNotifier extends Notifier<List<Goal>> {
  static const _boxName = 'goals';

  @override
  List<Goal> build() {
    if (!Hive.isBoxOpen(_boxName)) {
      Hive.openBox(_boxName).then((_) => ref.invalidateSelf());
      return const [];
    }
    return [
      for (final v in Hive.box(_boxName).values)
        Goal.fromMap(jsonDecode(v as String) as Map),
    ]..sort((a, b) => a.by.compareTo(b.by));
  }

  Future<Box> _box() async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  Future<void> save(Goal g) async {
    await (await _box()).put(g.id, jsonEncode(g.toMap()));
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await (await _box()).delete(id);
    ref.invalidateSelf();
  }
}

final goalsProvider = NotifierProvider<GoalsNotifier, List<Goal>>(
  GoalsNotifier.new,
);

/// Where a goal stands and where it is heading.
class GoalProgress {
  const GoalProgress({
    required this.saved,
    required this.ratePct,
    required this.usesCredited,
    required this.projected,
    required this.needMonthly,
    required this.months,
  });

  /// KES now, across the linked holdings.
  final double saved;

  /// Net annual rate used for the projection, in percent.
  final double ratePct;

  /// The rate comes from what statements show was actually credited.
  final bool usesCredited;

  /// KES at the goal date with the planned top-up.
  final double projected;

  /// Top-up a month that would reach the target exactly, KES (0 when on track).
  final double needMonthly;
  final int months;
}

/// Projects a goal at the rate the user is really paid. For a holding with a
/// checked statement that is the credited rate (net of tax); otherwise the
/// fund's published rate net of tax. Rates are weighted by each holding's value.
final goalProgressProvider = Provider.autoDispose.family<GoalProgress, Goal>((
  ref,
  g,
) {
  final funds = ref.watch(fundsByIdProvider);
  final fx = ref.watch(usdKesProvider);
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final statements =
      ref.watch(statementsProvider).value ?? const <SavedStatement>[];

  var saved = 0.0;
  var weighted = 0.0;
  var credited = false;
  for (final h in ref.watch(holdingsProvider)) {
    if (g.fundIds.isNotEmpty && !g.fundIds.contains(h.fundId)) continue;
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    final v = PortfolioMath.value(
      h,
      ratePercent: s?.ratePercent,
      taxFree: s?.taxFree ?? false,
      usdKes: fx,
    ).valueKes;
    if (v == null || v <= 0) continue;
    double? rate;
    final st = statements.where((x) => x.fundId == h.fundId).firstOrNull;
    if (st != null) {
      final a = ref.watch(statementAnalysisProvider(st.id)).value?.analysis;
      if (a?.recentCreditedPct != null) {
        rate = a!.recentCreditedPct! * (1 - wht / 100);
        credited = true;
      }
    }
    final f = funds[h.fundId];
    rate ??= s?.ratePercent == null
        ? 0
        : ((s!.taxFree || !(f?.whtStillDue ?? true))
              ? s.ratePercent!
              : s.ratePercent! * (1 - wht / 100));
    saved += v;
    weighted += v * rate;
  }
  final ratePct = saved > 0 ? weighted / saved : 0.0;

  final now = DateTime.now();
  final months = math.max(
    0,
    (g.by.year - now.year) * 12 + g.by.month - now.month,
  );
  final r = ratePct / 100 / 12;
  final grow = math.pow(1 + r, months).toDouble();
  final annuity = r == 0 ? months.toDouble() : (grow - 1) / r;
  final projected = saved * grow + g.monthly * annuity;
  final need = annuity <= 0
      ? 0.0
      : math.max(0.0, (g.target - saved * grow) / annuity);

  return GoalProgress(
    saved: saved,
    ratePct: ratePct,
    usesCredited: credited,
    projected: projected,
    needMonthly: need,
    months: months,
  );
});

const _mon = [
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
String _monthYear(DateTime d) => '${_mon[d.month - 1]} ${d.year}';

/// Every goal, with a ring and a one-line verdict each.
class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final goals = ref.watch(goalsProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('goals.title'),
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
        onPressed: () => showGoalSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('goals.add')),
      ),
      body: goals.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  t('goals.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 15, height: 1.45),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [for (final g in goals) _GoalCard(goal: g)],
            ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final p = ref.watch(goalProgressProvider(goal));
    final on = p.projected >= goal.target;
    final pct = goal.target <= 0
        ? 0.0
        : (p.saved / goal.target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GoalDetailPage(goalId: goal.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: CustomPaint(
                    painter: _Ring(pct, c.dataInk(c.up), c.s2, 6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('goals.cardSub', {
                          'target': money('KES', goal.target),
                          'by': _monthYear(goal.by),
                        }),
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  t(on ? 'goals.onTrack' : 'goals.behind'),
                  style: TextStyle(
                    color: on ? c.up : c.down,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/// One goal: ring, verdict, top-up and the numbers behind the projection.
class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final goal = ref
        .watch(goalsProvider)
        .where((g) => g.id == goalId)
        .firstOrNull;
    if (goal == null) return Scaffold(backgroundColor: c.bg);
    final p = ref.watch(goalProgressProvider(goal));
    final on = p.projected >= goal.target;
    final pct = goal.target <= 0
        ? 0.0
        : (p.saved / goal.target).clamp(0.0, 1.0);

    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(
            value,
            style: fructaFonts.numeric(
              color: color,
              size: 15,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        actions: [
          IconButton(
            tooltip: t('common.remove'),
            onPressed: () async {
              await ref.read(goalsProvider.notifier).remove(goal.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: Icon(Icons.delete_outline_rounded, color: c.muted),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            goal.name,
            style: TextStyle(
              color: c.text,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('goals.detailSub', {
              'target': money('KES', goal.target),
              'by': _monthYear(goal.by),
            }),
            style: TextStyle(color: c.muted, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(190, 190),
                    painter: _Ring(pct, c.dataInk(c.up), c.s2, 14),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(pct * 100).round()}%',
                        style: fructaFonts.numeric(
                          color: c.text,
                          size: 36,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        t('goals.saved'),
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: on ? c.upSoft : c.downSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(on ? 'goals.onTrackTag' : 'goals.behindTag'),
                  style: TextStyle(
                    color: on ? c.up : c.down,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  on
                      ? t('goals.onTrackLine', {
                          'spare': money('KES', p.projected - goal.target),
                        })
                      : t('goals.behindLine', {
                          'need': money(
                            'KES',
                            (p.needMonthly / 100).ceil() * 100.0,
                          ),
                        }),
                  style: TextStyle(color: c.text, fontSize: 15, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            t('goals.topUp'),
            style: TextStyle(color: c.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in <double>{0, 2000, 5000, 10000, goal.monthly})
                ChoiceChip(
                  label: Text(v == 0 ? t('goals.none') : money('KES', v)),
                  selected: goal.monthly == v,
                  onSelected: (_) => ref
                      .read(goalsProvider.notifier)
                      .save(goal.copyWith(monthly: v)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              stat(t('goals.statSaved'), money('KES', p.saved), c.text),
              stat(
                t('goals.statProjected', {'by': _monthYear(goal.by)}),
                money('KES', p.projected),
                on ? c.up : c.down,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat(
                t('goals.statRate'),
                '${p.ratePct.toStringAsFixed(2)}%',
                c.text,
              ),
              stat(t('goals.statMonths'), '${p.months}', c.text),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            t(p.usesCredited ? 'goals.rateCredited' : 'goals.ratePublished'),
            style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _Ring old) =>
      old.value != value || old.color != color;
}

/// New goal: name, amount, date, which holdings count, monthly top-up.
Future<void> showGoalSheet(BuildContext context) {
  final c = context.c;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.s1,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _GoalSheet(),
  );
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet();

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  DateTime _by = DateTime(DateTime.now().year + 1, DateTime.now().month);
  final Set<String> _funds = {};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (_name.text.trim().isEmpty || amount == null || amount <= 0) {
      setState(() => _error = t('goals.err'));
      return;
    }
    await ref
        .read(goalsProvider.notifier)
        .save(
          Goal(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: _name.text.trim(),
            target: amount,
            by: _by,
            fundIds: _funds.toList(),
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final funds = ref.watch(fundsByIdProvider);
    final holdings = ref
        .watch(holdingsProvider)
        .where((h) => !h.isSacco)
        .toList();
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
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
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('goals.new'),
              style: TextStyle(
                color: c.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: deco(t('goals.name')),
              style: TextStyle(color: c.text),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter(decimals: 0)],
              decoration: deco(t('goals.amount')).copyWith(prefixText: 'KES  '),
              style: fructaFonts.numeric(color: c.text, size: 17),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.line2),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _by,
                  firstDate: DateTime.now().add(const Duration(days: 31)),
                  lastDate: DateTime(DateTime.now().year + 30),
                );
                if (picked != null) setState(() => _by = picked);
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(t('goals.by', {'date': _monthYear(_by)})),
            ),
            if (holdings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                t('goals.which'),
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in holdings)
                    FilterChip(
                      label: Text(funds[h.fundId]?.name ?? h.fundId),
                      selected: _funds.contains(h.fundId),
                      onSelected: (v) => setState(
                        () =>
                            v ? _funds.add(h.fundId) : _funds.remove(h.fundId),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                t('goals.whichHint'),
                style: TextStyle(color: c.faint, fontSize: 11.5),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.down, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _save,
              child: Text(t('goals.create')),
            ),
          ],
        ),
      ),
    );
  }
}

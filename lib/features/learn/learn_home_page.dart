import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/learn.dart';
import '../../data/snapshot_providers.dart';
import 'learn_progress.dart';
import 'lesson_player.dart';

/// Learn home — matches fructa_learn_mock: "Money, decoded" header + streak/XP,
/// a level hero with a progress track, unit paths of ring nodes (done / active
/// with a bob / locked) on a per-unit accent, and locked units teased as
/// "Up next" cards. Lessons unlock in order; a unit unlocks when its
/// prerequisite unit is fully done.
class LearnHomePage extends ConsumerWidget {
  const LearnHomePage({super.key});

  static const _levelTitles = [
    'Just getting started',
    'Getting the basics',
    'Rate reader',
    'Yield savvy',
    'Money master',
  ];

  LearnUnit? _unitById(LearnContent c, String? id) {
    if (id == null) return null;
    for (final u in c.units) {
      if (u.id == id) return u;
    }
    return null;
  }

  bool _unlocked(LearnContent c, LearnUnit u, LearnProgress p) {
    if (u.unlockAfter == null) return true;
    final prereq = _unitById(c, u.unlockAfter);
    return prereq == null || prereq.lessons.every((l) => p.isDone(l.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final content = ref.watch(learnProvider);
    final progress = ref.watch(learnProgressProvider);

    if (content.isEmpty) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: _bar(context),
        body: const _Empty(),
      );
    }

    final unlocked = content.units.where((u) => _unlocked(content, u, progress));
    final locked =
        content.units.where((u) => !_unlocked(content, u, progress)).toList();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _bar(context),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _Header(streak: progress.streak, xp: progress.xp),
          _LevelHero(
            content: content,
            progress: progress,
            titles: _levelTitles,
            nextLocked: locked.isEmpty ? null : locked.first,
          ),
          for (final u in unlocked)
            _UnitPath(unit: u, progress: progress),
          if (locked.isNotEmpty) _UpNext(units: locked),
        ],
      ),
    );
  }

  PreferredSizeWidget _bar(BuildContext context) => AppBar(
        backgroundColor: context.c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: context.c.text,
        elevation: 0,
      );
}

// ── accent name → palette (central fructaAccent colours) ──────────────────────
fructaAccent _accent(String? name) => switch (name) {
      'sky' => fructaAccent.sky,
      'emerald' => fructaAccent.emerald,
      'iris' => fructaAccent.iris,
      'amber' => fructaAccent.amber,
      _ => fructaAccent.gold,
    };

// ── Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.streak, required this.xp});
  final int streak;
  final int xp;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LEARN',
                    style: TextStyle(
                        color: c.faint,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Money, decoded',
                    style: TextStyle(
                        color: c.text,
                        fontSize: 23,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _stat(context, Icons.local_fire_department_rounded, '$streak', c.accent),
          const SizedBox(width: 8),
          _stat(context, Icons.bolt_rounded, '$xp', c.up),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String v, Color color) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(v,
            style: TextStyle(
                color: color,
                fontFamily: fructaFonts.mono,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Level hero ───────────────────────────────────────────────────────────────
class _LevelHero extends StatelessWidget {
  const _LevelHero({
    required this.content,
    required this.progress,
    required this.titles,
    required this.nextLocked,
  });
  final LearnContent content;
  final LearnProgress progress;
  final List<String> titles;
  final LearnUnit? nextLocked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = content.units.expand((u) => u.lessons).toList();
    final total = all.length;
    final done = all.where((l) => progress.isDone(l.id)).length;
    final pct = total == 0 ? 0.0 : done / total;
    final level = (pct >= 1)
        ? 4
        : (pct >= 0.66)
            ? 3
            : (pct >= 0.33)
                ? 2
                : (pct > 0)
                    ? 1
                    : 0;
    final sky = fructaAccent.sky.color;
    final iris = fructaAccent.iris.color;

    final headline = pct >= 1
        ? "You've cleared every lesson."
        : (done == 0
            ? 'Start with the basics of how money grows.'
            : "You're getting the hang of yields.");
    final sub = nextLocked != null
        ? 'Finish this unit to unlock ${nextLocked!.title}.'
        : (pct >= 1 ? 'More units are on the way.' : 'Keep the streak going.');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sky.withValues(alpha: 0.16), iris.withValues(alpha: 0.10)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LEVEL ${level + 1} \u00b7 ${titles[level]}'.toUpperCase(),
              style: TextStyle(
                  color: sky,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(headline,
              style: TextStyle(
                  color: c.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(children: [
              Container(height: 8, color: c.s3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [sky, iris])),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$done of $total lessons',
                  style: TextStyle(color: c.faint, fontSize: 11)),
              Text('${(pct * 100).round()}%',
                  style: TextStyle(color: c.faint, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Unit path ────────────────────────────────────────────────────────────────
class _UnitPath extends StatelessWidget {
  const _UnitPath({required this.unit, required this.progress});
  final LearnUnit unit;
  final LearnProgress progress;

  static const _wave = [-44.0, 40.0, -22.0, 46.0, -10.0];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final acc = _accent(unit.accent);
    final lessons = unit.lessons;
    final done = lessons.where((l) => progress.isDone(l.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 22, 20, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$done of ${lessons.length} done'.toUpperCase(),
                  style: TextStyle(
                      color: acc.color,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(unit.title,
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
              if (unit.subtitle != null) ...[
                const SizedBox(height: 3),
                Text(unit.subtitle!,
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Column(
              children: [
                for (var i = 0; i < lessons.length; i++) ...[
                  if (i > 0)
                    _Connector(done: progress.isDone(lessons[i - 1].id)),
                  Transform.translate(
                    offset: Offset(_wave[i % _wave.length], 0),
                    child: _LessonNode(
                      lesson: lessons[i],
                      done: progress.isDone(lessons[i].id),
                      unlocked: i == 0 || progress.isDone(lessons[i - 1].id),
                      accent: acc.color,
                      ink: acc.onColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 3,
      height: 22,
      decoration: BoxDecoration(
        color: done ? c.up : c.line2,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Lesson node (ring + bobbing face) ────────────────────────────────────────
class _LessonNode extends StatefulWidget {
  const _LessonNode({
    required this.lesson,
    required this.done,
    required this.unlocked,
    required this.accent,
    required this.ink,
  });
  final LearnLesson lesson;
  final bool done;
  final bool unlocked;
  final Color accent;
  final Color ink;

  @override
  State<_LessonNode> createState() => _LessonNodeState();
}

class _LessonNodeState extends State<_LessonNode>
    with SingleTickerProviderStateMixin {
  AnimationController? _bob;

  bool get _active => widget.unlocked && !widget.done;

  @override
  void initState() {
    super.initState();
    if (_active) {
      _bob = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ringColor =
        widget.done ? c.up : (widget.unlocked ? widget.accent : c.s3);
    final faceColors = widget.done
        ? [c.up, c.up.withValues(alpha: 0.72)]
        : (widget.unlocked
            ? [widget.accent, widget.accent.withValues(alpha: 0.72)]
            : [c.s3, c.s3]);
    final iconColor = widget.done
        ? c.bg
        : (widget.unlocked ? widget.ink : c.faint);
    final icon = widget.done
        ? Icons.check_rounded
        : (widget.unlocked ? Icons.bolt_rounded : Icons.lock_rounded);

    Widget face = Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: faceColors,
        ),
        boxShadow: _active
            ? [
                BoxShadow(
                    color: widget.accent.withValues(alpha: 0.32),
                    blurRadius: 22,
                    spreadRadius: 1)
              ]
            : null,
      ),
      child: Icon(icon, color: iconColor, size: 25),
    );

    if (_bob != null) {
      face = AnimatedBuilder(
        animation: _bob!,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -4 * Curves.easeInOut.transform(_bob!.value)),
          child: child,
        ),
        child: face,
      );
    }

    return InkWell(
      onTap: (widget.done || widget.unlocked)
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => LessonPlayer(lesson: widget.lesson)),
              )
          : null,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(72, 72),
                    painter: _RingPainter(color: ringColor, bg: c.s3),
                  ),
                  face,
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 150,
              child: Text(
                widget.lesson.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: (widget.done || widget.unlocked) ? c.text : c.faint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.bg});
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.bg != bg;
}

// ── Up next (locked units) ───────────────────────────────────────────────────
class _UpNext extends StatelessWidget {
  const _UpNext({required this.units});
  final List<LearnUnit> units;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UP NEXT',
              style: TextStyle(
                  color: c.faint,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final u in units)
            Container(
              margin: const EdgeInsets.only(bottom: 11),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line2),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.s3,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_graph_rounded,
                      color: _accent(u.accent).color, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.title,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      if (u.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(u.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.muted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.lock_rounded, color: c.faint, size: 16),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.line2),
              ),
              child: Icon(Icons.school_outlined, color: c.accent, size: 34),
            ),
            const SizedBox(height: 18),
            Text('Lessons are on the way',
                style: TextStyle(
                    color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Short, plain-language lessons on MMFs, yields and tax — landing '
              'here soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

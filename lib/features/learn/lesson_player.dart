import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/models/learn.dart';
import '../../data/providers.dart';
import '../company/company_page.dart';
import 'learn_progress.dart';

/// Plays one lesson: its steps in order, then an XP win screen. Explainer,
/// interactive (earn slider) and quiz are the step kinds; a lesson's fund (if
/// set) powers the live-rate badge and the "See it live" hand-off.
class LessonPlayer extends ConsumerStatefulWidget {
  const LessonPlayer({super.key, required this.lesson});
  final LearnLesson lesson;

  @override
  ConsumerState<LessonPlayer> createState() => _LessonPlayerState();
}

class _LessonPlayerState extends ConsumerState<LessonPlayer> {
  int _i = 0;
  final Set<int> _answered = {};

  List<LearnStep> get _steps => widget.lesson.steps;
  bool get _isWin => _i >= _steps.length;

  void _next() {
    if (_i < _steps.length) setState(() => _i++);
  }

  Future<void> _finish({required bool seeLive, Fund? fund}) async {
    await ref
        .read(learnProgressProvider.notifier)
        .completeLesson(widget.lesson.id, widget.lesson.xp);
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (seeLive && fund != null) {
      nav.push(MaterialPageRoute(builder: (_) => CompanyPage(fund)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fund = widget.lesson.fundId != null
        ? ref.watch(fundsByIdProvider)[widget.lesson.fundId]
        : null;

    final total = _steps.length + 1;
    final progress = ((_i + 1) / total).clamp(0.0, 1.0);
    final step = _isWin ? null : _steps[_i];
    final quizPending =
        step != null && step.kind == LearnStepKind.quiz && !_answered.contains(_i);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Close + progress
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 18, 8),
              child: Row(children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.s2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line2),
                    ),
                    child: Icon(Icons.close_rounded, color: c.muted, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: c.s3,
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: _isWin
                  ? _WinView(
                      lesson: widget.lesson,
                      streak: ref.watch(learnProgressProvider).streak + 1,
                      fund: fund,
                      onComplete: () => _finish(seeLive: false, fund: fund),
                      onSeeLive: fund == null
                          ? null
                          : () => _finish(seeLive: true, fund: fund),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
                      child: _StepView(
                        key: ValueKey(step!.id),
                        step: step,
                        fund: fund,
                        onAnswered: () => setState(() => _answered.add(_i)),
                      ),
                    ),
            ),
            if (!_isWin)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: quizPending ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      disabledBackgroundColor: c.s3,
                      disabledForegroundColor: c.faint,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    child: Text(_i == _steps.length - 1 ? 'Finish' : 'Continue'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Step view (dispatch by kind) ────────────────────────────────────────────

class _StepView extends StatelessWidget {
  const _StepView({
    super.key,
    required this.step,
    required this.fund,
    required this.onAnswered,
  });
  final LearnStep step;
  final Fund? fund;
  final VoidCallback onAnswered;

  @override
  Widget build(BuildContext context) {
    switch (step.kind) {
      case LearnStepKind.explainer:
        return _Explainer(step: step, fund: fund);
      case LearnStepKind.interactive:
        return _Interactive(step: step, fund: fund);
      case LearnStepKind.quiz:
        return _QuizView(step: step, onAnswered: onAnswered);
      case LearnStepKind.image:
        return _NetImage(
            url: step.payload['url'] as String?,
            caption: step.payload['caption'] as String?);
      case LearnStepKind.chart:
        return _ChartView(spec: step.payload);
      case LearnStepKind.unknown:
        return const SizedBox.shrink();
    }
  }
}

List<String> _paragraphs(String? body) => (body ?? '')
    .split(RegExp(r'\n+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

class _LiveBadge extends StatelessWidget {
  const _LiveBadge(this.fund);
  final Fund fund;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rate = fund.currentRate;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.up, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(fund.name,
            style: TextStyle(
                color: c.accent,
                fontFamily: fructaFonts.mono,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        if (rate != null) ...[
          const SizedBox(width: 8),
          Text('${rate.toStringAsFixed(2)}% \u00b7 live',
              style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.step, required this.fund});
  final LearnStep step;
  final Fund? fund;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fund != null) _LiveBadge(fund!),
        if (step.title != null)
          Text(step.title!,
              style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final p in _paragraphs(step.body)) ...[
          Text(p,
              style: TextStyle(color: c.muted, fontSize: 15, height: 1.6)),
          const SizedBox(height: 12),
        ],
        if (step.note != null)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: c.accent, width: 3)),
            ),
            child: Text(step.note!,
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.55)),
          ),
        _Media(payload: step.payload),
      ],
    );
  }
}

class _Interactive extends StatefulWidget {
  const _Interactive({required this.step, required this.fund});
  final LearnStep step;
  final Fund? fund;
  @override
  State<_Interactive> createState() => _InteractiveState();
}

class _InteractiveState extends State<_Interactive> {
  late double _amt = widget.step.initial ?? 10000;

  double get _rate => widget.step.rate ?? widget.fund?.currentRate ?? 0;
  bool get _taxable => !(widget.fund?.taxFree ?? false);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final min = widget.step.min ?? 1000;
    final max = widget.step.max ?? 500000;
    final kept = _amt * (_rate / 100) * (_taxable ? 0.85 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.step.title != null)
          Text(widget.step.title!,
              style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final p in _paragraphs(widget.step.body))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(p,
                style: TextStyle(color: c.muted, fontSize: 14.5, height: 1.55)),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: c.s2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(money('KES', kept),
                        style: TextStyle(
                            color: c.up,
                            fontFamily: fructaFonts.mono,
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                    Text('kept after tax \u00b7 1 year',
                        style: TextStyle(color: c.faint, fontSize: 11.5)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money('KES', _amt),
                        style: TextStyle(
                            color: c.text,
                            fontFamily: fructaFonts.mono,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    Text('you put in',
                        style: TextStyle(color: c.faint, fontSize: 11.5)),
                  ]),
                ],
              ),
              Slider(
                value: _amt.clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) => setState(() => _amt = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuizView extends StatefulWidget {
  const _QuizView({required this.step, required this.onAnswered});
  final LearnStep step;
  final VoidCallback onAnswered;
  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final opts = widget.step.options;
    final answered = _picked != null;
    final correct = answered && opts[_picked!].correct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK CHECK',
            style: TextStyle(
                color: c.faint,
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (widget.step.prompt != null)
          Text(widget.step.prompt!,
              style: TextStyle(
                  color: c.text,
                  fontSize: 19,
                  height: 1.25,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (var i = 0; i < opts.length; i++)
          _Option(
            text: opts[i].text,
            state: !answered
                ? _OptState.idle
                : (opts[i].correct
                    ? _OptState.correct
                    : (i == _picked ? _OptState.wrong : _OptState.idle)),
            onTap: answered
                ? null
                : () {
                    setState(() => _picked = i);
                    widget.onAnswered();
                  },
          ),
        if (answered) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (correct ? c.up : c.down).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (correct ? c.up : c.down).withValues(alpha: 0.35)),
            ),
            child: Text(
              (correct ? widget.step.explainOk : widget.step.explainNo) ??
                  (correct ? 'Correct.' : 'Not quite.'),
              style: TextStyle(
                  color: correct ? c.up : c.down,
                  fontSize: 13,
                  height: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

enum _OptState { idle, correct, wrong }

class _Option extends StatelessWidget {
  const _Option({required this.text, required this.state, required this.onTap});
  final String text;
  final _OptState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (border, fill, dotColor, dotIcon) = switch (state) {
      _OptState.correct => (c.up, c.up.withValues(alpha: 0.10), c.up, Icons.check_rounded),
      _OptState.wrong => (c.down, c.down.withValues(alpha: 0.10), c.down, Icons.close_rounded),
      _OptState.idle => (c.line2, c.s2, c.line2, null),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: border, width: state == _OptState.idle ? 1 : 1.5),
          ),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotIcon == null ? Colors.transparent : dotColor,
                border: Border.all(color: dotColor, width: 2),
              ),
              child: dotIcon == null
                  ? null
                  : Icon(dotIcon,
                      size: 14,
                      color: state == _OptState.correct
                          ? const Color(0xFF04120C)
                          : const Color(0xFF1A0605)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Win screen ──────────────────────────────────────────────────────────────

class _WinView extends StatelessWidget {
  const _WinView({
    required this.lesson,
    required this.streak,
    required this.fund,
    required this.onComplete,
    this.onSeeLive,
  });
  final LearnLesson lesson;
  final int streak;
  final Fund? fund;
  final VoidCallback onComplete;
  final VoidCallback? onSeeLive;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 116,
            height: 116,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.up, width: 8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('+${lesson.xp}',
                    style: TextStyle(
                        color: c.text,
                        fontFamily: fructaFonts.mono,
                        fontSize: 28,
                        fontWeight: FontWeight.w700)),
                Text('XP', style: TextStyle(color: c.muted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Lesson complete',
              style: TextStyle(
                  color: c.text, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Nicely done. Your streak is at $streak.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.5)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: c.up.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.up.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_fire_department_rounded, size: 16, color: c.up),
              const SizedBox(width: 8),
              Text('$streak-day streak',
                  style: TextStyle(
                      color: c.up,
                      fontFamily: fructaFonts.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const Spacer(),
          if (onSeeLive != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSeeLive,
                icon: const Icon(Icons.north_east_rounded, size: 18),
                label: Text('See ${fund?.name ?? 'it'} live'),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onComplete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.line2),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to path'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onComplete,
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  textStyle:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                child: const Text('Back to path'),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Media: optional inline image + chart inside any explainer payload ────────

class _Media extends StatelessWidget {
  const _Media({required this.payload});
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final img = payload['image'];
    final chart = payload['chart'];
    final children = <Widget>[];
    if (img is String && img.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_NetImage(
          url: img, caption: payload['image_caption'] as String?));
    }
    if (chart is Map) {
      children.add(const SizedBox(height: 8));
      children.add(_ChartView(spec: chart.cast<String, dynamic>()));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url, this.caption});
  final String? url;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(height: 160, color: c.s2),
            errorWidget: (_, __, ___) => Container(
              height: 120,
              alignment: Alignment.center,
              color: c.s2,
              child: Icon(Icons.broken_image_outlined, color: c.faint),
            ),
          ),
        ),
        if (caption != null && caption!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(caption!, style: TextStyle(color: c.faint, fontSize: 12)),
        ],
      ],
    );
  }
}

// Data-series colours are the sanctioned exception to theme-only tokens; kept
// to theme values here so charts still track light/dark.
List<Color> _palette(BuildContext context) {
  final c = context.c;
  return [c.accent, c.up, c.down, c.muted];
}

String _fmt(double v) {
  final r = v.round();
  return (v - r).abs() < 0.001 ? '$r' : v.toStringAsFixed(2);
}

class _ChartView extends StatelessWidget {
  const _ChartView({required this.spec});
  final Map<String, dynamic> spec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final type = (spec['chart'] as String?) ?? 'bars';
    final title = spec['title'] as String?;
    final caption = spec['caption'] as String?;

    final Widget chart = switch (type) {
      'line' => _LineView(spec: spec),
      'growth' => _GrowthView(spec: spec),
      _ => _BarsView(spec: spec),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty) ...[
            Text(title,
                style: TextStyle(
                    color: c.text, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
          ],
          chart,
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption,
                style: TextStyle(color: c.faint, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _BarsView extends StatelessWidget {
  const _BarsView({required this.spec});
  final Map<String, dynamic> spec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final series = ((spec['series'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (series.isEmpty) return const SizedBox.shrink();
    final unit = (spec['unit'] as String?) ?? '';
    final maxV = series
        .map((s) => (s['value'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    final safeMax = maxV <= 0 ? 1.0 : maxV;

    return Column(
      children: [
        for (final s in series) ...[
          _Bar(
            label: s['label'] as String? ?? '',
            value: (s['value'] as num?)?.toDouble() ?? 0,
            frac: ((s['value'] as num?)?.toDouble() ?? 0) / safeMax,
            color: s['highlight'] == true ? c.accent : c.muted,
            unit: unit,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.frac,
    required this.color,
    required this.unit,
  });
  final String label;
  final double value;
  final double frac;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 12.5)),
            Text('${_fmt(value)}$unit',
                style: TextStyle(
                    color: color,
                    fontFamily: fructaFonts.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Container(height: 9, color: c.s3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(height: 9, color: color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.spec});
  final Map<String, dynamic> spec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final labels =
        ((spec['labels'] as List?) ?? const []).map((e) => '$e').toList();
    final lines = ((spec['lines'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final pal = _palette(context);

    double lo = double.infinity, hi = -double.infinity;
    for (final ln in lines) {
      for (final v in (ln['values'] as List? ?? const [])) {
        final d = (v as num).toDouble();
        if (d < lo) lo = d;
        if (d > hi) hi = d;
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    }
    final span = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: LineChart(LineChartData(
            minY: lo - span * 0.12,
            maxY: hi + span * 0.12,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: labels.isNotEmpty,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(labels[i],
                          style: TextStyle(color: c.faint, fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              for (var i = 0; i < lines.length; i++)
                LineChartBarData(
                  spots: [
                    for (var x = 0;
                        x < (lines[i]['values'] as List? ?? const []).length;
                        x++)
                      FlSpot(x.toDouble(),
                          ((lines[i]['values'] as List)[x] as num).toDouble()),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: pal[i % pal.length],
                  barWidth: 2.4,
                  dotData: const FlDotData(show: false),
                ),
            ],
          )),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (var i = 0; i < lines.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 3,
                    decoration: BoxDecoration(
                        color: pal[i % pal.length],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text(lines[i]['label'] as String? ?? '',
                    style: TextStyle(color: c.muted, fontSize: 11.5)),
              ]),
          ],
        ),
      ],
    );
  }
}

class _GrowthView extends StatelessWidget {
  const _GrowthView({required this.spec});
  final Map<String, dynamic> spec;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final principal = (spec['principal'] as num?)?.toDouble() ?? 10000;
    final rate = (spec['rate'] as num?)?.toDouble() ?? 10;
    final years = (spec['years'] as num?)?.toInt() ?? 5;
    final net = spec['net'] != false;
    final r = (net ? rate * 0.85 : rate) / 100;
    final vals = [for (var y = 0; y <= years; y++) principal * pow(1 + r, y)];
    final lo = vals.first, hi = vals.last;
    final span = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${money('KES', vals.last)} in $years years',
            style: TextStyle(
                color: c.up,
                fontFamily: fructaFonts.mono,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: LineChart(LineChartData(
            minY: lo - span * 0.05,
            maxY: hi + span * 0.08,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (v, meta) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Y${v.toInt()}',
                        style: TextStyle(color: c.faint, fontSize: 10)),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var y = 0; y < vals.length; y++)
                    FlSpot(y.toDouble(), vals[y].toDouble())
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                color: c.accent,
                barWidth: 2.6,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.accent.withValues(alpha: 0.22),
                      c.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }
}

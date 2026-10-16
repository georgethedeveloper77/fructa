import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/category_colors.dart';
import '../../core/i18n.dart';
import '../../core/local_notify.dart';
import '../../core/motion/motion.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/reveal_text.dart';
import '../../data/providers.dart';
import '../company/company_page.dart';
import '../pro/pro_widgets.dart';
import '../statements/statement_controller.dart';
import '../reports/report_archive.dart';
import '../reports/report_notify.dart';
import 'wrap_chart.dart';
import 'wrap_engine.dart';

/// Opens the Weekly wrap full screen at [start].
Future<void> openWeeklyWrap(BuildContext context, {int start = 0}) =>
    openWrap(context, WrapViewer(start: start));

/// Opens any wrap (a saved week, a month) full screen.
Future<void> openWrap(BuildContext context, WrapViewer viewer) =>
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => viewer,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(
              begin: 0.96,
              end: 1.0,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );

/// Story colours. Stories are always drawn on the dark palette, in both app
/// themes, so they feel like their own full-screen space and a shared card
/// looks the same whoever posts it.
final _d = fructaColors.dark(fructaAccent.gold);

Color _tone(WrapTone t) => switch (t) {
  WrapTone.up => _d.up,
  WrapTone.down => _d.down,
  WrapTone.info => fundTypeColor('fixed_income'),
  WrapTone.tbill => categoryColor('tbill'),
  WrapTone.accent => _d.accent,
};

/// The Weekly wrap: market stories, then the user's own (Pro).
///
/// Tap the right side for the next story, the left for the previous; each
/// advances by itself after six seconds, and holding a finger down pauses it.
class WrapViewer extends ConsumerStatefulWidget {
  const WrapViewer({
    super.key,
    this.start = 0,
    this.slides,
    this.kicker,
    this.range,
    this.onPdf,
  });

  final int start;

  /// A fixed set of slides (a saved week, a month). Null plays this week's
  /// live wrap, with the Pro gate on the personal part.
  final List<WrapSlide>? slides;

  /// Header overrides for a fixed set, e.g. "October wrap".
  final String? kicker;
  final String? range;

  /// Shown as "Save as PDF" on the last slide.
  final Future<void> Function()? onPdf;

  @override
  ConsumerState<WrapViewer> createState() => _WrapViewerState();
}

class _WrapViewerState extends ConsumerState<WrapViewer>
    with SingleTickerProviderStateMixin {
  late int _i = widget.start;
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });
  final _shot = GlobalKey();
  int _count = 1;

  @override
  void initState() {
    super.initState();
    _clock.forward();
    // Opening the live wrap counts as watching it: the NEW tag clears and
    // Friday's notification is no longer needed.
    if (widget.slides == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final to = ref.read(weeklyWrapProvider).to;
        ref.read(wrapSeenProvider.notifier).mark(WrapArchive.weekId(to));
        LocalNotify.cancelIds([wrapNotificationId(to)]);
      });
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0) return;
    if (i >= _count) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _i = i);
    _clock
      ..reset()
      ..forward();
  }

  void _next() => _go(_i + 1);

  Future<void> _share() async {
    _clock.stop();
    try {
      final boundary =
          _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fructa-story.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: t('wrap.shareText')),
      );
    } finally {
      if (mounted) _clock.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wrap = ref.watch(weeklyWrapProvider);
    final unlocked = ref.watch(wrapPersonalUnlockedProvider);
    final fixed = widget.slides;
    final slides = fixed ?? [...wrap.market, if (unlocked) ...wrap.personal];
    // A free user with personal data gets one locked "Your week" slide.
    final locked = fixed == null && !unlocked && wrap.personal.isNotEmpty;
    _count = slides.length + (locked ? 1 : 0);
    if (_count == 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(context).maybePop(),
      );
      return const SizedBox.shrink();
    }
    final i = _i.clamp(0, _count - 1);
    final onLocked = locked && i == slides.length;
    final slide = onLocked ? null : slides[i];
    final tone = slide == null ? _d.accent : _tone(slide.tone);

    return Scaffold(
      backgroundColor: _d.bg,
      body: GestureDetector(
        onLongPressStart: (_) => _clock.stop(),
        onLongPressEnd: (_) => _clock.forward(),
        onTapUp: (e) {
          final w = MediaQuery.sizeOf(context).width;
          e.globalPosition.dx < w * 0.3 ? _go(i - 1) : _go(i + 1);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -1.1),
                    radius: 1.3,
                    colors: [
                      tone.withValues(alpha: 0.30),
                      _d.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress bars redraw every frame; decorative, so kept out
                  // of the semantics tree.
                  ExcludeSemantics(
                    child: _Bars(count: _count, index: i, clock: _clock),
                  ),
                  _Header(
                    kicker:
                        widget.kicker ??
                        t(
                          onLocked || (slide?.personal ?? false)
                              ? 'wrap.kickerYou'
                              : 'wrap.kickerMarket',
                        ),
                    range:
                        widget.range ??
                        t('wrap.range', {'range': _range(wrap.from, wrap.to)}),
                    onShare: onLocked ? null : _share,
                  ),
                  Expanded(
                    child: onLocked
                        ? _LockedSlide(onUnlocked: () => setState(() {}))
                        : RepaintBoundary(
                            key: _shot,
                            child: ColoredBox(
                              color: _d.bg,
                              child: _SlideBody(
                                key: ValueKey(i),
                                slide: slide!,
                                tone: tone,
                                index: i,
                                // Scrubbing a chart holds the story, like a
                                // long press does.
                                onScrub: (on) =>
                                    on ? _clock.stop() : _clock.forward(),
                              ),
                            ),
                          ),
                  ),
                  if (widget.onPdf != null && i == _count - 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _d.text,
                          foregroundColor: _d.bg,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          _clock.stop();
                          await widget.onPdf!();
                        },
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 18,
                        ),
                        label: Text(t('reports.savePdf')),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _range(DateTime a, DateTime b) => '${a.day} to ${dayLabel(b)}';
}

class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.index, required this.clock});

  final int count;
  final int index;
  final AnimationController clock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          for (var k = 0; k < count; k++) ...[
            if (k > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: k == index
                      ? AnimatedBuilder(
                          animation: clock,
                          builder: (_, _) => LinearProgressIndicator(
                            value: clock.value,
                            backgroundColor: _d.text.withValues(alpha: 0.25),
                            valueColor: AlwaysStoppedAnimation(_d.text),
                          ),
                        )
                      : ColoredBox(
                          color: _d.text.withValues(
                            alpha: k < index ? 1 : 0.25,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.kicker, required this.range, this.onShare});

  final String kicker;
  final String range;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker,
                  style: TextStyle(
                    color: _d.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(range, style: TextStyle(color: _d.muted, fontSize: 12)),
              ],
            ),
          ),
          if (onShare != null)
            IconButton(
              tooltip: t('wrap.share'),
              onPressed: onShare,
              icon: Icon(Icons.ios_share_rounded, color: _d.text),
            ),
          IconButton(
            tooltip: t('common.close'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: _d.text),
          ),
        ],
      ),
    );
  }
}

class _SlideBody extends ConsumerWidget {
  const _SlideBody({
    super.key,
    required this.slide,
    required this.tone,
    required this.index,
    required this.onScrub,
  });

  final WrapSlide slide;
  final Color tone;
  final int index;
  final ValueChanged<bool> onScrub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );
    final masked = hidden && slide.personal && slide.big.startsWith('+KES');
    final funds = ref.watch(fundsByIdProvider);
    final fund = slide.fundId == null ? null : funds[slide.fundId];
    final charted = slide.chart != WrapChartKind.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(slide.tagKey),
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slide.title,
            style: TextStyle(
              color: _d.text,
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          StretchSwap(
            value: index,
            playOnMount: true,
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _CountUp(
                masked ? 'KES \u2022\u2022\u2022\u2022' : slide.big,
                style: fructaFonts.numeric(
                  color: tone,
                  size: 64,
                  weight: FontWeight.w600,
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            slide.unit,
            style: TextStyle(color: _d.muted, fontSize: 15, height: 1.35),
          ),
          if (charted) ...[
            const SizedBox(height: 14),
            // Takes the room left on short phones, never more than 260.
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: StoryChart(
                    slide: slide,
                    tone: tone,
                    palette: _d,
                    onScrub: onScrub,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 22),
          RevealText(
            slide.line,
            collapsedLines: charted ? 2 : 3,
            style: TextStyle(color: _d.text, fontSize: 17, height: 1.45),
          ),
          if (!charted) const Spacer() else const SizedBox(height: 16),
          if (fund != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _d.text,
                  side: BorderSide(color: _d.text.withValues(alpha: 0.3)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => CompanyPage(fund))),
                child: Text(t('wrap.openFund')),
              ),
            ),
          const SizedBox(height: 10),
          // Branding inside the captured area, so every shared card says
          // where it came from.
          Text(
            t('wrap.brand'),
            style: TextStyle(color: _d.faint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// The headline figure counting up from zero to its value, keeping the sign,
/// decimals and digit grouping of the text. Text with no number, or reduced
/// motion, shows as is.
class _CountUp extends StatefulWidget {
  const _CountUp(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<_CountUp>
    with SingleTickerProviderStateMixin {
  static final _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    reduceMotion(context) ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _at(double p) {
    final m = _number.firstMatch(widget.text);
    if (m == null || p >= 1) return widget.text;
    final raw = m.group(0)!;
    final grouped = raw.contains(',');
    final clean = raw.replaceAll(',', '');
    final dot = clean.indexOf('.');
    final dp = dot < 0 ? 0 : clean.length - dot - 1;
    var out = (double.parse(clean) * p).toStringAsFixed(dp);
    if (grouped) out = _group(out);
    return widget.text.replaceRange(m.start, m.end, out);
  }

  /// Thousands separators on the whole part.
  static String _group(String s) {
    final parts = s.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) =>
        Text(_at(Curves.easeOutCubic.transform(_c.value)), style: widget.style),
  );
}

/// "Now, your week" for a free user: what Pro would show, blurred.
class _LockedSlide extends ConsumerWidget {
  const _LockedSlide({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 60, 26, 24),
      child: Column(
        children: [
          const ProBadge(),
          const SizedBox(height: 18),
          Text(
            t('wrap.locked.title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _d.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('wrap.locked.body'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _d.muted, fontSize: 15.5, height: 1.5),
          ),
          const SizedBox(height: 28),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _d.s2,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    '+KES 1,2xx',
                    style: fructaFonts.numeric(
                      color: _d.up,
                      size: 34,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('wrap.locked.earned'),
                    style: TextStyle(color: _d.text, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _d.text,
                foregroundColor: _d.bg,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                if (await ensurePro(context, ref, source: 'weekly_wrap')) {
                  onUnlocked();
                }
              },
              child: Text(
                t('wrap.locked.cta'),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Week last written to the archive this session, so the card saves once.
String? _archivedWeek;

/// Today's way in: one card for the whole week, never a row of circles.
class WeeklyWrapCard extends ConsumerWidget {
  const WeeklyWrapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final wrap = ref.watch(weeklyWrapProvider);
    if (wrap.market.isEmpty) return const SizedBox.shrink();
    final week = WrapArchive.weekId(wrap.to);
    if (_archivedWeek != week) {
      _archivedWeek = week;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(wrapArchiveProvider.notifier).saveWeek(wrap),
      );
    }
    final unlocked = ref.watch(wrapPersonalUnlockedProvider);
    final unseen = ref.watch(wrapUnseenProvider);
    final thumbs = [
      ...wrap.market.take(4),
      if (wrap.personal.isNotEmpty) wrap.personal.first,
    ];
    final total =
        wrap.market.length +
        (wrap.personal.isNotEmpty ? (unlocked ? wrap.personal.length : 1) : 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: unseen ? c.accent : c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => openWeeklyWrap(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('wrap.card.kicker', {
                          'range': '${wrap.from.day} to ${dayLabel(wrap.to)}',
                        }).toUpperCase(),
                        style: TextStyle(
                          color: c.accentInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (unseen) ...[const NewTag(), const SizedBox(width: 8)],
                    Text(
                      t('wrap.card.count', {'n': '$total'}),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var k = 0; k < thumbs.length; k++) ...[
                      if (k > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _Thumb(
                          slide: thumbs[k],
                          lockedPersonal: thumbs[k].personal && !unlocked,
                          ring: unseen,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t(unseen ? 'wrap.card.title' : 'wrap.card.watched'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: unseen ? c.accent : c.s2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        t(unseen ? 'wrap.card.play' : 'wrap.card.again'),
                        style: TextStyle(
                          color: unseen ? c.onAccent : c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small accent tag for something the user has not opened yet.
class NewTag extends StatelessWidget {
  const NewTag({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t('common.new'),
        style: TextStyle(
          color: c.onAccent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.slide,
    required this.lockedPersonal,
    this.ring = false,
  });

  final WrapSlide slide;
  final bool lockedPersonal;

  /// Accent ring around an unwatched story, like a story circle.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final tone = lockedPersonal ? _d.accent : _tone(slide.tone);
    final c = context.c;
    return AspectRatio(
      aspectRatio: 9 / 15,
      child: Container(
        foregroundDecoration: ring
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.accent, width: 2),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(7, 0, 7, 8),
        decoration: BoxDecoration(
          color: _d.bg,
          borderRadius: BorderRadius.circular(12),
          gradient: RadialGradient(
            center: const Alignment(-0.4, -1),
            radius: 1.2,
            colors: [tone.withValues(alpha: 0.38), _d.bg],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scales down to fit the thumbnail rather than cutting the number.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                lockedPersonal ? t('wrap.card.pro') : _thumbFigure(slide),
                style: fructaFonts.numeric(
                  color: tone,
                  size: 13.5,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            _FitWords(
              _hidesAmount(slide) ? t('wrap.tag.yourWeek') : t(slide.tagKey),
              style: TextStyle(
                color: _d.text.withValues(alpha: 0.8),
                fontSize: 9,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A personal story whose figure is an amount. The card lives on Today,
/// which never shows KES, so it shows the week in basis points instead.
bool _hidesAmount(WrapSlide s) => s.personal && s.big.contains('KES');

String _thumbFigure(WrapSlide s) {
  if (!_hidesAmount(s)) return s.big;
  final m = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*bps').firstMatch(s.unit);
  if (m == null) return t('wrap.card.you');
  final v = m.group(1)!;
  return t('wrap.card.bps', {
    'v': v.startsWith('-') || v.startsWith('+') ? v : '+$v',
  });
}

/// Text that wraps only between words. When the longest word is wider than
/// the space, the whole label shrinks until it fits, so "IMPROVED" never
/// breaks into "IMPROVE" and "D".
class _FitWords extends StatelessWidget {
  const _FitWords(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context);
      var widest = 0.0;
      for (final w in text.split(' ')) {
        final tp = TextPainter(
          text: TextSpan(text: w, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scale,
        )..layout();
        if (tp.width > widest) widest = tp.width;
      }
      final size = style.fontSize ?? 9;
      final fitted = widest > box.maxWidth && widest > 0
          ? size * box.maxWidth / widest * 0.98
          : size;
      return Text(text, style: style.copyWith(fontSize: fitted));
    },
  );
}

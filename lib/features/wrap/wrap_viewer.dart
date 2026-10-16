import 'dart:io';
import 'dart:math' as math;
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
import '../../core/widgets/fund_logo.dart';
import '../../core/widgets/reveal_text.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../company/company_page.dart';
import '../pro/pro_widgets.dart';
import '../statements/statement_controller.dart';
import '../reports/report_archive.dart';
import '../reports/report_notify.dart';
import 'wrap_chart.dart';
import 'wrap_engine.dart';
import 'wrap_feed.dart';

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

  /// True for the frame the story is captured in: buttons give way to the
  /// share footer and every animation shows its final state.
  bool _sharing = false;

  /// The current story's glow colour, kept for the share image's margins.
  Color _glow = _d.accent;
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
    setState(() => _sharing = true);
    try {
      // Two frames: one to lay out the share footer, one to paint it.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final shot = await boundary.toImage(pixelRatio: 3);
      final image = await _storyFrame(shot, _glow);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fructa-story.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: t('wrap.shareText')),
      );
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
        _clock.forward();
      }
    }
  }

  /// Places the captured story on a 1080 by 1920 frame, the size stories and
  /// status updates use, with the same glow filling any margin.
  static Future<ui.Image> _storyFrame(ui.Image shot, Color glow) async {
    const w = 1080.0;
    const h = 1920.0;
    const frame = Rect.fromLTWH(0, 0, w, h);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, frame);
    canvas.drawRect(frame, Paint()..color = _d.bg);
    canvas.drawRect(
      frame,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.6, -1.1),
          radius: 1.3,
          colors: [glow.withValues(alpha: 0.30), _d.bg.withValues(alpha: 0)],
        ).createShader(frame),
    );
    final scale = math.min(w / shot.width, h / shot.height);
    final dw = shot.width * scale;
    final dh = shot.height * scale;
    canvas.drawImageRect(
      shot,
      Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
      Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
    return rec.endRecording().toImage(w.toInt(), h.toInt());
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
    // The glow takes the fund's brand colour; the figures keep the story's
    // tone, so a drop still reads as a drop on any brand.
    final fundId = slide?.fundId;
    final brand = fundId == null ? null : ref.watch(brandColorProvider(fundId));
    final glow = brand == null ? tone : _d.brandOnBg(brand);
    _glow = glow;
    // Every story's history starts loading now, so each chart is ready (or
    // drawing from the snapshot line) the moment its story opens.
    for (final s in slides) {
      final id = s.fundId;
      if (id != null) ref.listen(historyProvider(id), (_, _) {});
    }

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
              child: AnimatedContainer(
                duration: Duration(
                  milliseconds: reduceMotion(context) ? 0 : 420,
                ),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -1.1),
                    radius: 1.3,
                    colors: [
                      glow.withValues(alpha: 0.30),
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
                            child: AnimatedContainer(
                              duration: Duration(
                                milliseconds: reduceMotion(context) ? 0 : 420,
                              ),
                              // The glow continues under the story, so the
                              // shared image carries it too.
                              decoration: BoxDecoration(
                                color: _d.bg,
                                gradient: RadialGradient(
                                  center: const Alignment(-0.7, -1.25),
                                  radius: 1.25,
                                  colors: [
                                    glow.withValues(alpha: 0.18),
                                    _d.bg.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                              child: _SlideBody(
                                key: ValueKey(i),
                                slide: slide!,
                                tone: tone,
                                index: i,
                                sharing: _sharing,
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
    this.sharing = false,
  });

  final WrapSlide slide;
  final Color tone;
  final int index;
  final ValueChanged<bool> onScrub;

  /// Capturing for share: final frame, no buttons, the share footer.
  final bool sharing;

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
          // The fund's own logo beside the story tag; stories about the market
          // as a whole keep the tag alone.
          Row(
            children: [
              if (fund != null) ...[
                FundLogo(
                  domain: fund.logoDomain,
                  seed: fund.manager,
                  logoUrl: ref.watch(logoUrlProvider(fund.id)),
                  brandColor: ref.watch(brandColorProvider(fund.id)),
                  size: 40,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
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
                    if (fund != null && fund.manager.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        fund.manager,
                        style: TextStyle(color: _d.muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                done: sharing,
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
                    finished: sharing,
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
          if (sharing)
            const _ShareFooter()
          else if (fund != null)
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
          if (!sharing) ...[
            const SizedBox(height: 10),
            // Branding inside the captured area, so every shared card says
            // where it came from.
            Text(
              t('wrap.brand'),
              style: TextStyle(color: _d.faint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a shared story ends with in place of its buttons: the Fructa mark,
/// the address and one line on what Fructa is.
class _ShareFooter extends StatelessWidget {
  const _ShareFooter();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/icons/logo.png', width: 24, height: 24),
        ),
        const SizedBox(width: 8),
        Text(
          t('wrap.share.site'),
          style: TextStyle(
            color: _d.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            t('wrap.share.tagline'),
            textAlign: TextAlign.right,
            style: TextStyle(color: _d.faint, fontSize: 11.5),
          ),
        ),
      ],
    ),
  );
}

/// The headline figure counting up from zero to its value, keeping the sign,
/// decimals and digit grouping of the text. Text with no number, or reduced
/// motion, shows as is.
class _CountUp extends StatefulWidget {
  const _CountUp(this.text, {required this.style, this.done = false});

  final String text;
  final TextStyle style;

  /// Shows the final value at once (the story is being captured).
  final bool done;

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
    builder: (_, _) => Text(
      widget.done ? widget.text : _at(Curves.easeOutCubic.transform(_c.value)),
      style: widget.style,
    ),
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

/// Today's way in: the week's lead story as a card, with the next two
/// stories peeking out behind it in their brand colours.
///
/// The front card is a small story: the fund's logo and brand glow, the tag,
/// the figure and its line drawing in. "+N more stories" says what else is
/// waiting. Market stories only, so Today never shows an amount. The cards
/// behind bob gently; nothing moves under reduced motion.
class WeeklyWrapCard extends ConsumerStatefulWidget {
  const WeeklyWrapCard({super.key});

  @override
  ConsumerState<WeeklyWrapCard> createState() => _WeeklyWrapCardState();
}

class _WeeklyWrapCardState extends ConsumerState<WeeklyWrapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  /// A story's glow colour: its fund's brand, lifted to show on black, or
  /// the story's own tone when it has no fund.
  Color _glowOf(WrapSlide s) {
    final id = s.fundId;
    final brand = id == null ? null : ref.watch(brandColorProvider(id));
    return brand == null ? _tone(s.tone) : _d.brandOnBg(brand);
  }

  @override
  Widget build(BuildContext context) {
    final wrap = ref.watch(weeklyWrapProvider);
    if (wrap.market.isEmpty && ref.watch(todayWrapProvider) == null) {
      return const SizedBox.shrink();
    }
    final week = WrapArchive.weekId(wrap.to);
    if (_archivedWeek != week) {
      _archivedWeek = week;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(wrapArchiveProvider.notifier).saveWeek(wrap),
      );
    }
    final unlocked = ref.watch(wrapPersonalUnlockedProvider);
    // A day when something moved leads the card until it is watched; then
    // the card goes back to the week.
    final day = ref.watch(todayWrapProvider);
    final dayNew = day != null && ref.watch(daySeenProvider) != day.id;
    final daySlides = day?.slides ?? const <WrapSlide>[];
    final dayId = day?.id ?? '';
    if (!dayNew && wrap.market.isEmpty) return const SizedBox.shrink();
    final unseen = dayNew || ref.watch(wrapUnseenProvider);
    final total =
        wrap.market.length +
        (wrap.personal.isNotEmpty ? (unlocked ? wrap.personal.length : 1) : 0);
    final lead = dayNew ? daySlides.first : wrap.market.first;
    final behind = [
      if (dayNew) ...daySlides.skip(1),
      ...wrap.market.skip(dayNew ? 0 : 1),
    ].take(2).toList();
    final now = DateTime.now();
    // The week publishes Friday evening; on that day the card says so.
    final weekLater = now.weekday == DateTime.friday && now.hour < 18;
    final kicker = dayNew
        ? t('wrap.card.today', {'date': '${_weekday(now)} ${dayLabel(now)}'})
        : t('wrap.card.kicker', {
            'range': '${wrap.from.day} to ${dayLabel(wrap.to)}',
          });
    final footer = dayNew
        ? [
            if (daySlides.length > 1)
              t('wrap.card.moreToday', {'n': '${daySlides.length - 1}'}),
            if (weekLater) t('wrap.card.weekLater'),
          ].join(' · ')
        : !unseen
        ? t('wrap.card.watched')
        : total > 1
        ? t('wrap.card.more', {'n': '${total - 1}'})
        : t('wrap.card.title');
    void open() {
      if (dayNew) {
        ref.read(daySeenProvider.notifier).mark(dayId);
        openWrap(
          context,
          WrapViewer(
            slides: daySlides,
            kicker: t('wrap.kickerToday'),
            range: dayLabel(now),
          ),
        );
      } else {
        openWeeklyWrap(context);
      }
    }

    final glow = _glowOf(lead);
    final tone = _tone(lead.tone);
    final funds = ref.watch(fundsByIdProvider);
    final fund = lead.fundId == null ? null : funds[lead.fundId];
    final calm = reduceMotion(context);

    // A card behind the front one: inset, raised, in its story's colour.
    Widget peek(int depth, WrapSlide s) => AnimatedBuilder(
      animation: _bob,
      builder: (_, child) => Positioned(
        left: 12.0 * depth,
        right: 12.0 * depth,
        top: 18.0 - 9 * depth - 3 * Curves.easeInOut.transform(_bob.value),
        bottom: 18,
        child: child!,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: _glowOf(s).withValues(alpha: depth == 1 ? 0.55 : 0.35),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Semantics(
        button: true,
        label:
            '${t('wrap.card.title')}. ${t(lead.tagKey)}, ${lead.title}, ${lead.big}',
        child: SizedBox(
          height: 300,
          child: Stack(
            children: [
              for (var k = behind.length; k >= 1; k--) peek(k, behind[k - 1]),
              Positioned(
                left: 0,
                right: 0,
                top: 18,
                bottom: 0,
                child: Material(
                  color: _d.bg,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: unseen
                          ? _d.accent.withValues(alpha: 0.7)
                          : _d.text.withValues(alpha: 0.08),
                    ),
                  ),
                  child: InkWell(
                    onTap: open,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.9, -1),
                          radius: 1.3,
                          colors: [
                            glow.withValues(alpha: 0.55),
                            _d.bg.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    kicker.toUpperCase(),
                                    style: TextStyle(
                                      color: _d.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                if (unseen) const NewTag(),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                if (fund != null) ...[
                                  FundLogo(
                                    domain: fund.logoDomain,
                                    seed: fund.manager,
                                    logoUrl: ref.watch(
                                      logoUrlProvider(fund.id),
                                    ),
                                    brandColor: ref.watch(
                                      brandColorProvider(fund.id),
                                    ),
                                    size: 36,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t(lead.tagKey),
                                        style: TextStyle(
                                          color: tone,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      Text(
                                        lead.title,
                                        style: TextStyle(
                                          color: _d.text,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      lead.big,
                                      style: fructaFonts.numeric(
                                        color: tone,
                                        size: 48,
                                        weight: FontWeight.w600,
                                        letterSpacing: -1.5,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                if (lead.series.length >= 2) ...[
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        begin: calm ? 1.0 : 0.0,
                                        end: 1.0,
                                      ),
                                      duration: const Duration(
                                        milliseconds: 1100,
                                      ),
                                      curve: Curves.easeInOutCubic,
                                      builder: (_, v, _) => SizedBox(
                                        height: 44,
                                        child: CustomPaint(
                                          painter: _CardLine(
                                            lead.series,
                                            tone,
                                            v,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    footer.isEmpty
                                        ? t('wrap.card.todayOne')
                                        : footer,
                                    style: TextStyle(
                                      color: _d.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 40,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: unseen ? _d.accent : _d.s2,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        unseen
                                            ? Icons.play_arrow_rounded
                                            : Icons.replay_rounded,
                                        size: 18,
                                        color: unseen ? _d.onAccent : _d.text,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        t(
                                          unseen
                                              ? 'wrap.card.play'
                                              : 'wrap.card.again',
                                        ),
                                        style: TextStyle(
                                          color: unseen ? _d.onAccent : _d.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _weekday(DateTime d) => _weekdays[d.weekday - 1];

/// The lead story's recent line on the card, drawn in to [progress].
class _CardLine extends CustomPainter {
  const _CardLine(this.points, this.color, this.progress);

  final List<double> points;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = points.reduce(math.min);
    final hi = points.reduce(math.max);
    final span = hi - lo < 1e-9 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = hi - lo < 1e-9
          ? size.height / 2
          : size.height - 3 - (points[i] - lo) / span * (size.height - 6);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final out = Path();
    for (final m in path.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * progress), Offset.zero);
    }
    canvas.drawPath(
      out,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CardLine old) =>
      old.progress != progress || old.color != color || old.points != points;
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

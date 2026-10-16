import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/theme.dart';
import '../../data/models/rate_history.dart';
import '../../data/providers.dart';
import 'wrap_engine.dart';

/// One plotted point. [day] is null when the series came from the snapshot
/// sparkline, which carries prints but no dates.
typedef _Pt = ({DateTime? day, double v});

/// A candidate label on the horizontal axis. [keep] labels (first, last)
/// always draw; the rest give way when they would crowd a neighbour.
typedef _XTick = ({int k, String top, String sub, bool keep});

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
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
String _dayMon(DateTime d) => '${d.day} ${_mon[d.month - 1]}';
String _signed(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';

/// Plot area inside the chart box, shared by the painter and the scrub
/// gesture so a finger maps to the point it is over.
class _Frame {
  const _Frame(this.l, this.r, this.t, this.b);

  factory _Frame.of(Size s) => _Frame(54, s.width - 24, 22, s.height - 58);

  final double l;
  final double r;
  final double t;
  final double b;
}

/// Nice axis scale: pads the data range, picks a 1, 2, 2.5 or 5 step for
/// about four ticks, and snaps both ends to that step. Ranks use whole steps
/// and never go above #1.
class _Scale {
  const _Scale(this.min, this.max, this.step, this.ticks);

  factory _Scale.nice(double lo, double hi, {bool rank = false}) {
    if (hi - lo < 1e-9) {
      final pad = rank ? 2.0 : 0.25;
      lo -= pad;
      hi += pad;
    }
    final span = hi - lo;
    lo -= span * 0.12;
    hi += span * 0.12;
    final raw = (hi - lo) / 3;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    var step = <double>[
      1,
      2,
      2.5,
      5,
      10,
    ].map((k) => k * mag).firstWhere((s) => s >= raw - 1e-12);
    if (rank) step = math.max(1.0, step.roundToDouble());
    var min = (lo / step + 1e-9).floorToDouble() * step;
    if (rank && min < 1) min = 1;
    final max = min + ((hi - min) / step - 1e-9).ceilToDouble() * step;
    final ticks = <double>[
      for (var v = min; v <= max + 1e-9; v += step)
        (v * 1e6).roundToDouble() / 1e6,
    ];
    return _Scale(min, max, step, ticks);
  }

  final double min;
  final double max;
  final double step;
  final List<double> ticks;

  /// Decimals a tick label needs: 0.25 needs two, 0.5 needs one.
  int get decimals {
    if (step >= 1) return 0;
    return ((step * 10) - (step * 10).roundToDouble()).abs() < 1e-9 ? 1 : 2;
  }
}

/// Everything the painter needs, resolved from the slide and its history.
class _Spec {
  const _Spec({
    required this.kind,
    required this.pts,
    required this.xt,
    required this.xRead,
    required this.yTitle,
    required this.xTitle,
    this.ref,
    this.refLabel,
    this.bandLo,
    this.bandHi,
    this.bandLabel,
    this.delta,
    this.eventK,
    this.eventLabel,
    this.topN = 0,
    this.topLabel,
  });

  final WrapChartKind kind;

  /// Series for line kinds; for bars, one point per fund (best first).
  final List<_Pt> pts;
  final List<_XTick> xt;

  /// Text for the x axis readout at each index; empty hides it.
  final List<String> xRead;
  final String yTitle;
  final String xTitle;
  final double? ref;
  final String? refLabel;
  final double? bandLo;
  final double? bandHi;
  final String? bandLabel;

  /// Label on the bracket measuring first to last; null draws no bracket.
  final String? delta;
  final int? eventK;
  final String? eventLabel;
  final int topN;
  final String? topLabel;
}

/// The chart under a story's figure: two labelled axes, a nice scale, a
/// readout on each axis, and a drag to scrub.
///
/// On entry the axes draw out from the origin, the value scale settles from
/// zoomed out into its range, the line draws itself, bars grow in order, and
/// a bracket measures the move. Under reduced motion it renders final.
class StoryChart extends ConsumerStatefulWidget {
  const StoryChart({
    super.key,
    required this.slide,
    required this.tone,
    required this.palette,
    this.onScrub,
    this.finished = false,
  });

  final WrapSlide slide;

  /// Jump to the final frame (the story is being captured for sharing).
  final bool finished;
  final Color tone;

  /// Story palette; stories always draw on the dark tokens.
  final fructaColors palette;

  /// Called with true while a finger scrubs, so the viewer can pause.
  final ValueChanged<bool>? onScrub;

  @override
  ConsumerState<StoryChart> createState() => _StoryChartState();
}

class _StoryChartState extends ConsumerState<StoryChart>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _armed = false;
  int? _h;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && !reduceMotion(context)) {
        _ring.repeat();
      }
    });
  }

  @override
  void didUpdateWidget(StoryChart old) {
    super.didUpdateWidget(old);
    if (widget.finished && !old.finished) {
      _intro.value = 1;
      _ring
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// Starts the entry once there is something to draw.
  void _arm() {
    if (_armed) return;
    _armed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reduceMotion(context) ? _intro.value = 1 : _intro.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = _resolve();
    if (spec == null) return const SizedBox.shrink();
    _arm();
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final f = _Frame.of(size);
        final n = spec.pts.length;

        int at(Offset p) {
          final k = spec.kind == WrapChartKind.bars
              ? ((p.dy - f.t) / (f.b - f.t) * n).floor()
              : ((p.dx - f.l) / (f.r - f.l) * (n - 1)).round();
          return k.clamp(0, n - 1);
        }

        void scrub(Offset p) {
          final k = at(p);
          if (k != _h) setState(() => _h = k);
        }

        void release() {
          if (_h != null) setState(() => _h = null);
          widget.onScrub?.call(false);
        }

        return Semantics(
          label: '${spec.yTitle}, ${spec.xTitle}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              widget.onScrub?.call(true);
              scrub(d.localPosition);
            },
            onPanUpdate: (d) => scrub(d.localPosition),
            onPanEnd: (_) => release(),
            onPanCancel: release,
            child: CustomPaint(
              size: size,
              painter: _StoryPainter(
                spec: spec,
                tone: widget.tone,
                d: widget.palette,
                intro: _intro,
                ring: _ring,
                h: _h,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the spec, or null while dated history is still loading or when
  /// the slide has nothing honest to plot.
  _Spec? _resolve() {
    final s = widget.slide;
    return switch (s.chart) {
      WrapChartKind.none => null,
      WrapChartKind.bars => _bars(s),
      WrapChartKind.rank => _rank(s),
      WrapChartKind.line ||
      WrapChartKind.step ||
      WrapChartKind.band => _series(s),
    };
  }

  _Spec? _bars(WrapSlide s) {
    if (s.field.length < 2 || s.refRate == null) return null;
    final ref = s.refRate!;
    return _Spec(
      kind: WrapChartKind.bars,
      pts: [for (final v in s.field) (day: null, v: v)],
      xt: const [],
      xRead: [for (final v in s.field) '${v.toStringAsFixed(2)}%'],
      yTitle: t('wrap.axis.rankOf', {'n': '${s.field.length}'}),
      xTitle: t('wrap.axis.gross'),
      ref: ref,
      refLabel: t(s.refKey ?? 'wrap.axis.tbill', {
        'v': '${ref.toStringAsFixed(2)}%',
      }),
    );
  }

  _Spec? _rank(WrapSlide s) {
    final a = s.rankFrom;
    final b = s.rankTo;
    if (a == null || b == null) return null;
    final now = t('wrap.axis.now');
    return _Spec(
      kind: WrapChartKind.rank,
      pts: [(day: null, v: a.toDouble()), (day: null, v: b.toDouble())],
      xt: [
        (k: 0, top: t('wrap.axis.then'), sub: '', keep: true),
        (k: 1, top: now, sub: '', keep: true),
      ],
      xRead: [t('wrap.axis.then'), now],
      yTitle: s.rankOf == null
          ? t('wrap.axis.rank')
          : t('wrap.axis.rankOf', {'n': '${s.rankOf}'}),
      xTitle: '',
      delta: a == b
          ? null
          : t('wrap.axis.places', {'v': a > b ? '+${a - b}' : '${a - b}'}),
      topN: 3,
      topLabel: t('wrap.axis.top', {'n': '3'}),
    );
  }

  _Spec? _series(WrapSlide s) {
    final fund = s.fundId == null
        ? null
        : ref.watch(fundsByIdProvider)[s.fundId];
    var pts = <_Pt>[];
    if (fund != null) {
      // Until dated history arrives, draw from the snapshot line below, so
      // the chart is never blank while it loads.
      final hist = ref.watch(historyProvider(fund.id));
      if (hist.hasValue) {
        pts = _daily(hist.value!, fund.currentRate, s.windowDays);
      }
    }
    if (pts.length < 2) pts = [for (final v in s.series) (day: null, v: v)];
    if (pts.length < 2) return null;

    final n = pts.length;
    final dated = pts.first.day != null;
    final now = t('wrap.axis.now');
    final xt = <_XTick>[];
    final xRead = <String>[];
    if (dated) {
      for (var k = 0; k < n; k++) {
        final d = pts[k].day!;
        xRead.add('${_wd[d.weekday - 1]} ${_dayMon(d)}');
        final first = k == 0;
        final last = k == n - 1;
        if (n <= 8) {
          // A week: every day, month only on the first so labels never crowd.
          xt.add((
            k: k,
            top: first ? _dayMon(d) : '${d.day}',
            sub: _wd[d.weekday - 1].substring(0, 2),
            keep: first || last,
          ));
        } else if (first || last) {
          xt.add((k: k, top: _dayMon(d), sub: '', keep: true));
        } else if (d.day == 1) {
          xt.add((k: k, top: _mon[d.month - 1], sub: '', keep: false));
        }
      }
    } else {
      xRead.addAll(List.filled(n - 1, ''));
      xRead.add(now);
      xt
        ..add((k: 0, top: t('wrap.axis.then'), sub: '', keep: true))
        ..add((k: n - 1, top: now, sub: '', keep: true));
    }

    final a = pts.first.day;
    final b = pts.last.day;
    final xTitle = !dated
        ? t('wrap.axis.prints', {'n': '$n'})
        : (a!.month == b!.month && a.year == b.year)
        ? '${_mon[b.month - 1]} ${b.year}'
        : t('wrap.axis.span', {
            'a': _mon[a.month - 1],
            'b': '${_mon[b.month - 1]} ${b.year}',
          });

    final move = pts.last.v - pts.first.v;
    int? eventK;
    String? eventLabel;
    if (s.chart == WrapChartKind.step && dated) {
      // The single biggest day to day change is the day worth marking.
      var best = 0.0;
      for (var k = 1; k < n; k++) {
        final c = pts[k].v - pts[k - 1].v;
        if (c.abs() > best.abs()) {
          best = c;
          eventK = k;
        }
      }
      if (eventK != null && best.abs() >= 0.005) {
        eventLabel = t(best < 0 ? 'wrap.axis.cutOn' : 'wrap.axis.upOn', {
          'day': _dayMon(pts[eventK].day!),
        });
      } else {
        eventK = null;
      }
    }

    final band = s.chart == WrapChartKind.band && s.field.length == 2;
    return _Spec(
      kind: s.chart,
      pts: pts,
      xt: xt,
      xRead: xRead,
      yTitle: t('wrap.axis.rate'),
      xTitle: xTitle,
      ref: s.refRate,
      refLabel: s.refRate == null
          ? null
          : t(s.refKey ?? 'wrap.axis.avg', {
              'v': '${s.refRate!.toStringAsFixed(2)}%',
            }),
      bandLo: band ? s.field.first : null,
      bandHi: band ? s.field.last : null,
      bandLabel: band ? t('wrap.axis.range') : null,
      delta: move.abs() < 0.005 || band
          ? null
          : t('wrap.axis.pts', {'v': _signed(move)}),
      eventK: eventK,
      eventLabel: eventLabel,
    );
  }
}

/// One value per calendar day over the last [days], each day carrying the
/// most recent print on or before it, so a rate change lands on its own day.
///
/// History can lag the headline, so a differing [current] is appended as
/// today's print (the same rule the fund page chart uses).
List<_Pt> _daily(List<RateHistory> raw, double? current, int days) {
  final sorted = [...raw]..sort((a, b) => a.asOf.compareTo(b.asOf));
  final prints = <({DateTime day, double v})>[
    for (final h in sorted) (day: _date(DateTime.parse(h.asOf)), v: h.rate),
  ];
  final today = _date(DateTime.now());
  if (current != null &&
      (prints.isEmpty || (prints.last.v - current).abs() >= 0.005)) {
    final last = prints.isEmpty ? null : prints.last.day;
    final at = last == null || today.isAfter(last)
        ? today
        : DateTime(last.year, last.month, last.day + 1);
    prints.add((day: at, v: current));
  }
  if (prints.isEmpty) return const [];

  final end = prints.last.day.isAfter(today) ? prints.last.day : today;
  var start = DateTime(end.year, end.month, end.day - days);
  if (prints.first.day.isAfter(start)) start = prints.first.day;

  final out = <_Pt>[];
  var j = 0;
  double? v;
  for (
    var d = start;
    !d.isAfter(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    while (j < prints.length && !prints[j].day.isAfter(d)) {
      v = prints[j].v;
      j++;
    }
    if (v != null) out.add((day: d, v: v));
  }
  return out;
}

class _StoryPainter extends CustomPainter {
  _StoryPainter({
    required this.spec,
    required this.tone,
    required this.d,
    required this.intro,
    required this.ring,
    required this.h,
  }) : super(repaint: Listenable.merge([intro, ring]));

  final _Spec spec;
  final Color tone;
  final fructaColors d;
  final Animation<double> intro;
  final Animation<double> ring;

  /// Scrubbed index, or null for the default readout.
  final int? h;

  /// Progress of the entry between [a] and [b], eased.
  double _iv(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((intro.value - a) / (b - a)).clamp(0.0, 1.0));

  TextStyle _num(Color c, {double size = 11, FontWeight w = FontWeight.w500}) =>
      fructaFonts.numeric(color: c, size: size, weight: w);

  TextStyle _sans(
    Color c, {
    double size = 11,
    FontWeight w = FontWeight.w600,
  }) => TextStyle(
    color: c,
    fontFamily: fructaFonts.sans,
    fontSize: size,
    fontWeight: w,
    letterSpacing: 0.3,
  );

  TextPainter _layout(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Draws [s] with its box anchored at [at]: [ax], [ay] are 0 for left or
  /// top, 0.5 for centre, 1 for right or bottom.
  void _text(
    Canvas c,
    String s,
    Offset at,
    TextStyle st, {
    double ax = 0,
    double ay = 0,
    double opacity = 1,
  }) {
    if (s.isEmpty || opacity <= 0) return;
    final tp = _layout(
      s,
      st.copyWith(color: st.color!.withValues(alpha: st.color!.a * opacity)),
    );
    tp.paint(c, at - Offset(tp.width * ax, tp.height * ay));
  }

  /// A rounded tag scaled by [scale] about its centre.
  void _pill(
    Canvas c,
    String s,
    Offset at,
    Color bg,
    Color fg, {
    double ax = 0.5,
    double ay = 0.5,
    double scale = 1,
    double minLeft = 0,
    double maxRight = double.infinity,
  }) {
    if (s.isEmpty || scale <= 0) return;
    final tp = _layout(s, _num(fg, w: FontWeight.w700));
    final w = tp.width + 14;
    final hgt = tp.height + 5;
    var left = at.dx - w * ax;
    left = left.clamp(minLeft, math.max(minLeft, maxRight - w));
    final rect = Rect.fromLTWH(left, at.dy - hgt * ay, w, hgt);
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    c.scale(scale);
    c.translate(-rect.center.dx, -rect.center.dy);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = bg,
    );
    tp.paint(c, rect.topLeft + const Offset(7, 2.5));
    c.restore();
  }

  /// Straight dashed line from [a] to [b].
  void _dash(
    Canvas c,
    Offset a,
    Offset b,
    Paint p, {
    double on = 3,
    double off = 4,
  }) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    for (var s = 0.0; s < len; s += on + off) {
      c.drawLine(a + dir * s, a + dir * math.min(s + on, len), p);
    }
  }

  /// The first [f] of [path] by length, for lines that draw themselves.
  Path _partial(Path path, double f) {
    if (f >= 1) return path;
    final out = Path();
    for (final m in path.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * f), Offset.zero);
    }
    return out;
  }

  /// Rotated y axis title, centred on the plot height.
  void _yTitle(Canvas c, _Frame f) {
    c.save();
    c.translate(7, (f.t + f.b) / 2);
    c.rotate(-math.pi / 2);
    _text(
      c,
      spec.yTitle,
      Offset.zero,
      _sans(d.faint),
      ax: 0.5,
      ay: 0.5,
      opacity: _iv(0.05, 0.3),
    );
    c.restore();
  }

  void _axes(Canvas c, _Frame f) {
    final a = _iv(0, 0.3);
    final p = Paint()
      ..color = d.text.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    c.drawLine(Offset(f.l, f.b), Offset(f.l, f.b - (f.b - f.t) * a), p);
    c.drawLine(Offset(f.l, f.b), Offset(f.l + (f.r - f.l) * a, f.b), p);
    _text(
      c,
      spec.xTitle,
      Offset(f.r + 20, f.b + 56),
      _sans(d.faint),
      ax: 1,
      ay: 1,
      opacity: _iv(0.3, 0.55),
    );
  }

  Paint get _gridPaint => Paint()
    ..color = d.text.withValues(alpha: 0.09)
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final f = _Frame.of(size);
    _yTitle(canvas, f);
    spec.kind == WrapChartKind.bars
        ? _paintBars(canvas, f, size)
        : _paintSeries(canvas, f, size);
  }

  void _paintSeries(Canvas c, _Frame f, Size size) {
    final pts = spec.pts;
    final n = pts.length;
    final rank = spec.kind == WrapChartKind.rank;
    final vals = [
      for (final p in pts) p.v,
      ?spec.ref,
      ?spec.bandLo,
      ?spec.bandHi,
    ];
    final sc = _Scale.nice(
      vals.reduce(math.min),
      vals.reduce(math.max),
      rank: rank,
    );

    // Rate axes start zoomed out and settle into the nice range, so ticks
    // spread from the middle and the line grows into place. Ranks stay put.
    final e = rank ? 1.0 : _iv(0, 0.75);
    final span = sc.max - sc.min;
    final lo = sc.min - span * 1.6 * (1 - e);
    final hi = sc.max + span * 1.6 * (1 - e);
    double x(int k) => f.l + (f.r - f.l) * k / (n - 1);
    double y(double v) {
      final u = (v - lo) / (hi - lo);
      return rank ? f.t + u * (f.b - f.t) : f.b - u * (f.b - f.t);
    }

    String fy(double v) =>
        rank ? '#${v.round()}' : v.toStringAsFixed(sc.decimals);
    String fv(double v) => rank ? '#${v.round()}' : '${v.toStringAsFixed(2)}%';

    // Top places zone on a rank axis.
    if (rank && spec.topN > 0) {
      final fade = _iv(0.3, 0.6);
      final bottom = y(spec.topN + 0.5).clamp(f.t, f.b);
      c.drawRect(
        Rect.fromLTRB(f.l, f.t, f.r, bottom),
        Paint()..color = d.up.withValues(alpha: 0.08 * fade),
      );
      _dash(
        c,
        Offset(f.l, bottom),
        Offset(f.r, bottom),
        Paint()
          ..color = d.up.withValues(alpha: 0.4 * fade)
          ..strokeWidth = 1,
      );
      _text(
        c,
        spec.topLabel ?? '',
        Offset(f.r - 4, f.t + 4),
        _sans(d.up, w: FontWeight.w700),
        ax: 1,
        opacity: fade,
      );
    }

    // Value ticks and gridlines, staggered bottom up.
    for (var j = 0; j < sc.ticks.length; j++) {
      final v = sc.ticks[j];
      final yy = y(v);
      final g = _iv(0.05 + j * 0.06, 0.45 + j * 0.06);
      _dash(c, Offset(f.l, yy), Offset(f.l + (f.r - f.l) * g, yy), _gridPaint);
      _text(
        c,
        fy(v),
        Offset(f.l - 8, yy),
        _num(d.muted),
        ax: 1,
        ay: 0.5,
        opacity: g * (0.35 + 0.65 * e),
      );
    }

    // Time ticks; middle labels give way when they would crowd a neighbour.
    final tickPaint = Paint()
      ..color = d.text.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    var lastRight = -double.infinity;
    final lastX = spec.xt.isEmpty ? 0.0 : x(spec.xt.last.k);
    for (var j = 0; j < spec.xt.length; j++) {
      final tk = spec.xt[j];
      final xx = x(tk.k);
      if (!tk.keep && (xx - lastRight < 40 || lastX - xx < 44)) continue;
      final o = _iv(0.2 + j * 0.03, 0.5 + j * 0.03);
      c.drawLine(Offset(xx, f.b), Offset(xx, f.b + 5 * o), tickPaint);
      final ax = tk.k == 0 ? 0.0 : (tk.k == n - 1 ? 1.0 : 0.5);
      final rise = 6 * (1 - o);
      _text(
        c,
        tk.top,
        Offset(xx, f.b + 8 + rise),
        _num(d.muted),
        ax: ax,
        opacity: o,
      );
      _text(
        c,
        tk.sub,
        Offset(xx, f.b + 22 + rise),
        _sans(d.faint, size: 10, w: FontWeight.w500),
        ax: ax,
        opacity: o,
      );
      lastRight = xx;
    }

    _axes(c, f);

    final wipe = _iv(0.2, 0.8);
    final clip = Rect.fromLTRB(0, 0, f.l + (f.r - f.l) * wipe, size.height);

    // Field range behind a flat line.
    if (spec.bandLo != null && spec.bandHi != null) {
      c.save();
      c.clipRect(clip);
      final r = Rect.fromLTRB(f.l, y(spec.bandHi!), f.r, y(spec.bandLo!));
      c.drawRect(r, Paint()..color = d.text.withValues(alpha: 0.07));
      final edge = Paint()
        ..color = d.text.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      c.drawLine(r.topLeft, r.topRight, edge);
      c.drawLine(r.bottomLeft, r.bottomRight, edge);
      c.restore();
      _text(
        c,
        spec.bandLabel ?? '',
        Offset(f.l + 8, r.top + 4),
        _sans(d.muted),
        opacity: _iv(0.45, 0.7),
      );
    }

    // Line path; a step series holds each rate until the day it changes.
    final path = Path()..moveTo(x(0), y(pts[0].v));
    for (var k = 1; k < n; k++) {
      if (spec.kind == WrapChartKind.step) {
        path
          ..lineTo(x(k), y(pts[k - 1].v))
          ..lineTo(x(k), y(pts[k].v));
      } else {
        path.lineTo(x(k), y(pts[k].v));
      }
    }

    if (!rank && spec.bandLo == null) {
      final area = Path.from(path)
        ..lineTo(f.r, f.b)
        ..lineTo(f.l, f.b)
        ..close();
      c.save();
      c.clipRect(clip);
      c.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone.withValues(alpha: 0.28), tone.withValues(alpha: 0)],
          ).createShader(Rect.fromLTRB(f.l, f.t, f.r, f.b)),
      );
      c.restore();
    }

    if (spec.ref != null) {
      final ry = y(spec.ref!);
      final rw = _iv(0.4, 0.85);
      _dash(
        c,
        Offset(f.l, ry),
        Offset(f.l + (f.r - f.l) * rw, ry),
        Paint()
          ..color = d.text.withValues(alpha: 0.55)
          ..strokeWidth = 1.5,
        on: 4,
        off: 5,
      );
      final above = ry - 17 >= f.t - 4;
      _text(
        c,
        spec.refLabel ?? '',
        Offset(f.l + 6, above ? ry - 4 : ry + 4),
        _sans(d.text.withValues(alpha: 0.6)),
        ay: above ? 1 : 0,
        opacity: _iv(0.6, 0.8),
      );
    }

    if (spec.eventK != null) {
      final ex = x(spec.eventK!);
      final o = _iv(0.6, 0.8);
      _dash(
        c,
        Offset(ex, f.t),
        Offset(ex, f.b),
        Paint()
          ..color = d.text.withValues(alpha: 0.45 * o)
          ..strokeWidth = 1,
      );
      final right =
          ex + 5 + _layout(spec.eventLabel ?? '', _sans(d.text)).width >
          f.r + 20;
      _text(
        c,
        spec.eventLabel ?? '',
        Offset(right ? ex - 5 : ex + 5, 2 + 6 * (1 - o)),
        _sans(d.text),
        ax: right ? 1 : 0,
        opacity: o,
      );
    }

    c.drawPath(
      _partial(path, _iv(0.15, 0.8, Curves.easeInOutCubic)),
      Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Start level carried across, with a bracket measuring the move.
    if (spec.delta != null) {
      final gy = y(pts.first.v);
      final ey = y(pts.last.v);
      final bx = f.r + 12;
      final g = _iv(0.75, 0.9);
      _dash(
        c,
        Offset(f.l, gy),
        Offset(f.l + (bx - 4 - f.l) * g, gy),
        Paint()
          ..color = d.text.withValues(alpha: 0.4)
          ..strokeWidth = 1,
        on: 2,
        off: 4,
      );
      final br = Path()
        ..moveTo(bx - 4, gy)
        ..lineTo(bx, gy)
        ..lineTo(bx, ey)
        ..lineTo(bx - 4, ey);
      c.drawPath(
        _partial(br, _iv(0.82, 0.95)),
        Paint()
          ..color = tone
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _pill(
        c,
        spec.delta!,
        Offset(bx - 8, (gy + ey) / 2),
        tone.withValues(alpha: 0.16),
        tone,
        ax: 1,
        scale: _iv(0.88, 1, Curves.easeOutBack),
      );
    }

    // Rank observations pop in order.
    if (rank) {
      for (var k = 0; k < n; k++) {
        final s = _iv(0.3 + k * 0.12, 0.5 + k * 0.12, Curves.easeOutBack);
        c.drawCircle(Offset(x(k), y(pts[k].v)), 6.5 * s, Paint()..color = d.bg);
        c.drawCircle(Offset(x(k), y(pts[k].v)), 4.5 * s, Paint()..color = tone);
      }
    }

    final idx = h ?? n - 1;
    final fx = x(idx);
    final fyy = y(pts[idx].v);

    if (h != null) {
      final guide = Paint()
        ..color = d.text.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      _dash(c, Offset(f.l, fyy), Offset(fx, fyy), guide);
      _dash(c, Offset(fx, fyy), Offset(fx, f.b), guide);
    }

    // Pulse ring on the latest point once the entry has settled.
    if (h == null && ring.value > 0) {
      final r = ring.value;
      c.drawCircle(
        Offset(x(n - 1), y(pts.last.v)),
        5 * (1 + 2.4 * r),
        Paint()
          ..color = tone.withValues(alpha: 0.6 * (1 - r))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final pop = h == null ? _iv(0.8, 0.92, Curves.easeOutBack) : 1.0;
    c.drawCircle(
      Offset(fx, fyy),
      6 * pop,
      Paint()..color = h == null ? tone : d.text,
    );
    c.drawCircle(
      Offset(fx, fyy),
      6 * pop,
      Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Readouts on both axes: the latest point by default, the finger's point
    // while scrubbing.
    final read = h == null ? _iv(0.85, 1, Curves.easeOutBack) : 1.0;
    _pill(
      c,
      fv(pts[idx].v),
      Offset(f.l - 4, fyy),
      tone,
      d.bg,
      ax: 1,
      scale: read,
    );
    _pill(
      c,
      spec.xRead[idx],
      Offset(fx, f.b + 6),
      d.text,
      d.bg,
      ay: 0,
      scale: read,
      minLeft: f.l - 20,
      maxRight: size.width,
    );
  }

  void _paintBars(Canvas c, _Frame f, Size size) {
    final rates = [for (final p in spec.pts) p.v];
    final n = rates.length;
    final ref = spec.ref!;
    final sc = _Scale.nice(
      math.min(rates.reduce(math.min), ref),
      rates.reduce(math.max),
    );
    double x(double v) => f.l + (v - sc.min) / (sc.max - sc.min) * (f.r - f.l);
    final row = (f.b - f.t) / n;

    // Rate ticks along the bottom, with vertical gridlines.
    for (var j = 0; j < sc.ticks.length; j++) {
      final v = sc.ticks[j];
      final xx = x(v);
      final g = _iv(0.05 + j * 0.05, 0.45 + j * 0.05);
      _dash(c, Offset(xx, f.b), Offset(xx, f.b - (f.b - f.t) * g), _gridPaint);
      c.drawLine(
        Offset(xx, f.b),
        Offset(xx, f.b + 5 * g),
        Paint()
          ..color = d.text.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      _text(
        c,
        v.toStringAsFixed(sc.decimals),
        Offset(xx, f.b + 8 + 6 * (1 - g)),
        _num(d.muted),
        ax: 0.5,
        opacity: g,
      );
    }

    // Rank ticks down the side: first, quarters, last.
    final marks = <int>{
      1,
      (n * 0.25).round(),
      (n * 0.5).round(),
      (n * 0.75).round(),
      n,
    }.where((r) => r >= 1 && r <= n).toList();
    for (var j = 0; j < marks.length; j++) {
      final yy = f.t + (marks[j] - 0.5) * row;
      _text(
        c,
        '#${marks[j]}',
        Offset(f.l - 8, yy),
        _num(d.muted),
        ax: 1,
        ay: 0.5,
        opacity: _iv(0.08 + j * 0.06, 0.4 + j * 0.06),
      );
    }

    _axes(c, f);

    // Bars grow from the axis one after another, best first.
    final idx = h ?? 0;
    for (var k = 0; k < n; k++) {
      final g = _iv(0.2 + k * 0.013, 0.55 + k * 0.013, Curves.easeOutBack);
      final color = h == k
          ? d.text
          : k == 0
          ? tone
          : rates[k] > ref
          ? d.up.withValues(alpha: 0.7)
          : d.text.withValues(alpha: 0.2);
      final w = math.max(0.0, (x(rates[k]) - f.l) * g);
      c.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(f.l, f.t + k * row + 0.6, w, math.max(1.5, row - 1.4)),
          topRight: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }

    // Reference rate as a vertical line from top to axis.
    final rx = x(ref);
    final rw = _iv(0.45, 0.8);
    _dash(
      c,
      Offset(rx, f.t - 6),
      Offset(rx, f.t - 6 + (f.b - f.t + 6) * rw),
      Paint()
        ..color = d.accent
        ..strokeWidth = 1.5,
      on: 4,
      off: 4,
    );
    final label = spec.refLabel ?? '';
    final flip = rx + 5 + _layout(label, _sans(d.accent)).width > size.width;
    _text(
      c,
      label,
      Offset(flip ? rx - 5 : rx + 5, 0),
      _sans(d.accent),
      ax: flip ? 1 : 0,
      opacity: _iv(0.6, 0.8),
    );

    final read = h == null ? _iv(0.85, 1, Curves.easeOutBack) : 1.0;
    _pill(
      c,
      '#${idx + 1}',
      Offset(f.l - 4, f.t + (idx + 0.5) * row),
      tone,
      d.bg,
      ax: 1,
      scale: read,
    );
    _pill(
      c,
      spec.xRead[idx],
      Offset(x(rates[idx]), f.b + 6),
      d.text,
      d.bg,
      ay: 0,
      scale: read,
      minLeft: f.l - 20,
      maxRight: size.width,
    );
  }

  @override
  bool shouldRepaint(covariant _StoryPainter old) =>
      old.spec != spec || old.h != h || old.tone != tone;
}

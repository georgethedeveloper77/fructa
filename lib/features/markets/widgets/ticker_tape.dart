import 'package:flutter/material.dart';

import '../../../core/category_colors.dart';
import '../../../core/series_colors.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';

/// Continuously scrolling strip of top rates, grouped by category.
///
/// Each category is named ONCE, in its own colour from the central palette
/// ([fundTypeColors] / [categoryColor]), and its funds are listed under it
/// before a divider and the next category. Money market splits into KES and USD
/// so the currency is stated by the header instead of repeated on every cell.
/// This is what stops two funds from one manager reading as a glitchy
/// duplicate: an Etica under SPECIAL and an Etica under MMF KES are plainly
/// different things.
///
/// A USD/KES cell rides at the end when [fxRate] is supplied. It is the only
/// non-fund item in the strip, and it earns the place: the currency card that
/// explains it sits at the FOOT of Markets, so without a cue up here nobody
/// scrolling the rates would know it exists.
///
/// Gestures: press-and-hold pauses and releasing resumes; a single tap toggles
/// a sticky pause; a double tap on a fund opens it. The single-tap pause waits
/// about 300ms so it can be told apart from a double tap.
class TickerTape extends StatefulWidget {
  const TickerTape(
    this.funds, {
    super.key,
    this.onOpenFund,
    this.fxRate,
    this.fxPair = 'USD/KES',
    this.fxMove12,
    this.onOpenFx,
  });

  final List<Fund> funds;

  /// Called with the fund under a double-tapped cell. Null makes double-tap a
  /// no-op (the strip still scrolls and pauses).
  final void Function(Fund)? onOpenFund;

  /// Latest indicative mean. Null hides the currency cell entirely, which is
  /// the correct state before the FX backfill has run.
  final double? fxRate;

  final String fxPair;

  /// Trailing twelve month move as a fraction, positive when the shilling
  /// weakened. Null renders the rate with no move beside it rather than
  /// printing a zero that would read as "unchanged".
  final double? fxMove12;

  /// Double-tap target for the currency cell.
  final VoidCallback? onOpenFx;

  @override
  State<TickerTape> createState() => _TickerTapeState();
}

/// One category band: its header label, its colour, and the test that decides
/// which funds belong to it. Ordered; empty bands are dropped at build time.
class _Section {
  const _Section(this.label, this.color, this.test);
  final String label;
  final Color color;
  final bool Function(Fund) test;
}

/// The flat, scrollable stream is a sequence of these.
sealed class _Item {
  const _Item();
}

class _HeaderItem extends _Item {
  const _HeaderItem(this.label, this.color);
  final String label;
  final Color color;
}

class _FundItem extends _Item {
  const _FundItem(this.fund);
  final Fund fund;
}

class _DividerItem extends _Item {
  const _DividerItem();
}

class _FxItem extends _Item {
  const _FxItem(this.pair, this.rate, this.move12);
  final String pair;
  final double rate;
  final double? move12;
}

class _TickerTapeState extends State<TickerTape>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _ctl;
  bool _stopped = false; // sticky pause via tap

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _ctl.addListener(_tick);
  }

  void _tick() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset + 0.6);
  }

  void _pause() => _ctl.stop();
  void _resume() {
    if (!_stopped && _ctl.isAnimating == false) _ctl.repeat();
  }

  void _toggleSticky() {
    setState(() => _stopped = !_stopped);
    _stopped ? _ctl.stop() : _ctl.repeat();
  }

  @override
  void dispose() {
    _ctl.removeListener(_tick);
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> _build() {
    // Ordered category bands. Money market first and split by currency; the
    // legacy T-bill instrument rides at the end. Colours come straight from the
    // central palette so the ticker agrees with the donut and the pulse.
    final sections = <_Section>[
      _Section('MMF KES', fundTypeColor('mmf'),
          (f) => f.fundType == 'mmf' && f.currency == 'KES'),
      _Section('MMF USD', fundTypeColor('mmf'),
          (f) => f.fundType == 'mmf' && f.currency == 'USD'),
      _Section('FIXED INCOME', fundTypeColor('fixed_income'),
          (f) => f.fundType == 'fixed_income'),
      _Section('SPECIAL', fundTypeColor('special'),
          (f) => f.fundType == 'special'),
      _Section('EQUITY', fundTypeColor('equity'),
          (f) => f.fundType == 'equity'),
      _Section('BALANCED', fundTypeColor('balanced'),
          (f) => f.fundType == 'balanced'),
      _Section('T-BILLS', categoryColor('tbill'),
          (f) => f.category == 'tbill'),
    ];

    final items = <_Item>[];
    for (final sec in sections) {
      final group =
          widget.funds.where((f) => f.currentRate != null && sec.test(f)).toList()
            ..sort((a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0));
      if (group.isEmpty) continue;
      items.add(_HeaderItem(sec.label, sec.color));
      for (final f in group.take(6)) {
        items.add(_FundItem(f));
      }
      items.add(const _DividerItem());
    }

    // Currency last, under its own header, in the same palette the context
    // card uses so the two are recognisably the same subject.
    final fx = widget.fxRate;
    if (fx != null) {
      items.add(_HeaderItem(widget.fxPair, seriesColor(2)));
      items.add(_FxItem(widget.fxPair, fx, widget.fxMove12));
      items.add(const _DividerItem());
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _build();
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: Listener(
        // Hold to pause, release to resume (unless tap-stopped).
        onPointerDown: (_) => _pause(),
        onPointerUp: (_) => _resume(),
        onPointerCancel: (_) => _resume(),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.04, 0.96, 1.0],
          ).createShader(rect),
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) {
              final it = items[i % items.length];
              final Widget child = switch (it) {
                _HeaderItem(:final label, :final color) =>
                  _header(label, color),
                _FundItem(:final fund) => _fund(context, fund),
                _FxItem(:final rate, :final move12) => _fx(context, rate, move12),
                _DividerItem() => _divider(context),
              };
              final onDouble = switch (it) {
                _FundItem(:final fund) when widget.onOpenFund != null =>
                  () => widget.onOpenFund!(fund),
                _FxItem() when widget.onOpenFx != null => widget.onOpenFx,
                _ => null,
              };
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleSticky,
                onDoubleTap: onDouble,
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(String label, Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: fructaFonts.mono,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _fund(BuildContext context, Fund f) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Text(
            f.name.split(' ').first,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            '${f.currentRate!.toStringAsFixed(2)}%',
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// The rate, then the trailing year beside it. A currency quote with no
  /// sense of direction is a number nobody can act on, and the direction is
  /// the entire reason the cell is here.
  Widget _fx(BuildContext context, double rate, double? move12) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Text(
            rate.toStringAsFixed(2),
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (move12 != null) ...[
            const SizedBox(width: 6),
            Text(
              // Positive means the shilling weakened, which is the pair going
              // UP. Signing it the other way round would put a green arrow on
              // a falling currency.
              '${move12 >= 0 ? '+' : '-'}${(move12.abs() * 100).toStringAsFixed(1)}% 1Y',
              style: TextStyle(
                color: c.muted,
                fontFamily: fructaFonts.mono,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: context.c.line2,
      );
}

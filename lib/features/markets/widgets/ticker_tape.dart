import 'package:flutter/material.dart';

import '../../../core/category_colors.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';

/// Continuously scrolling strip of top rates, brand-tinted per type. Both edges
/// fade to transparent. Press-and-hold pauses the scroll; a tap toggles a
/// sticky pause (tap again to resume)  so a thumb resting on it doesn't fight
/// the animation. Rate colour is always legible (fund-type / category hue,
/// never the muted-grey fallback).
class TickerTape extends StatefulWidget {
  const TickerTape(this.funds, {super.key});
  final List<Fund> funds;

  @override
  State<TickerTape> createState() => _TickerTapeState();
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

  Color _rateColor(BuildContext context, Fund f) {
    final ft = f.fundType;
    if (ft != null && fundTypeColors.containsKey(ft))
      return fundTypeColors[ft]!;
    return categoryColors[f.category] ?? context.c.text;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top =
        ([...widget.funds]..sort(
              (a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0),
            ))
            .where((f) => f.currentRate != null)
            .take(12)
            .toList();
    if (top.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: Listener(
        // Hold to pause, release to resume (unless tap-stopped).
        onPointerDown: (_) => _pause(),
        onPointerUp: (_) => _resume(),
        onPointerCancel: (_) => _resume(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleSticky,
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
              stops: [0.0, 0.05, 0.95, 1.0],
            ).createShader(rect),
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, i) {
                final f = top[i % top.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                          color: _rateColor(context, f),
                          fontFamily: fructaFonts.mono,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

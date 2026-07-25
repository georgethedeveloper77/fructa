import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../theme.dart';

/// The app's single loading indicator, in the brand accent by default. Inline
/// and chart loaders use the Newton's cradle; set [wave] for app-level loading
/// (major actions and full-screen waits), which reads better as a dots wave.
/// Pass [color] to override (e.g. a fund's brand tint on its own chart).
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 36, this.color, this.wave = false});

  final double size;
  final Color? color;
  final bool wave;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.c.accent;
    return wave
        ? LoadingAnimationWidget.staggeredDotsWave(color: tint, size: size)
        : LoadingAnimationWidget.newtonCradle(color: tint, size: size);
  }
}

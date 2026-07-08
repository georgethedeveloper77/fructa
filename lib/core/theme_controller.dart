import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'theme.dart';

/// Persisted appearance state: light/dark/system + which of the 5 accents.
@immutable
class AppTheme {
  const AppTheme({
    required this.mode,
    required this.accent,
    required this.textScale,
  });

  final ThemeMode mode;
  final fructaAccent accent;

  /// Global text-scale multiplier (0.9 = small … 1.3 = extra large).
  final double textScale;

  static const initial = AppTheme(
    mode: ThemeMode.system,
    accent: fructaAccent.gold,
    textScale: 1.0,
  );

  AppTheme copyWith({
    ThemeMode? mode,
    fructaAccent? accent,
    double? textScale,
  }) => AppTheme(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    textScale: textScale ?? this.textScale,
  );
}

/// Hive box that holds settings. Open it in `main()` before `runApp` and
/// override this provider with the opened box:
///
/// ```dart
/// await Hive.initFlutter();
/// final settings = await Hive.openBox('settings');
/// runApp(ProviderScope(
///   overrides: [settingsBoxProvider.overrideWithValue(settings)],
///   child: const fructaApp(),
/// ));
/// ```
final settingsBoxProvider = Provider<Box>((ref) {
  throw UnimplementedError('settingsBoxProvider must be overridden in main()');
});

const _kMode = 'theme_mode'; // stored as ThemeMode.index
const _kAccent = 'theme_accent'; // stored as fructaAccent.index
const _kTextScale = 'text_scale'; // stored as double (0.9..1.3)

class ThemeController extends Notifier<AppTheme> {
  Box get _box => ref.read(settingsBoxProvider);

  @override
  AppTheme build() {
    final modeIdx = _box.get(_kMode) as int?;
    final accentIdx = _box.get(_kAccent) as int?;
    final scale = (_box.get(_kTextScale) as num?)?.toDouble();
    return AppTheme(
      mode: _themeModeFrom(modeIdx),
      accent: _accentFrom(accentIdx),
      textScale: _scaleFrom(scale),
    );
  }

  void setMode(ThemeMode mode) {
    state = state.copyWith(mode: mode);
    _box.put(_kMode, mode.index);
  }

  void setAccent(fructaAccent accent) {
    state = state.copyWith(accent: accent);
    _box.put(_kAccent, accent.index);
  }

  void setTextScale(double scale) {
    final s = _scaleFrom(scale);
    state = state.copyWith(textScale: s);
    _box.put(_kTextScale, s);
  }

  void cycleMode() => setMode(switch (state.mode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  });

  // Defensive parsing  never throw on a corrupt/out-of-range persisted value.
  static ThemeMode _themeModeFrom(int? i) =>
      (i != null && i >= 0 && i < ThemeMode.values.length)
      ? ThemeMode.values[i]
      : AppTheme.initial.mode;

  static fructaAccent _accentFrom(int? i) =>
      (i != null && i >= 0 && i < fructaAccent.values.length)
      ? fructaAccent.values[i]
      : AppTheme.initial.accent;

  // Clamp to the supported range so a corrupt value can't break layout.
  static double _scaleFrom(double? s) =>
      (s == null || s.isNaN) ? 1.0 : s.clamp(0.9, 1.3);
}

final themeControllerProvider = NotifierProvider<ThemeController, AppTheme>(
  ThemeController.new,
);

/// Convenience selectors so widgets can watch just what they need.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeControllerProvider).mode,
);
final accentProvider = Provider<fructaAccent>(
  (ref) => ref.watch(themeControllerProvider).accent,
);
final textScaleProvider = Provider<double>(
  (ref) => ref.watch(themeControllerProvider).textScale,
);

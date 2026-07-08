import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight i18n. Loads a flat key→string JSON from assets/lang/<code>.json
/// once at startup and exposes a global `t(...)`. No extra dependencies, and it
/// works outside the widget tree (engines, providers) as well as inside.
///
/// Convention going forward: **no bare UI string literals**  every visible
/// string is `t('some.key')`, with the English copy in assets/lang/en.json.
///
/// Interpolation: `t('markets.fundCount', {'n': '12'})` against
/// `"{n} funds"` → "12 funds".
class L10n {
  L10n._();

  static String _code = 'en';
  static Map<String, String> _map = const {};

  static String get code => _code;

  static Future<void> load([String code = 'en']) async {
    _code = code;
    try {
      final raw = await rootBundle.loadString('assets/lang/$code.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _map = decoded.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      // Missing/!valid file → keys fall through as their own text.
      _map = const {};
    }
  }

  static String translate(String key, [Map<String, String>? vars]) {
    var s = _map[key] ?? key;
    if (vars != null) {
      vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }
}

/// Global shorthand. Prefer this at call sites: `Text(t('nav.markets'))`.
String t(String key, [Map<String, String>? vars]) => L10n.translate(key, vars);

/// Provider bump for future runtime language switching: rebuild widgets after
/// `ref.read(localeProvider.notifier).state = 'sw'` + `L10n.load('sw')`.
final localeProvider = StateProvider<String>((_) => L10n.code);

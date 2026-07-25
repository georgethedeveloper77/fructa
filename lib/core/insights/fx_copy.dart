// The currency card's copy layer. Picks a slot from live market state, picks a
// phrasing from the date, and fills the tokens.
//
// Two rules this file exists to enforce.
//
// First, variance comes from the market and not from a shuffle. A random line
// on every rebuild reads as a glitch on a screen full of numbers, and it makes
// two screenshots of the same market disagree. The slot is a pure function of
// stance, regime and hurdle band; the phrasing within a slot is a pure function
// of the day of the year. Same market, same day, same sentence.
//
// Second, the database wins. Rows live in insight_templates (migration 0072)
// and ride in the snapshot, so a phrasing can be fixed from the admin without
// an app release. [_fallback] carries one phrasing per slot so a device with a
// stale snapshot, or one that has never fetched, still renders a sentence
// rather than a blank. It is a floor, not a source of truth.

import '../../engine/fx_engine.dart';

/// One filled line, plus the slot it came from so a caller can log or test
/// which branch fired without re-deriving it.
class FxLine {
  const FxLine({required this.key, required this.text});

  /// The `fx.<stance>.<regime>[.<band>]` slot this came from.
  final String key;

  /// The filled sentence. May contain `<b>` and is rendered accordingly.
  final String text;
}

abstract final class FxCopy {
  /// Regroups raw (key, template) rows into the map [line] wants.
  ///
  /// Not needed on the normal path: SnapshotExtras already exposes
  /// `templateBank` grouped by key, and [line] reads that directly. This exists
  /// for a caller holding ungrouped rows, and for tests.
  static Map<String, List<String>> groupBank(
    Iterable<(String key, String template)> rows,
  ) {
    final out = <String, List<String>>{};
    for (final (key, template) in rows) {
      if (!key.startsWith('fx.')) continue;
      (out[key] ??= <String>[]).add(template);
    }
    // Stable order inside a slot, so the day rotation lands on the same
    // phrasing regardless of the order the rows arrived in.
    for (final v in out.values) {
      v.sort();
    }
    return out;
  }

  /// The line for the card.
  ///
  /// [move12] and [move3] are the trailing moves in the pair as fractions, with
  /// the sign convention used everywhere else in the feature: positive means
  /// the shilling weakened. They are rendered as magnitudes, because the
  /// direction is already carried by the regime that selected the slot.
  static FxLine line({
    required FxCase fxCase,
    required FxRegime regime,
    required double move12,
    required double move3,
    Map<String, List<String>> bank = const {},
    DateTime? now,
  }) {
    final key = FxEngine.copyKey(
      stance: fxCase.stance,
      regime: regime,
      band: fxCase.hurdleBand,
    );

    // Sorted, so the day rotation lands on the same phrasing regardless of the
    // order the rows came out of the snapshot. Without this the line could
    // change on a rebuild that shuffled the bank, which is exactly the flicker
    // the day-based rotation exists to prevent.
    final raw = bank[key];
    final options = (raw != null && raw.isNotEmpty)
        ? (List<String>.of(raw)..sort())
        : (_fallback[key] == null
            ? const <String>[]
            : <String>[_fallback[key]!]);

    if (options.isEmpty) return FxLine(key: key, text: '');

    final pick = options[
        FxEngine.rotation(now: now ?? DateTime.now(), count: options.length)];

    return FxLine(key: key, text: _fill(pick, fxCase, move12, move3));
  }

  static String _fill(
    String template,
    FxCase fxCase,
    double move12,
    double move3,
  ) {
    final be = fxCase.breakeven;
    final hurdle = fxCase.annualisedHurdle;

    // A missing hurdle only happens on the hedged stance, whose templates
    // never reference {be} or {hurdle}. Rendering a dash rather than dropping
    // the token means a mis-keyed template shows up as visibly wrong in review
    // instead of quietly reading as a complete sentence.
    return template
        .replaceAll('{mean}', fxCase.quote.mean.toStringAsFixed(2))
        .replaceAll('{be}', be == null ? '-' : be.toStringAsFixed(2))
        .replaceAll(
            '{hurdle}', hurdle == null ? '-' : _pct(hurdle * 100))
        .replaceAll('{gap}', _pct(fxCase.annualGap * 100))
        .replaceAll('{mv12}', _pct(move12.abs() * 100))
        .replaceAll('{mv3}', _pct(move3.abs() * 100));
  }

  /// 5.28 renders as 5.3, 11.0 renders as 11. Trailing zeroes on a figure this
  /// approximate imply a precision the input does not have.
  static String _pct(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// One phrasing per slot, mirroring the first row of each pair in migration
  /// 0072. Present so a device with no snapshot still renders a sentence.
  static const Map<String, String> _fallback = {
    // Buying USD.
    'fx.buying.calm.low':
        'The pair is sitting still and the yield gap is narrow. Buying USD needs <b>{be}</b> inside a year, about <b>{hurdle}%</b>.',
    'fx.buying.calm.mod':
        'Flat near <b>{mean}</b>. Buying USD has to clear <b>{hurdle}% a year</b> before the spread and the yield gap are paid off.',
    'fx.buying.calm.high':
        'A wide <b>{gap} point</b> gap against a still market. Buying USD needs <b>{be}</b> within the year just to draw level.',
    'fx.buying.drifting.low':
        'The pair has moved <b>{mv12}%</b> over the year against a <b>{hurdle}%</b> bar. Closer to break even than it usually is.',
    'fx.buying.drifting.mod':
        'The shilling is drifting, <b>{mv12}%</b> over the year. Buying USD still needs <b>{hurdle}% a year</b> to pay for itself.',
    'fx.buying.drifting.high':
        'A <b>{mv12}%</b> year against a <b>{hurdle}%</b> hurdle. The drift is real and it is not yet enough.',
    'fx.buying.falling.low':
        'Down <b>{mv12}%</b> in twelve months, well past the <b>{hurdle}%</b> a buyer needed. That is history, not a forecast.',
    'fx.buying.falling.mod':
        'A <b>{mv12}%</b> fall has carried past the <b>{hurdle}%</b> hurdle. Every buyer converting today starts again at <b>{be}</b>.',
    'fx.buying.falling.high':
        'Down <b>{mv12}%</b> against a <b>{hurdle}%</b> bar, so the currency is doing the work the <b>{gap} point</b> yield gap cannot.',
    'fx.buying.snapback.low':
        'The shilling has gained <b>{mv3}%</b> in three months. Anyone who bought USD before that is behind before yield is counted.',
    'fx.buying.snapback.mod':
        'Up <b>{mv3}%</b> in a quarter. Buying USD now starts from <b>{mean}</b> and still needs <b>{hurdle}% a year</b>.',
    'fx.buying.snapback.high':
        'A <b>{mv3}%</b> quarter against the dollar, with a <b>{gap} point</b> yield gap on top. Both are working against a buyer.',

    // Holding USD.
    'fx.holding.calm.low':
        'You are past the buy spread, so only the <b>{gap} point</b> gap is left. Staying long needs <b>{be}</b>.',
    'fx.holding.calm.mod':
        'Flat at <b>{mean}</b>. A KES fund pays you <b>{hurdle}% a year</b> to convert now, and the pair has to reach {be} to make waiting right.',
    'fx.holding.calm.high':
        'A <b>{gap} point</b> gap is a lot to give up to a market that is not moving. Break even is <b>{be}</b>.',
    'fx.holding.drifting.low':
        'The pair has moved <b>{mv12}%</b> over the year against a <b>{hurdle}%</b> bar. Holding is close to paying for itself.',
    'fx.holding.drifting.mod':
        'The pair has moved <b>{mv12}%</b> in twelve months and needs <b>{hurdle}%</b> for holding to win. Closer than it looks, not there.',
    'fx.holding.drifting.high':
        'A <b>{gap} point</b> gap against a <b>{mv12}%</b> drift. The yield is winning that race today.',
    'fx.holding.falling.low':
        'Down <b>{mv12}%</b> against a <b>{hurdle}%</b> bar. Holding dollars has been the right call this year.',
    'fx.holding.falling.mod':
        'A <b>{mv12}%</b> fall has beaten the <b>{hurdle}%</b> needed. Holding won the last year; the next one restarts at <b>{be}</b>.',
    'fx.holding.falling.high':
        'Even a <b>{gap} point</b> yield gap has not kept up with a <b>{mv12}%</b> fall. Break even from here is <b>{be}</b>.',
    'fx.holding.snapback.low':
        'Up <b>{mv3}%</b> in three months. Holding dollars has just cost more than the <b>{gap} point</b> gap ever would.',
    'fx.holding.snapback.mod':
        'The shilling has gained <b>{mv3}%</b> in a quarter, so waiting has given back more than a year of yield gap.',
    'fx.holding.snapback.high':
        'A <b>{mv3}%</b> recovery on top of a <b>{gap} point</b> yield gap. Both sides of the trade moved against holding.',

    // Hedged. No hurdle, so no band in the key.
    'fx.hedged.calm':
        'USD in and USD out means there is no currency position to take. A KES fund pays more on paper and hands you a bill that moves.',
    'fx.hedged.drifting':
        'The pair has moved <b>{mv12}%</b> this year and none of it touched you. That is what matching the currency buys.',
    'fx.hedged.falling':
        'Down <b>{mv12}%</b> over the year. Anyone holding a KES fund against USD costs has felt that; you have not.',
    'fx.hedged.snapback':
        'The shilling has gained <b>{mv3}%</b> in a quarter. Matching your spending currency means neither direction reaches you.',
  };
}

import '../../data/models/fund.dart';
import '../../engine/tax.dart';
import '../format.dart';

/// Insight engine (§4). Pure function: `(fund, peers) → up to 4 Signals`.
/// Deterministic per fund per day via a seeded pick, so wording varies without
/// ever contradicting the data. Templates are the v5 bank; C1 moves them to the
/// Supabase `insight_templates` table (snapshot-shipped, admin-editable) and
/// this in-code bank becomes the fallback.
///
/// The current `Fund` model lacks momentum (d7), liquidity, composition and
/// risk, so those condition keys can't fire yet  they activate automatically
/// once C1 adds the fields. No fabricated movement.

enum SignalTag { strength, watch, note }

class Signal {
  final SignalTag tag;
  final String text;
  const Signal(this.tag, this.text);
}

// Full v5 bank (kept complete for when C1 enables the remaining keys).
const _bank = <String, List<String>>{
  'upBig': [
    '{n} jumped <b>{d} pts this week</b>  the sharpest move in its class.',
    "A <b>+{d} pt week</b> puts {n} among the market's fastest risers.",
    'Momentum is with {n}: <b>up {d} pts in 7 days</b>, well past the pack.',
  ],
  'upSmall': [
    '{n} drifted up {d} pts this week  steady, in line with the sector.',
    'A quiet +{d} pt week for {n}; the whole class is grinding higher.',
    '{n} added {d} pts over 7 days  nothing dramatic, direction is right.',
  ],
  'downBig': [
    '{n} shed <b>{d} pts this week</b>  repricing faster than peers after the CBK move.',
    'A <b>\u2212{d} pt week</b>: {n} is absorbing the base-rate trim ahead of the pack.',
  ],
  'downSmall': [
    '{n} eased {d} pts as older high-coupon paper matured. Nothing structural.',
    'A soft \u2212{d} pt week for {n}; normal churn, not a trend break.',
  ],
  'flat': [
    "{n} has held {r}% steady  low drama, and that's the point of this instrument.",
    'No movement at {n} this week; the rate is pinned at {r}%.',
  ],
  'top1': [
    'Highest gross yield in its class right now at <b>{r}%</b> ({net}% net).',
    'Leads its category: <b>{r}%</b> gross, {net}% after tax  top of the table.',
  ],
  'liqFast': [
    'Liquidity is the edge: <b>{liq}</b>  fastest access in the peer set.',
    "<b>{liq}</b>  near-instant access most rivals can't match.",
  ],
  'minLow': [
    'Entry from just <b>{min}</b>  the most accessible ticket in the class.',
    'A <b>{min}</b> minimum makes this the easiest first position here.',
  ],
  'minHigh': [
    'Entry needs <b>KES {min}</b>  the steepest minimum in the set.',
    'The <b>KES {min}</b> ticket prices out smaller savers; the yield is the compensation.',
  ],
  'feeHigh': [
    'Management fee of <b>{fee}</b> runs above the 2.00% peer norm  it eats into the net.',
    'Watch the <b>{fee}</b> fee: higher than peers, and it compounds against you.',
  ],
  'taxfree': [
    'Coupon is <b>tax-free</b>  the effective yield beats taxed paper by roughly 3 pts.',
    'No withholding tax here: the {r}% you see is closer to what you keep.',
  ],
  'tbillHeavy': [
    '<b>{tb}% of the book is T-bills</b>  riding elevated auction rates while they last.',
    'A T-bill-heavy book ({tb}%) tracks the auctions closely, up and down.',
  ],
  'corpHeavy': [
    '<b>{cp}% corporate paper</b>  pays a premium over peers but adds credit exposure.',
    "The {cp}% corporate slice is why the yield is fat; it's also where the risk lives.",
  ],
  'usd': [
    'Earns in dollars and tracks US short rates, not CBK  a hedge as much as a yield.',
  ],
  'sacco': [
    'Payouts are <b>annual, declared at the AGM</b>  not a daily-accruing rate like an MMF.',
  ],
  'bondLock': [
    'Money is locked to maturity; secondary exit exists but is price-sensitive.',
  ],
};

int _hash(String s) {
  var h = 5381;
  for (final ch in s.codeUnits) {
    h = ((h << 5) + h + ch) & 0x7fffffff;
  }
  return h;
}

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month}-${d.day}';
}

final _tags = RegExp(r'</?b>');
String _strip(String s) => s.replaceAll(_tags, '');

/// Build up to 4 signals for [f], using [peers] (same snapshot) for class rank.
List<Signal> buildSignals(
  Fund f,
  List<Fund> peers, {
  Map<String, List<String>>? bank,
}) {
  final b = (bank != null && bank.isNotEmpty) ? bank : _bank;
  final seed = _hash(f.id + _today());
  final r = f.currentRate;
  final out = <Signal>[];

  String fill(String s) {
    final net = f.taxFree ? (r ?? 0) : Tax.net(r ?? 0);
    return s
        .replaceAll('{n}', f.name)
        .replaceAll('{r}', (r ?? 0).toStringAsFixed(2))
        .replaceAll('{net}', net.toStringAsFixed(2))
        .replaceAll(
          '{min}',
          f.minInvest != null ? withCommas(f.minInvest!) : '',
        )
        .replaceAll(
          '{fee}',
          f.mgmtFee != null ? '${f.mgmtFee!.toStringAsFixed(2)}%' : '',
        );
  }

  void add(SignalTag tag, String key, int off) {
    final list = b[key];
    if (list == null || list.isEmpty) return;
    out.add(Signal(tag, _strip(fill(list[(seed + off) % list.length]))));
  }

  // Class leader (needs peers).
  final cls = peers.where(
    (x) => x.category == f.category && x.currentRate != null,
  );
  if (r != null && cls.length > 1) {
    final best = cls.map((x) => x.currentRate!).reduce((a, b) => a > b ? a : b);
    if (r >= best) add(SignalTag.strength, 'top1', 6);
  }

  // Minimum ticket.
  final mv = f.minInvest ?? 0;
  if (mv > 0 && mv <= 1000 && f.currency == 'KES') {
    add(SignalTag.strength, 'minLow', 8);
  }
  if (mv >= 100000 && f.currency == 'KES') add(SignalTag.watch, 'minHigh', 9);

  // Fee.
  if ((f.mgmtFee ?? 0) >= 2.25) add(SignalTag.watch, 'feeHigh', 10);

  // Tax-free.
  if (f.taxFree) add(SignalTag.strength, 'taxfree', 11);

  // Class notes.
  if (f.category == 'mmf_usd') add(SignalTag.note, 'usd', 14);
  if (f.category == 'sacco') add(SignalTag.watch, 'sacco', 15);
  if (f.category == 'bond') add(SignalTag.note, 'bondLock', 16);

  return out.take(4).toList();
}

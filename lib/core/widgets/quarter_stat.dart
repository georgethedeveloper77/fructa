import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared pieces for the two CMA quarterly surfaces: the Markets fund-market
/// card and the Stocks NSE header. Both render a figure that was struck at a
/// quarter end and sits beside figures that were not, so they must look alike
/// and must state their period the same way. Kept in core so the two cannot
/// drift, and so neither feature has to import the other.

const _monthNames = [
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

/// A signed period move.
///
/// Deliberately a pill rather than bare coloured text. Bare coloured text is
/// how the stock tiles render a DAY change, and these are QUARTER changes; the
/// two must not look like the same measurement sitting in different rows.
class DeltaPill extends StatelessWidget {
  const DeltaPill({
    super.key,
    required this.pct,
    this.compact = false,
    this.digits = 2,
  });

  final double pct;
  final bool compact;
  final int digits;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final up = pct >= 0;
    final col = c.delta(pct);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: compact ? 13 : 15,
            color: col,
          ),
          Text(
            '${pct.abs().toStringAsFixed(digits)}%',
            style: TextStyle(
              color: col,
              fontFamily: fructaFonts.mono,
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 3755.44 -> "3,755.44". Grouped by hand: there is no intl dependency here,
/// and a locale-aware separator would fight the tabular mono alignment that
/// every figure column in this app relies on.
String groupedNumber(double v, int digits) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(digits);
  final dot = s.indexOf('.');
  final whole = dot < 0 ? s : s.substring(0, dot);
  final rest = dot < 0 ? '' : s.substring(dot);

  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${neg ? '-' : ''}$buf$rest';
}

/// Compact KES from a raw shilling amount. 851708510285 -> "851.7B" at one
/// digit, "852B" at zero.
String compactKes(double v, {int digits = 1}) {
  if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(digits)}T';
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(digits)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(digits)}M';
  return groupedNumber(v, 0);
}

/// "2026-06-30" -> "Q2 2026". Unparseable passes through unchanged.
///
/// Prefer [monthTag] on anything a user reads. A quarter tag beside a source
/// name gets read as a report edition ("the Q1 report") rather than as the date
/// the figure was struck, which matters here because the CIS data always lags
/// the bulletin that carries it by one quarter. "Mar 2026" cannot be misread.
String quarterTag(String? iso) {
  if (iso == null) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final q = ((int.parse(m.group(2)!) - 1) ~/ 3) + 1;
  return 'Q$q ${m.group(1)}';
}

/// "2026-06-30" -> "30 Jun 2026". Unparseable passes through unchanged.
String prettyDate(String? iso) {
  if (iso == null) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final mo = int.parse(m.group(2)!);
  if (mo < 1 || mo > 12) return iso;
  return '${int.parse(m.group(3)!)} ${_monthNames[mo - 1]} ${m.group(1)}';
}

/// "2026-03-31" -> "Mar 2026". Unparseable passes through unchanged.
///
/// The user-facing period label. See the note on [quarterTag] for why this is
/// the default rather than the quarter form.
String monthTag(String? iso) {
  if (iso == null) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final mo = int.parse(m.group(2)!);
  if (mo < 1 || mo > 12) return iso;
  return '${_monthNames[mo - 1]} ${m.group(1)}';
}

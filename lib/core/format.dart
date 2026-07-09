import 'package:flutter/services.dart';

String withCommas(num v) {
  final neg = v < 0;
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

String money(String currency, num v) => '$currency ${withCommas(v)}';

/// Thousands-grouped amount that can keep [decimals] fractional digits, used to
/// seed an amount field with a pre-formatted value (KES = 0, USD = 2).
String groupedAmount(num v, {int decimals = 0}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
  final frac = dot == -1 ? '' : fixed.substring(dot); // includes the '.'
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}$buf$frac';
}

/// Groups the integer part with thousands separators as the user types, keeping
/// a single optional decimal point and at most [decimals] fractional digits.
/// The caret is parked at the end, which reads naturally for amount entry.
///
/// The rest of the app parses these fields with `text.replaceAll(',', '')`, so
/// the injected separators never reach the stored value.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({this.decimals = 2});
  final int decimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Keep digits and the first dot only.
    var cleaned = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final firstDot = cleaned.indexOf('.');
    if (firstDot != -1) {
      final intPart = cleaned.substring(0, firstDot);
      var frac = cleaned.substring(firstDot + 1).replaceAll('.', '');
      if (decimals <= 0) {
        cleaned = intPart; // this currency takes no decimals
      } else {
        if (frac.length > decimals) frac = frac.substring(0, decimals);
        cleaned = '$intPart.$frac';
      }
    }

    final dot = cleaned.indexOf('.');
    final intDigits = dot == -1 ? cleaned : cleaned.substring(0, dot);
    final frac = dot == -1 ? null : cleaned.substring(dot + 1);

    final grouped = _group(intDigits);
    final out = frac == null ? grouped : '$grouped.$frac';

    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }

  String _group(String digits) {
    if (digits.isEmpty) return '';
    // Collapse runs of leading zeros to a single zero (no "007").
    final s = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

String timeAgo(DateTime d) {
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

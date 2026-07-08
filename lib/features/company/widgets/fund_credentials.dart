import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/company.dart';
import '../../../data/models/fund.dart';

/// "Credentials"  the fund-side trust strip: how long it's operated and who
/// independently holds and audits the assets. Custody is manager-level (read
/// from the fund's [Company]); age + objective are the fund's own. The
/// fund-side mirror of the insurer trust signals.
///
/// Renders nothing when none of it is seeded, so an unseeded fund degrades to
/// the prior detail page. Icon-free by design  mono labels, matching the
/// page's `_Facts`/`_Stat3` aesthetic (and the no-emoji/no-glyph rule).
class FundCredentials extends StatelessWidget {
  const FundCredentials(this.fund, this.manager, {super.key});

  final Fund fund;
  final Company? manager;

  static const _months = [
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

  /// "Nov 2017 · 8 years" from inceptionDate, or "Nov 2017" under a year, or
  /// null when there's no parseable inception.
  String? _sinceLabel() {
    final iso = fund.inceptionDate;
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return null;
    final my = '${_months[d.month - 1]} ${d.year}';
    final yrs = fund.yearsOperating;
    if (yrs == null || yrs < 1) return my;
    return '$my \u00b7 $yrs ${yrs == 1 ? 'year' : 'years'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final since = _sinceLabel();
    final rows = <MapEntry<String, String>>[
      if (since != null) MapEntry('OPERATING SINCE', since),
      if (manager?.trustee != null) MapEntry('TRUSTEE', manager!.trustee!),
      if (manager?.custodian != null)
        MapEntry('CUSTODIAN', manager!.custodian!),
      if (manager?.auditor != null) MapEntry('AUDITOR', manager!.auditor!),
    ];
    final objective = fund.objective;
    final hasObjective = objective != null && objective.isNotEmpty;
    if (rows.isEmpty && !hasObjective) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Text(
            'CREDENTIALS',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasObjective)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 16,
                      bottom: rows.isEmpty ? 16 : 6,
                    ),
                    child: Text(
                      objective,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                for (var i = 0; i < rows.length; i++)
                  _CredRow(
                    k: rows[i].key,
                    v: rows[i].value,
                    divider: i < rows.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow({required this.k, required this.v, required this.divider});
  final String k;
  final String v;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              k,
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

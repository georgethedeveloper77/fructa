import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/insurer.dart';
import 'insure_common.dart';

/// The trust surface for an insurer, built ONLY from sourced public data:
///
///   license status   IRA register / public notices
///   financial rating GCR national scale
///   combined ratio   AKI annual market report (below 100 = underwriting profit)
///   complaints       IRA quarterly industry release
///
/// There is no published per-insurer claims-settlement % in Kenya, so we never
/// show one. Every cell hides when its datum is unseeded, and the whole panel
/// hides when nothing is seeded, so the screen degrades to honest silence
/// rather than filling space with invented numbers.
class InsurerTrustPanel extends StatelessWidget {
  const InsurerTrustPanel(this.insurer, {super.key});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final i = insurer;
    if (!i.hasTrustData) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!i.canWriteNewBusiness) _StatusBanner(insurer: i),
        InsureH2(t('insure.trust.title'), small: t('insure.trust.sub')),
        _TrustGrid(insurer: i),
        if (i.dataSource != null) InsureFoot(i.dataSource!),
      ],
    );
  }
}

/// A hard regulatory warning. An insurer under statutory management cannot
/// write new business, so the app must warn instead of quietly comparing it.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final closed = insurer.licenseStatus == 'closed';
    final title =
        closed ? t('insure.trust.closed') : t('insure.trust.statMgmt');
    final body = closed
        ? t('insure.trust.closedBody')
        : t('insure.trust.statMgmtBody');

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.down.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.down.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: c.down),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: c.down,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        color: c.muted, fontSize: 12, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The seeded trust cells, laid out two-up. Only what exists is rendered.
class _TrustGrid extends StatelessWidget {
  const _TrustGrid({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    final cells = <Widget>[];

    // Combined ratio: the honest claims-paying proxy. Under 100 is healthy, so
    // the gauge fills toward 100 and turns green below it, red above.
    if (i.combinedRatio != null) {
      final cr = i.combinedRatio!;
      cells.add(_GaugeCell(
        value: cr,
        good: cr < 100,
        label: t('insure.trust.combined'),
        note: cr < 100
            ? t('insure.trust.combinedGood')
            : t('insure.trust.combinedBad'),
        asOf: i.ratiosAsOf,
      ));
    }

    if (i.financialRating != null) {
      cells.add(_StatCell(
        value: i.financialRating!,
        label: t('insure.trust.rating'),
        note: [
          if (i.ratingAgency != null) i.ratingAgency!,
          if (i.ratingOutlook != null) i.ratingOutlook!,
        ].join(' \u00b7 '),
        asOf: i.ratingAsOf,
      ));
    }

    if (i.complaintsCount != null) {
      final resolved = i.complaintsResolved;
      cells.add(_StatCell(
        value: '${i.complaintsCount}',
        label: t('insure.trust.complaints'),
        note: resolved == null
            ? t('insure.trust.complaintsNote')
            : t('insure.trust.complaintsResolved', {'n': '$resolved'}),
        asOf: i.complaintsPeriod,
      ));
    }

    if (i.marketSharePct != null) {
      cells.add(_StatCell(
        value: '${i.marketSharePct!.toStringAsFixed(1)}%',
        label: t('insure.trust.share'),
        note: t('insure.trust.shareNote'),
        asOf: i.ratiosAsOf,
      ));
    }

    if (i.licenseYear != null) {
      cells.add(_StatCell(
        value: '${i.licenseYear}',
        label: t('insure.trust.licensed'),
        note: t('insure.trust.licensedNote'),
      ));
    }

    if (cells.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        children: [
          for (var r = 0; r < cells.length; r += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cells[r]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: r + 1 < cells.length
                        ? cells[r + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          if (i.iraClassCodes.isNotEmpty) _ClassCodes(codes: i.iraClassCodes),
        ],
      ),
    );
  }
}

/// A plain value cell (rating, complaints, share, licensed year).
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    this.note,
    this.asOf,
  });
  final String value;
  final String label;
  final String? note;
  final String? asOf;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: c.faint,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note!,
                style: TextStyle(color: c.muted, fontSize: 10.5, height: 1.3)),
          ],
          if (asOf != null) ...[
            const SizedBox(height: 3),
            Text(asOf!,
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9,
                    fontFamily: fructaFonts.mono)),
          ],
        ],
      ),
    );
  }
}

/// Combined-ratio cell with a 0-to-100 arc. Green below 100 (underwriting
/// profit), red above (paying out more than it takes in).
class _GaugeCell extends StatelessWidget {
  const _GaugeCell({
    required this.value,
    required this.good,
    required this.label,
    required this.note,
    this.asOf,
  });
  final double value;
  final bool good;
  final String label;
  final String note;
  final String? asOf;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = good ? c.up : c.down;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: c.faint,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(42, 42),
                      painter: _RatioPainter(
                        frac: (value / 130).clamp(0.0, 1.0),
                        color: tint,
                        track: c.line2,
                      ),
                    ),
                    Icon(
                        good
                            ? Icons.trending_down_rounded
                            : Icons.trending_up_rounded,
                        size: 15,
                        color: tint),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('${value.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: c.text,
                      fontFamily: fructaFonts.mono,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(note,
              style: TextStyle(color: c.muted, fontSize: 10.5, height: 1.3)),
          if (asOf != null) ...[
            const SizedBox(height: 3),
            Text(asOf!,
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9,
                    fontFamily: fructaFonts.mono)),
          ],
        ],
      ),
    );
  }
}

class _RatioPainter extends CustomPainter {
  _RatioPainter({required this.frac, required this.color, required this.track});
  final double frac;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RatioPainter old) =>
      old.frac != frac || old.color != color || old.track != track;
}

/// IRA authorized class codes, e.g. 07 Motor Private.
class _ClassCodes extends StatelessWidget {
  const _ClassCodes({required this.codes});
  final List<String> codes;

  static const _labels = <String, String>{
    '01': 'Aviation',
    '02': 'Engineering',
    '03': 'Fire Domestic',
    '04': 'Fire Industrial',
    '05': 'Liability',
    '06': 'Marine',
    '07': 'Motor Private',
    '08': 'Motor Commercial',
    '09': 'Personal Accident',
    '10': 'Theft',
    '11': 'Workmen Comp',
    '12': 'Medical',
    '13': 'Micro-insurance',
    '14': 'Miscellaneous',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final code in codes)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.line),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      fontSize: 10,
                      color: c.muted),
                  children: [
                    TextSpan(
                        text: code,
                        style: TextStyle(
                            color: c.text, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${_labels[code] ?? ''}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

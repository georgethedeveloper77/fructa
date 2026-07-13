import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/insurer.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_motion.dart';
import 'insure_shell.dart';
import 'insurer_detail_page.dart';

enum InsurerFilter { all, motor, travel, rated, flagged }

extension on InsurerFilter {
  String get label => switch (this) {
    InsurerFilter.all => t('insure.dir.all'),
    InsurerFilter.motor => t('insure.motor'),
    InsurerFilter.travel => t('insure.travel'),
    InsurerFilter.rated => t('insure.dir.rated'),
    InsurerFilter.flagged => t('insure.dir.flagged'),
  };

  bool matches(Insurer i) => switch (this) {
    InsurerFilter.all => true,
    InsurerFilter.motor => i.hasMotor,
    InsurerFilter.travel => i.hasTravel,
    InsurerFilter.rated => i.financialRating != null,
    InsurerFilter.flagged => !i.canWriteNewBusiness,
  };
}

/// Every insurer on the IRA register, not just the ones we can price.
///
/// An insurer earns a row here on regulatory standing alone. Where a published
/// rate exists we say so and the row opens a quote flow; where it does not, the
/// row opens an informational page (who they are, their rating, how to reach
/// them). That is the honest shape of the Kenyan market: most insurers do not
/// publish rates, and pretending otherwise would mean inventing numbers.
class InsurerDirectoryPage extends ConsumerStatefulWidget {
  const InsurerDirectoryPage({super.key});

  @override
  ConsumerState<InsurerDirectoryPage> createState() =>
      _InsurerDirectoryPageState();
}

class _InsurerDirectoryPageState extends ConsumerState<InsurerDirectoryPage> {
  final _search = TextEditingController();
  InsurerFilter _filter = InsurerFilter.all;
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const double _motorValue = 3450000;

  void _open(Insurer i) {
    // A quote flow only where a real rate backs it. Otherwise: the facts.
    final route = i.hasMotor
        ? MaterialPageRoute<void>(
            builder: (_) => InsurerDetailPage.motor(i, value: _motorValue),
          )
        : i.hasTravel
        ? MaterialPageRoute<void>(
            builder: (_) =>
                InsurerDetailPage.travel(i, region: 'af', days: 7, pax: 1),
          )
        : MaterialPageRoute<void>(builder: (_) => InsurerDetailPage.info(i));
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(insurersProvider);

    final q = _q.trim().toLowerCase();
    final shown =
        all.where((i) {
            if (!_filter.matches(i)) return false;
            if (q.isEmpty) return true;
            return i.name.toLowerCase().contains(q);
          }).toList()
          // Flagged insurers first (a user searching one must see the warning),
          // then those we can price, then the rest alphabetically.
          ..sort((a, b) {
            final fa = a.canWriteNewBusiness ? 1 : 0;
            final fb = b.canWriteNewBusiness ? 1 : 0;
            if (fa != fb) return fa.compareTo(fb);
            final pa = (a.hasMotor || a.hasTravel) ? 0 : 1;
            final pb = (b.hasMotor || b.hasTravel) ? 0 : 1;
            if (pa != pb) return pa.compareTo(pb);
            return a.name.compareTo(b.name);
          });

    final rated = all.where((i) => i.financialRating != null).length;
    final flaggedCount = all.where((i) => !i.canWriteNewBusiness).length;

    // The register year, taken from the data rather than from a constant, so
    // the kicker cannot outlive the gazette it is quoting. Absent from the
    // snapshot, the kicker simply carries no year.
    final years = all
        .map((i) => i.licenseYear)
        .whereType<int>()
        .toList(growable: false);
    final year = years.isEmpty
        ? null
        : years.reduce((a, b) => a > b ? a : b);

    return InsureScaffold(
      navTitle: t('insure.dir.title'),
      children: [
        InsureHead(
          // A register year is a fact that does not move, so the node does not
          // pulse. Pulsing it would promise a liveness the datum does not have.
          kicker: year == null
              ? t('insure.dir.kickerPlain')
              : t('insure.dir.kicker', {'y': '$year'}),
          live: false,
          title: t('insure.dir.h1'),
          sub: t('insure.dir.sub'),
        ),
        // The three numbers that justify the page existing. FLAGGED is the one
        // nobody else in Kenya will show a retail buyer, so it is tinted red
        // even at zero: it is the reason to scroll.
        KpiStrip([
          KpiCell(label: t('insure.dir.kpiLicensed'), value: '${all.length}'),
          KpiCell(label: t('insure.dir.kpiRated'), value: '$rated'),
          KpiCell(
            label: t('insure.dir.kpiFlagged'),
            value: '$flaggedCount',
            color: flaggedCount > 0 ? c.down : null,
          ),
        ]),
        _SearchBox(
          controller: _search,
          count: all.length,
          onChanged: (v) => setState(() => _q = v),
        ),
        // Pills, not segments. The count is the information: "Flagged 3" is a
        // reason to tap, "Flagged" is a label.
        FilterPills<InsurerFilter>(
          selected: _filter,
          onTap: (f) => setState(() => _filter = f),
          pills: [
            for (final f in InsurerFilter.values)
              PillDatum(
                value: f,
                label: f.label,
                count: all.where(f.matches).length,
                danger: f == InsurerFilter.flagged,
              ),
          ],
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Text(
              t('insure.dir.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.6),
            ),
          )
        else
          for (var k = 0; k < shown.length; k++)
            _InsurerRow(insurer: shown[k], index: k, onTap: () => _open(shown[k])),
        if (shown.isNotEmpty) InsureFoot(t('insure.dir.foot')),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.count,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int count;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: c.faint),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textInputAction: TextInputAction.search,
              cursorColor: c.accent,
              style: TextStyle(color: c.text, fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                // The hint carries the size of the set. "Search" asks for
                // faith; "Search 38 insurers" tells the reader what is in
                // there before they type a letter.
                hintText: t('insure.dir.searchN', {'n': '$count'}),
                hintStyle: TextStyle(color: c.faint, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsurerRow extends StatelessWidget {
  const _InsurerRow({
    required this.insurer,
    required this.onTap,
    required this.index,
  });

  final Insurer insurer;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    final flagged = !i.canWriteNewBusiness;
    final rung = GradeScale.rungFor(i.financialRating);
    final priced = i.hasMotor || i.hasTravel;

    return Stagger(
      index: index,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A red node on the mark itself, not just a tag further along the
              // row. A reader scanning 38 logos should be able to spot the
              // seized ones without reading a word.
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InsurerLogo(i, size: 44),
                    if (flagged)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: c.down,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.bg, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13.5,
                        height: 1.3,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        if (flagged)
                          _Tag(
                            label: t('insure.dir.noNewBusiness'),
                            fg: c.down,
                            bg: c.downSoft,
                            icon: Icons.close,
                          ),
                        if (i.hasMotor)
                          _Tag(
                            label: t('insure.motor'),
                            fg: c.accent,
                            bg: c.accentSoft,
                          ),
                        if (i.hasTravel)
                          _Tag(
                            label: t('insure.travel'),
                            fg: c.accent,
                            bg: c.accentSoft,
                          ),
                        // "No published rate" rather than "info only". The
                        // reason we cannot quote them is theirs, not ours, and
                        // the row should say so.
                        if (!priced && !flagged)
                          _Tag(
                            label: t('insure.dir.noRate'),
                            fg: c.faint,
                            bg: c.s3,
                          ),
                        if (i.marketSharePct != null)
                          _Tag(
                            label: t('insure.dir.share', {
                              'p': i.marketSharePct!.toStringAsFixed(1),
                            }),
                            fg: c.faint,
                            bg: c.s3,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The grade as a position, not just letters. "AA+(KE)" means
              // nothing to someone who has never read a GCR scale; seven rungs
              // with five filled means "high" at a glance. An unrated insurer
              // gets the word, never an empty ladder that would read as a bad
              // score rather than an absent one.
              SizedBox(
                width: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (i.financialRating != null) ...[
                      Text(
                        i.financialRating!,
                        style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (rung != null) ...[
                        const SizedBox(height: 5),
                        GradeScale(filled: rung, color: c.up),
                      ],
                    ] else
                      Text(
                        t('insure.dir.unrated'),
                        style: TextStyle(color: c.faint, fontSize: 10.5),
                      ),
                    const SizedBox(height: 5),
                    Icon(Icons.chevron_right, size: 17, color: c.faint),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.fg,
    required this.bg,
    this.icon,
  });

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 9, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

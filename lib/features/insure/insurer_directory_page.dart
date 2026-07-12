import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurer.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
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
            builder: (_) => InsurerDetailPage.motor(i, value: _motorValue))
        : i.hasTravel
            ? MaterialPageRoute<void>(
                builder: (_) => InsurerDetailPage.travel(i,
                    region: 'af', days: 7, pax: 1))
            : MaterialPageRoute<void>(
                builder: (_) => InsurerDetailPage.info(i));
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final all = ref.watch(insurersProvider);

    final q = _q.trim().toLowerCase();
    final shown = all.where((i) {
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

    final priced = all.where((i) => i.hasMotor || i.hasTravel).length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            DisplayHeader(
              title: t('insure.dir.title'),
              sub: t('insure.dir.sub', {
                'n': '${all.length}',
                'priced': '$priced',
              }),
            ),
            _SearchBox(
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
            ),
            _FilterPills(
              filter: _filter,
              onFilter: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(t('insure.dir.empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.muted)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 32),
                      itemCount: shown.length,
                      itemBuilder: (_, k) => _InsurerRow(
                        insurer: shown[k],
                        onTap: () => _open(shown[k]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(13),
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
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: InputBorder.none,
                hintText: t('insure.dir.search'),
                hintStyle: TextStyle(color: c.faint, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.filter, required this.onFilter});
  final InsurerFilter filter;
  final ValueChanged<InsurerFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in InsurerFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onFilter(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: f == filter ? c.text : c.s1,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: f == filter ? c.text : c.line),
                    ),
                    child: Text(f.label,
                        style: TextStyle(
                            color: f == filter ? c.bg : c.muted,
                            fontSize: 12.5,
                            fontWeight: f == filter
                                ? FontWeight.w600
                                : FontWeight.w500)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One insurer: logo, name, what it offers, its rating, and a warning flag if
/// the regulator has taken it over.
class _InsurerRow extends StatelessWidget {
  const _InsurerRow({required this.insurer, required this.onTap});
  final Insurer insurer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    final flagged = !i.canWriteNewBusiness;

    final tags = <String>[
      if (i.hasMotor) t('insure.motor'),
      if (i.hasTravel) t('insure.travel'),
    ];

    return GestureDetector(
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
            FundLogo(
              domain: i.logoDomain,
              seed: i.name,
              size: 42,
              brandColor: insurerBrand(context, i),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.name,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      if (flagged)
                        _Tag(
                          label: t('insure.dir.noNewBusiness'),
                          fg: c.down,
                          bg: c.down.withValues(alpha: 0.14),
                        ),
                      for (final tag in tags)
                        _Tag(
                            label: tag,
                            fg: c.accent,
                            bg: c.accentSoft),
                      if (tags.isEmpty && !flagged)
                        _Tag(
                          label: t('insure.dir.infoOnly'),
                          fg: c.muted,
                          bg: c.s3,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (i.financialRating != null)
                  Text(i.financialRating!,
                      style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 13,
                          fontWeight: FontWeight.w700))
                else
                  Text(t('insure.dir.unrated'),
                      style: TextStyle(color: c.faint, fontSize: 11)),
                const SizedBox(height: 3),
                Icon(Icons.chevron_right, size: 18, color: c.faint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                color: fg, fontSize: 9.5, fontWeight: FontWeight.w600)),
      );
}

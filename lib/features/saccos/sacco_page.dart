import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/holding.dart';
import '../../data/models/sacco.dart';
import '../../data/providers.dart';
import '../alerts/alerts_page.dart';

/// SACCO detail.
///
/// This page ARGUES rather than lists, and it argues one thing:
///
///   The bigger percentage is not the bigger cheque.
///
/// A SACCO declares two rates a year. The dividend on share capital is nearly
/// always the higher number, and it is the one on every poster, every SMS and
/// every AGM headline in Kenya. It is paid on share capital, which is CAPPED.
/// The interest on deposits is the lower number and it is paid on savings, which
/// are not capped, and which are usually five to ten times larger.
///
/// So the page leads with both rates side by side, and then immediately spends a
/// whole block doing the arithmetic, with the user's own balances, because the
/// arithmetic is the argument and no amount of labelling substitutes for it.
class SaccoPage extends ConsumerStatefulWidget {
  const SaccoPage(this.sacco, {super.key});

  final Sacco sacco;

  @override
  ConsumerState<SaccoPage> createState() => _SaccoPageState();
}

class _SaccoPageState extends ConsumerState<SaccoPage> {
  // The worked example is STATIC, and matches the approved mockup.
  //
  // I had built this with two sliders. It was a better toy and a worse argument.
  // The point of the block is a single sentence the reader cannot wriggle out of
  // (the 13 percent pays 6.5 times what the 20 percent pays), and a slider hands
  // them a dial to make that sentence go away. Fixed, typical, honest amounts: a
  // member some years in, with far more saved than they hold in shares, which is
  // what a SACCO member's balance sheet actually looks like.
  static const double _kDeposits = 500000;
  static const double _kShares = 50000;

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  String _pct(double v) => '${v.toStringAsFixed(2)}%';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// The licence has an expiry and the badge says so, because "SASRA licensed"
  /// with no date is a claim about today that ages badly on a page nobody
  /// rebuilds. A malformed date returns the raw string rather than throwing.
  /// `sasraLicensedUntil` arrives from the snapshot as a raw ISO string, not a
  /// DateTime. Parse it here rather than at the call site, and on anything
  /// unparseable fall back to the raw value: a badge reading "SASRA licensed to
  /// 2026-12-31" is ugly, and a crash on a fund detail page is not.
  String _licenceUntil(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null || d.month < 1 || d.month > 12) return iso;
    return '${_months[d.month - 1]} ${d.year}';
  }

  String _commas(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.sacco;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Long society names ("Kenya National Police DT Sacco Society") blow the
        // bar, and the house rule forbids truncation, so scale down instead.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            s.displayName,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: t('nav.alerts'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AlertsPage()),
            ),
            icon: Icon(Icons.notifications_none, color: c.muted),
          ),
          // FOLLOW STAR GOES HERE, and is deliberately absent until push.dart
          // gains a SACCO tag namespace (Push.followSacco / unfollowSacco, and
          // a SaccoSubscriptionsNotifier beside the stock one).
          //
          // The star is a SUBSCRIPTION, not a bookmark: its whole job is to
          // drive a push. Reusing the fund namespace would put a SACCO id into
          // the same set that emit-events targets for fund rate changes, where
          // it would never match anything, and the user would have tapped a
          // star that silently subscribed them to nothing.
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _hero(context, s),
          _rates(context, s),
          if (s.hasBothRates) _callout(context, s),
          if (s.hasBothRates) _workedExample(context, s),
          _pots(context, s),
          if (s.rateHistory.length >= 2) _history(context, s),
          _institution(context, s),
          _joining(context, s),
          _cta(context, s),
          _sources(context, s),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  Widget _hero(BuildContext context, Sacco s) {
    final c = context.c;
    // Where it is and how big it is, in one mono line, exactly as the mockup has
    // it. Both parts are optional: a null county or tier drops out rather than
    // printing an empty separator.
    final sub = [
      if (s.physicalLocation != null && s.physicalLocation!.isNotEmpty)
        s.physicalLocation!
      else if (s.county != null && s.county!.isNotEmpty)
        s.county!,
      if (s.tier != null) 'Tier ${s.tier}',
    ].join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          // `domain` was null, which threw away a free logo for every society.
          // FundLogo resolves a bare domain through a favicon service when no
          // hosted logo_url is set, and every SACCO row already carries a
          // `website`. So: hosted logo if we have uploaded one, otherwise the
          // society's own favicon, otherwise the brand-tinted monogram. Nothing
          // to upload before this page looks right.
          FundLogo(
            domain: s.website,
            logoUrl: s.logoUrl,
            seed: s.name,
            size: 52,
            brandColor: s.brandColor,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.displayName,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: TextStyle(
                      color: c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (s.joinable)
                      _tag(
                        context,
                        Icons.how_to_reg_outlined,
                        'Open to anyone',
                        c.up,
                        c.upSoft,
                      )
                    else if (s.bondUnknown)
                      _tag(
                        context,
                        Icons.help_outline,
                        'Membership not confirmed',
                        c.faint,
                        c.s2,
                      )
                    else
                      _tag(
                        context,
                        Icons.block_outlined,
                        s.bondNote == null
                            ? 'Membership restricted'
                            : 'Members: ${s.bondNote}',
                        c.faint,
                        c.s2,
                      ),
                    if (s.sasraLicensedUntil != null)
                      _tag(
                        context,
                        Icons.verified_user_outlined,
                        'SASRA licensed to ${_licenceUntil(s.sasraLicensedUntil!)}',
                        c.muted,
                        c.s2,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(
    BuildContext context,
    IconData icon,
    String label,
    Color fg,
    Color bg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── The two rates ────────────────────────────────────────────────────────
  // Side by side, same size, both labelled with the pot they are paid on. The
  // deposit card is tinted with the up colour because it is the number that
  // decides the money; the dividend card wears the accent because it is the
  // number people arrive already believing in.

  Widget _rates(BuildContext context, Sacco s) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      // IntrinsicHeight, and it is not optional.
      //
      // The two cards MUST be the same height. A taller card reads as the more
      // important number, and 'DIVIDEND ON SHARES' wraps differently from
      // 'INTEREST ON DEPOSITS', so without this the dividend card grows and the
      // layout starts making the exact argument this page exists to refute.
      //
      // CrossAxisAlignment.stretch is how you get equal heights, but stretch
      // means 'fill the cross axis', and inside a ListView the Row's cross axis
      // is UNBOUNDED. Fill infinity and you get the infinite-height assertion.
      // IntrinsicHeight measures the taller card first and hands the Row a real
      // number to stretch into. It costs one extra layout pass on two small
      // cards, and it is the only way to have both the equal heights and the
      // scroll.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _rateCard(
                context,
                label: 'INTEREST\nON DEPOSITS',
                value: s.interestOnDeposits,
                sub: 'Paid on your savings',
                fg: c.up,
                border: c.up.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _rateCard(
                context,
                label: 'DIVIDEND\nON SHARES',
                value: s.dividendOnShareCapital,
                sub: 'Paid on your shares',
                fg: c.accent,
                border: c.line,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rateCard(
    BuildContext context, {
    required String label,
    required double? value,
    required String sub,
    required Color fg,
    required Color border,
  }) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              height: 1.4,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            // A missing rate is a dash, never a zero. We do not know it.
            value == null ? '\u2014' : '${value.toStringAsFixed(2)}%',
            style: TextStyle(
              color: value == null ? c.faint : fg,
              fontFamily: fructaFonts.mono,
              fontSize: 27,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: TextStyle(color: c.muted, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── The worked example ───────────────────────────────────────────────────
  //
  // The single most important block on the page, and the reason the page exists.
  //
  // Rendered only when BOTH rates are present. A half-drawn version of this
  // argument, with one rate missing, is worse than no version, because it would
  // let a reader conclude something from an arithmetic we did not finish.

  /// The callout. Its own block, above the arithmetic, exactly as approved.
  ///
  /// It states the claim in words first, and only then proves it with numbers.
  /// The other way round, the reader meets a table of figures with no idea what
  /// they are meant to notice about it.
  Widget _callout(BuildContext context, Sacco s) {
    final c = context.c;
    final dep = s.interestOnDeposits!;
    final div = s.dividendOnShareCapital!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      // The gold rule down the left edge is a CHILD, not a border side.
      //
      // It was a Border with a gold left and grey everywhere else, under a
      // borderRadius. Flutter will not paint that: a rounded border has to
      // decide what colour the corner is, where the gold meets the grey, and
      // there is no right answer, so it asserts rather than guess. Hence
      // "A borderRadius can only be given on borders with uniform colors".
      //
      // So: one uniform grey border with the radius, and the gold rule drawn
      // inside it, clipped to the same radius. Same picture, and it is now a
      // shape the framework can actually paint.
      child: Container(
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line2),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 2, color: c.accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The bigger percentage is not the bigger cheque',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your shares are capped. Your savings are not. So the '
                        '${_pct(dep)} almost always pays you more than the '
                        '${_pct(div)}, because it is paid on a much larger pile '
                        'of money.',
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12.5,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The worked example. The proof.
  ///
  /// Rendered only when BOTH rates are present. A half-drawn version of this
  /// argument, with one rate missing, is worse than no version at all, because
  /// it lets a reader conclude something from an arithmetic we did not finish.
  Widget _workedExample(BuildContext context, Sacco s) {
    final c = context.c;
    final e = s.earningsOn(deposits: _kDeposits, shares: _kShares);
    if (e == null) return const SizedBox.shrink();

    final ratio = e.fromShares > 0 ? e.fromDeposits / e.fromShares : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IF YOU SAVED THIS MUCH',
              style: TextStyle(
                color: c.faint,
                fontSize: 9.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 11),
            _payRow(
              context,
              noun: 'Deposits',
              amount: _kDeposits,
              rate: s.interestOnDeposits!,
              pays: e.fromDeposits,
              fg: c.up,
            ),
            const SizedBox(height: 8),
            _payRow(
              context,
              noun: 'Shares',
              amount: _kShares,
              rate: s.dividendOnShareCapital!,
              pays: e.fromShares,
              fg: c.accent,
            ),
            if (ratio != null && ratio > 1) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: c.line),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
                  children: [
                    const TextSpan(text: 'The savings rate pays you '),
                    TextSpan(
                      text: '${ratio.toStringAsFixed(1)} times more',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' than the headline dividend rate does. That is why '
                          'Fructa ranks SACCOs on deposit interest.',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One line of the arithmetic: the pot, the amount in it, the rate on it, and
  /// what that actually pays. Every term is on the row, so nothing has to be
  /// taken on trust.
  Widget _payRow(
    BuildContext context, {
    required String noun,
    required double amount,
    required double rate,
    required double pays,
    required Color fg,
  }) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
              children: [
                TextSpan(text: '$noun '),
                TextSpan(
                  text: _commas(amount),
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' at ${_pct(rate)}'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _commas(pays),
          style: TextStyle(
            color: fg,
            fontFamily: fructaFonts.mono,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // ── The two pots ─────────────────────────────────────────────────────────

  Widget _pots(BuildContext context, Sacco s) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Where your money goes'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _pot(
            context,
            icon: Icons.savings_outlined,
            name: 'Deposits',
            rate: s.interestOnDeposits,
            fg: c.up,
            body:
                'Your savings. They earn interest each year and they are what lets you borrow. You cannot withdraw them while you remain a member. You get them back when you leave the SACCO.',
            facts: [
              if (s.loanMultiple != null)
                'Borrow up to ${s.loanMultiple!.toStringAsFixed(s.loanMultiple! % 1 == 0 ? 0 : 1)}x',
              if (s.minMonthlyDepositKes != null)
                'From KES ${_commas(s.minMonthlyDepositKes!)} a month',
              'Locked',
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _pot(
            context,
            icon: Icons.pie_chart_outline,
            name: 'Share capital',
            rate: s.dividendOnShareCapital,
            fg: c.accent,
            body:
                'Your ownership stake in the SACCO. It earns a dividend each year. It is not savings and you cannot withdraw it. To get it back you sell your shares to another member.',
            facts: [
              if (s.minShareCapitalKes != null)
                'Minimum KES ${_commas(s.minShareCapitalKes!)}',
              'One vote per member',
            ],
          ),
        ),
      ],
    );
  }

  Widget _pot(
    BuildContext context, {
    required IconData icon,
    required String name,
    required double? rate,
    required Color fg,
    required String body,
    required List<String> facts,
  }) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                rate == null ? '\u2014' : '${rate.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: rate == null ? c.faint : fg,
                  fontFamily: fructaFonts.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 11),
            Divider(height: 1, color: c.line),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in facts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.s2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── AGM history ──────────────────────────────────────────────────────────
  // Both series, both labelled. Bars rather than a line, because these are
  // discrete annual declarations and not a continuous series: a SACCO rate does
  // not move between AGMs, and drawing a line between two years would imply a
  // path through values that never existed.

  Widget _history(BuildContext context, Sacco s) {
    final c = context.c;
    final years = s.rateHistory.reversed.toList(); // oldest first
    var hi = 0.0;
    for (final r in years) {
      final a = r.interestOnDeposits ?? 0;
      final b = r.dividendOnShareCapital ?? 0;
      if (a > hi) hi = a;
      if (b > hi) hi = b;
    }
    if (hi <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          'Rates declared at the AGM',
          caption: 'Financial year',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 12),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _legend(context, c.up, 'Deposits'),
                    const SizedBox(width: 14),
                    _legend(context, c.accent, 'Dividend'),
                  ],
                ),
                const SizedBox(height: 16),
                // The bar area FLEXES; the year label takes what it needs.
                //
                // This was a fixed 92px bar box plus a 7px gap plus a 9.5px line
                // of text inside a 112px SizedBox. That is 113, and it overflowed
                // by exactly the 1 pixel Flutter reported. Bumping the box to 120
                // would have hidden it until the first person turned their font
                // size up, and then it would be back.
                //
                // So the label is measured and the bars take whatever is left.
                // The bars are drawn as a FRACTION of that leftover rather than a
                // pixel height, which is why _bar no longer needs to know how tall
                // the chart is: there is no magic number left to get wrong.
                SizedBox(
                  height: 118,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in years)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _bar(r.interestOnDeposits, hi, c.up),
                                    const SizedBox(width: 3),
                                    _bar(
                                      r.dividendOnShareCapital,
                                      hi,
                                      c.accent,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${r.financialYear}',
                                style: TextStyle(
                                  color: c.faint,
                                  fontFamily: fructaFonts.mono,
                                  fontSize: 9.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A null year renders as no bar at all, not a zero-height one sitting on the
  /// axis. "Not declared" and "declared nothing" are different facts.
  ///
  /// Height is a FRACTION of whatever the chart row turned out to be, not a
  /// pixel count derived from a constant that has to be kept in sync with the
  /// SizedBox above. That constant is what overflowed.
  Widget _bar(double? v, double hi, Color color) {
    if (v == null || v <= 0) return const SizedBox(width: 11);
    final f = (v / hi).clamp(0.02, 1.0);
    return SizedBox(
      width: 11,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: f,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
      ],
    );
  }

  // ── Institution and joining ──────────────────────────────────────────────

  Widget _institution(BuildContext context, Sacco s) {
    final rows = <(String, String)>[
      if (s.totalAssetsKes != null)
        ('Total assets', 'KES ${(s.totalAssetsKes! / 1e9).toStringAsFixed(1)}B'),
      if (s.depositsKes != null)
        ('Member deposits', 'KES ${(s.depositsKes! / 1e9).toStringAsFixed(1)}B'),
      if (s.members != null) ('Members', _commas(s.members!)),
      if (s.branches != null) ('Branches', '${s.branches}'),
      if (s.registeredYear != null) ('Registered', '${s.registeredYear}'),
      if (s.county != null) ('County', s.county!),
      if (s.physicalLocation != null) ('Head office', s.physicalLocation!),
      // Only deposit-taking societies are ever published (the snapshot filters
      // on licence_class), so this row is a constant. It is here because it is
      // the fact that makes a savings rate legal to quote at all.
      ('SASRA licence', 'Deposit taking'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'The institution'),
        _rowCard(context, rows),
      ],
    );
  }

  Widget _joining(BuildContext context, Sacco s) {
    final rows = <(String, String)>[
      (
        'Who can join',
        s.joinable
            ? 'Anyone'
            : s.bondUnknown
            ? 'Not confirmed'
            : (s.bondNote ?? 'Restricted membership'),
      ),
      if (s.registrationFeeKes != null)
        ('Registration fee', 'KES ${_commas(s.registrationFeeKes!)}'),
      if (s.minShareCapitalKes != null)
        ('Minimum share capital', 'KES ${_commas(s.minShareCapitalKes!)}'),
      if (s.minMonthlyDepositKes != null)
        ('Minimum monthly deposit', 'KES ${_commas(s.minMonthlyDepositKes!)}'),
      if (s.depositNoticeDays != null)
        (
          'Notice to withdraw deposits',
          '${s.depositNoticeDays} days after exit',
        ),
      if (s.hasFosa == true) ('Front office (FOSA)', 'Yes'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Joining'),
        _rowCard(context, rows),
      ],
    );
  }

  Widget _rowCard(BuildContext context, List<(String, String)> rows) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        rows[i].$1,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (i != rows.length - 1) Divider(height: 1, color: c.line),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cta(BuildContext context, Sacco s) {
    final c = context.c;
    final held = ref
        .watch(holdingsProvider)
        .any((h) => h.isSacco && h.fundId == s.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          if (s.website != null && s.website!.isNotEmpty) ...[
            Material(
              color: c.accent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(s.website),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Visit ${s.displayName}',
                        style: TextStyle(
                          color: c.onAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.north_east, size: 15, color: c.onAccent),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],

          // The ghost CTA. Tracking, not transacting: Fructa never opens an
          // account and never moves money, so this records what you already
          // have with the society. The wording says "my portfolio" and not
          // "join", because the two are not the same act and a SACCO is the one
          // asset class where confusing them has a cost.
          Material(
            color: c.s1,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _addToPortfolio(context, s),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line2),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (held) ...[
                      Icon(Icons.check, size: 15, color: c.up),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      held ? 'Update my deposits' : 'Add to my portfolio',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Record DEPOSITS, never share capital.
  ///
  /// A member holds two balances at a SACCO and they behave nothing alike:
  /// deposits earn the interest rate and are the pot this whole page is about;
  /// share capital earns the dividend, is capped, and is not really savings at
  /// all. A portfolio tracker that added them together would produce a number
  /// that means nothing, so the sheet asks for one of them and says which.
  Future<void> _addToPortfolio(BuildContext context, Sacco s) async {
    final c = context.c;
    final existing = ref
        .read(holdingsProvider)
        .where((h) => h.isSacco && h.fundId == s.id)
        .firstOrNull;

    final ctrl = TextEditingController(
      text: existing == null
          ? ''
          : groupedAmount(existing.balance, decimals: 0),
    );

    final amount = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: c.s1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              s.displayName,
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Fructa does not open accounts or move money. This only records '
              'what you already have with the society.',
              style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            Text(
              'YOUR DEPOSITS',
              style: TextStyle(
                color: c.faint,
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              inputFormatters: [ThousandsInputFormatter(decimals: 0)],
              style: TextStyle(color: c.text, fontSize: 20),
              decoration: InputDecoration(
                prefixText: 'KES  ',
                prefixStyle: TextStyle(color: c.muted, fontSize: 18),
                filled: true,
                fillColor: c.s2,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.accent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Savings only. Do not include your share capital: it earns the '
              'dividend, not the interest rate, and adding the two together '
              'gives a number that means nothing.',
              style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final v = double.tryParse(
                    ctrl.text.replaceAll(',', ''),
                  );
                  if (v == null || v < 0) return;
                  Navigator.of(sheetCtx).pop(v);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
    if (amount == null) return;

    await ref
        .read(holdingsProvider.notifier)
        .setBalance(s.id, 'KES', amount, kind: HoldingKind.sacco);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${s.displayName} added to your portfolio.')),
      );
  }

  /// Provenance, per document. Three different sources feed this page and they
  /// refresh on three different schedules, so saying "sources: SASRA" would be
  /// a half-truth. Name each one against what it actually supplied.
  Widget _sources(BuildContext context, Sacco s) {
    final c = context.c;
    final lines = <String>[
      if (s.rateYear != null)
        'Rates declared at the annual general meeting for the year ended 31 December ${s.rateYear}.${s.rateSourceDoc == null ? '' : ' Source: ${s.rateSourceDoc}.'}',
      if (s.financialsAsOf != null)
        'Institution figures from the SASRA Sacco Supervision Annual Report.',
      'Licence status from the SASRA register of licensed Sacco societies.',
      'Deposits are not withdrawable while you remain a member. Fructa does not hold your money and does not open accounts.',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: c.faint),
                const SizedBox(width: 6),
                Text(
                  'WHERE THIS COMES FROM',
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 9.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < lines.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.only(top: 7, right: 8),
                    decoration: BoxDecoration(
                      color: c.faint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 11.5,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
              if (i != lines.length - 1) const SizedBox(height: 7),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, {String? caption}) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: c.faint,
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (caption != null)
            Text(
              caption,
              style: TextStyle(color: c.faint, fontSize: 10.5),
            ),
        ],
      ),
    );
  }
}

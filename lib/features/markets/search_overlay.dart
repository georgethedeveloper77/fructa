import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categories.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/models/insurer.dart';
import '../../data/models/sacco.dart';
import '../../data/models/stock.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../company/company_page.dart';
import '../insure/insure_overlay.dart';
import '../saccos/sacco_page.dart';
import '../stocks/stock_page.dart';

/// v5 `#searchOv`  global search across funds, insurers, stocks and SACCOs. Flat rows:
/// 36px logo · highlighted name · manager sub · category chip · mono rate.
/// Empty query shows admin-controlled suggestion chips (`search.suggestions`
/// via remote config) plus the top five funds ("Suggested"), matching the
/// mock's default slice. No search telemetry  on-device, nothing logged.
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _controller = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String q) => setState(() => _q = q.trim());

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final funds = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final insurers = ref.watch(insurersProvider);
    final stocks = ref.watch(stocksProvider);
    // Every published society, joinable or not. The open-bond filter belongs on
    // the SACCO tab, where someone is browsing; if a person types a society's
    // name they want to be told about it, including that they cannot join it.
    final saccos = ref.watch(saccosProvider);

    final results = _search(funds, insurers, stocks, saccos, _q);
    final suggestions = cfg.stringList('search.suggestions', const [
      'Money market',
      'Tax-free',
      'USD',
      'T-bills',
    ]);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── sr-top: box + Cancel ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: c.s1,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: c.line2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 18, color: c.faint),
                          const SizedBox(width: 9),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              onChanged: _set,
                              style: TextStyle(color: c.text, fontSize: 15),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                hintText: cfg.string(
                                  'search.placeholder',
                                  'Fund, insurer, or category\u2026',
                                ),
                                hintStyle: TextStyle(color: c.faint),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),

            // ── sr-body ──────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 30),
                children: [
                  if (_q.isEmpty && suggestions.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in suggestions)
                          GestureDetector(
                            onTap: () {
                              _controller.text = s;
                              _set(s);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: c.s2,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.line2),
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text(
                      _q.isEmpty
                          ? 'Suggested'
                          : '${results.length} result${results.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (results.isEmpty && _q.isNotEmpty)
                    Disclaimer('Nothing matches \u201c$_q\u201d.')
                  else
                    for (final r in results) _row(context, r),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── matching (mirrors v5 doSearch: name + manager + category label) ─────
  //
  // Stocks carry NO rate into search, deliberately. The empty-query "Suggested"
  // slice ranks by rate, and a stock's dividend yield is not the same kind of
  // number as an MMF yield: it needs a licensed price, it is not guaranteed,
  // and ranking one against the other would invite a comparison that is not
  // real. So a stock is findable by name or ticker, shows a dash where the rate
  // would be, and never competes in the yield ranking.
  //
  // SACCOs are the harder case, and they are handled differently from stocks.
  //
  // A SACCO DOES have a rate of exactly the right kind: interest on deposits is
  // an annual percentage paid on money you have saved, the same shape as an MMF
  // yield. Blanking it would be a lie by omission, so the row shows it, with a
  // lock beside it.
  //
  // But it does NOT compete in the empty-query "Suggested" ranking, and that is
  // the whole point of `rankable`. Suggested is an unprompted, unqualified list
  // of the five best numbers in the app. SACCOs pay 11 to 13 percent while money
  // market funds pay 9 to 10, so they would simply BE the suggestions, every
  // time, for a user who typed nothing and asked for nothing. The app would open
  // its search and quietly recommend five places you cannot withdraw your money
  // from. Whether locked money may outrank liquid money is a decision, it is
  // taken deliberately in the All tab behind a config flag and a tax gate, and
  // an unranked suggestion strip is not the place to take it by accident.
  //
  // Search for one and you find it. Ask for nothing and you are not sold one.
  List<_Hit> _search(
    List<Fund> funds,
    List<Insurer> insurers,
    List<Stock> stocks,
    List<Sacco> saccos,
    String q,
  ) {
    final needle = q.toLowerCase();
    final hits = <_Hit>[
      for (final f in funds)
        _Hit.fund(f, categoryLabel(f.category).toUpperCase()),
      for (final i in insurers) _Hit.insurer(i),
      for (final s in stocks) _Hit.stock(s, t('category.stock').toUpperCase()),
      for (final s in saccos) _Hit.sacco(s),
    ];
    if (needle.isEmpty) {
      final top = hits.where((h) => h.rankable && h.rate != null).toList()
        ..sort((a, b) => b.rate!.compareTo(a.rate!));
      return top.take(5).toList();
    }
    return hits
        .where(
          (h) => '${h.title} ${h.sub} ${h.tag}'.toLowerCase().contains(needle),
        )
        .toList();
  }

  Widget _row(BuildContext context, _Hit h) {
    final c = context.c;
    // A stock's logo rides on the stock row itself (no company_id indirection),
    // so it is resolved on the hit rather than through logoUrlProvider.
    final logoUrl = h.stock != null
        ? h.stock!.logoUrl
        : h.sacco != null
        ? h.sacco!.logoUrl
        : (h.fund != null ? ref.watch(logoUrlProvider(h.fund!.id)) : null);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => switch (h) {
              _ when h.fund != null => CompanyPage(h.fund!),
              _ when h.stock != null => StockPage(h.stock!),
              _ when h.sacco != null => SaccoPage(h.sacco!),
              _ => const InsureOverlay(),
            },
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            FundLogo(
              domain: h.logoDomain,
              logoUrl: logoUrl,
              seed: h.sub,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlight(
                    h.title,
                    base: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _highlight(
                    h.sub,
                    base: TextStyle(color: c.faint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: c.s3,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                h.tag,
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 8.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // The lock rides WITH the number, not somewhere else on the row.
            // A SACCO's 13 percent sits directly under an MMF's 9.8 in these
            // results, and the one thing that distinguishes them is that you
            // cannot get the first one back until you resign your membership.
            // Put that anywhere other than beside the figure and the eye skips
            // it.
            if (h.sacco != null) ...[
              Icon(Icons.lock_outline, size: 11, color: c.faint),
              const SizedBox(width: 3),
            ],
            Text(
              h.rate != null ? '${h.rate!.toStringAsFixed(2)}%' : '\u2014',
              style: TextStyle(
                color: h.rate != null ? c.text : c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: h.fund != null ? 14 : 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// v5 `<mark>`  highlight query matches in accent-soft.
  Widget _highlight(String text, {required TextStyle base}) {
    final c = context.c;
    if (_q.isEmpty) return Text(text, style: base);
    final needle = _q.toLowerCase();
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final at = lower.indexOf(needle, i);
      if (at < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
      spans.add(
        TextSpan(
          text: text.substring(at, at + needle.length),
          style: base.copyWith(
            backgroundColor: c.accentSoft,
            color: c.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      i = at + needle.length;
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _Hit {
  _Hit.fund(Fund f, this.tag)
    : fund = f,
      insurer = null,
      stock = null,
      sacco = null,
      title = f.name,
      sub = f.manager,
      rate = f.currentRate,
      rankable = true,
      logoDomain = f.logoDomain;

  _Hit.insurer(Insurer i)
    : fund = null,
      insurer = i,
      stock = null,
      sacco = null,
      title = i.name,
      sub = i.name,
      tag = 'INSURER',
      rate = i.motorRate,
      rankable = false,
      logoDomain = i.logoDomain;

  /// Ticker rides in `sub`, so typing "SCOM" finds Safaricom.
  /// `rate` is deliberately null: see _search.
  _Hit.stock(Stock s, this.tag)
    : fund = null,
      insurer = null,
      stock = s,
      sacco = null,
      title = s.name,
      sub = s.sector != null ? '${s.sector} \u00b7 ${s.ticker}' : s.ticker,
      rate = null,
      rankable = false,
      logoDomain = null;

  /// The rate is interest on DEPOSITS, never the dividend. The dividend is the
  /// bigger percentage and the smaller cheque, and a search row has no space to
  /// explain that, so it does not show a number it cannot label.
  ///
  /// `rankable` is false: a SACCO is findable, but it never appears in the
  /// unprompted "Suggested" five. See the note in _search.
  _Hit.sacco(Sacco s)
    : fund = null,
      insurer = null,
      stock = null,
      sacco = s,
      title = s.displayName,
      sub = s.county != null && s.county!.isNotEmpty
          ? 'SACCO \u00b7 ${s.county}'
          : 'SACCO',
      tag = 'SACCO',
      rate = s.interestOnDeposits,
      rankable = false,
      logoDomain = null;

  final Fund? fund;
  final Insurer? insurer;
  final Stock? stock;
  final Sacco? sacco;
  final String title;
  final String sub;
  final String tag;
  final double? rate;

  /// May this hit compete in the empty-query "Suggested" ranking? Only funds
  /// may: it is a list of yields on money you can actually withdraw.
  final bool rankable;

  final String? logoDomain;
}

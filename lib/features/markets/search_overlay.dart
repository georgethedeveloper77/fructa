import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categories.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/models/insurer.dart';
import '../../data/models/stock.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../company/company_page.dart';
import '../insure/insure_overlay.dart';
import '../stocks/stock_page.dart';

/// v5 `#searchOv`  global search across funds, insurers and stocks. Flat rows:
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

    final results = _search(funds, insurers, stocks, _q);
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
  List<_Hit> _search(
    List<Fund> funds,
    List<Insurer> insurers,
    List<Stock> stocks,
    String q,
  ) {
    final needle = q.toLowerCase();
    final hits = <_Hit>[
      for (final f in funds)
        _Hit.fund(f, categoryLabel(f.category).toUpperCase()),
      for (final i in insurers) _Hit.insurer(i),
      for (final s in stocks) _Hit.stock(s, t('category.stock').toUpperCase()),
    ];
    if (needle.isEmpty) {
      final top = hits.where((h) => h.rate != null).toList()
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
        : (h.fund != null ? ref.watch(logoUrlProvider(h.fund!.id)) : null);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => switch (h) {
              _ when h.fund != null => CompanyPage(h.fund!),
              _ when h.stock != null => StockPage(h.stock!),
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
      title = f.name,
      sub = f.manager,
      rate = f.currentRate,
      logoDomain = f.logoDomain;

  _Hit.insurer(Insurer i)
    : fund = null,
      insurer = i,
      stock = null,
      title = i.name,
      sub = i.name,
      tag = 'INSURER',
      rate = i.motorRate,
      logoDomain = i.logoDomain;

  /// Ticker rides in `sub`, so typing "SCOM" finds Safaricom.
  /// `rate` is deliberately null: see _search.
  _Hit.stock(Stock s, this.tag)
    : fund = null,
      insurer = null,
      stock = s,
      title = s.name,
      sub = s.sector != null ? '${s.sector} \u00b7 ${s.ticker}' : s.ticker,
      rate = null,
      logoDomain = null;

  final Fund? fund;
  final Insurer? insurer;
  final Stock? stock;
  final String title;
  final String sub;
  final String tag;
  final double? rate;
  final String? logoDomain;
}

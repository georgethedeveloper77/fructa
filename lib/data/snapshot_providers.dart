import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/agent.dart';
import 'models/company.dart';
import 'models/fund_composition.dart';
import 'models/insurance_type.dart';
import 'models/insurer.dart';
import 'models/learn.dart';
import 'models/market_event.dart';
import 'models/post.dart';
import 'models/remote_config.dart';
import 'models/sacco.dart';
import 'models/stock.dart';
import 'providers.dart';
import 'snapshot_extras.dart';

/// Parses the v2 sibling arrays out of the SAME cached snapshot body that
/// ratesProvider already fetched. Recomputes whenever a refresh lands (it
/// watches ratesProvider), reading the freshly-written cache. No second fetch,
/// no changes to providers.dart's RatesNotifier.
final snapshotExtrasProvider = Provider<SnapshotExtras>((ref) {
  ref.watch(ratesProvider); // recompute after each refresh
  final body = ref.watch(ratesCacheProvider).snapshot;
  if (body == null) return SnapshotExtras.empty;
  try {
    return SnapshotExtras.parse(body);
  } catch (_) {
    return SnapshotExtras.empty;
  }
});

final companiesProvider = Provider<Map<String, Company>>(
  (ref) => ref.watch(snapshotExtrasProvider).companies,
);

final marketEventsProvider = Provider<List<MarketEvent>>(
  (ref) => ref.watch(snapshotExtrasProvider).events,
);

final insurersProvider = Provider<List<Insurer>>(
  (ref) => ref.watch(snapshotExtrasProvider).insurers,
);

/// Admin-managed Insure home grid. Falls back to the baked Motor+Travel default
/// when the snapshot carries none, so the grid renders before the first publish.
final insuranceTypesProvider = Provider<List<InsuranceType>>((ref) {
  final types = ref.watch(snapshotExtrasProvider).insuranceTypes;
  return types.isEmpty ? InsuranceType.fallback : types;
});

/// Brand colour for a fund, via its company. Null until C1 data is present.
final brandColorProvider = Provider.family<Color?, String>((ref, fundId) {
  final f = ref.watch(fundsByIdProvider)[fundId];
  final cid = f?.companyId;
  if (cid == null) return null;
  return ref.watch(companiesProvider)[cid]?.brandColor;
});

final logoUrlProvider = Provider.family<String?, String>((ref, fundId) {
  final f = ref.watch(fundsByIdProvider)[fundId];
  final cid = f?.companyId;
  if (cid == null) return null;
  return ref.watch(companiesProvider)[cid]?.logoUrl;
});

/// Event-driven momentum delta for a fund (rate_change payload). Null when no
/// recent event  tiles simply show no delta, never a fabricated one.
final fundDeltaProvider = Provider.family<double?, String>(
  (ref, fundId) => ref.watch(snapshotExtrasProvider).deltaFor(fundId),
);

/// CMA holdings breakdown for a fund (quarterly, per the CIS report). Null
/// until the snapshot carries one  the Company "What the fund holds"
/// section hides itself on null, never showing fabricated splits.
final compositionProvider = Provider.family<FundComposition?, String>(
  (ref, fundId) => ref.watch(snapshotExtrasProvider).compositionFor(fundId),
);

/// V6 remote config  admin-edited copy/flags from the snapshot. Every read
/// carries a baked fallback, so this can never break rendering.
final remoteConfigProvider = Provider<RemoteConfig>(
  (ref) => ref.watch(snapshotExtrasProvider).config,
);

/// KES per USD for portfolio conversion. An admin-set `market.usd_kes` (edited
/// in the Config page, rides the snapshot) is authoritative when present, so a
/// stale scraped `fx_rates` row can't produce a wrong total. Falls back to the
/// latest `fx_rates` USD/KES, then null (USD then shown as unavailable rather
/// than converted at a wrong rate).
final usdKesProvider = Provider<double?>((ref) {
  final extras = ref.watch(snapshotExtrasProvider);
  final admin = extras.config.number('market.usd_kes', 0);
  if (admin > 0) return admin;
  return extras.fx['USD/KES'];
});

/// D2 admin-authored learn content (units → lessons → steps). Empty until the
/// snapshot carries it  the Learn surface shows its empty state, never fakes.
final learnProvider = Provider<LearnContent>(
  (ref) => ref.watch(snapshotExtrasProvider).learn,
);

/// D3 blog posts (articles + briefs) from the snapshot, already pinned-first,
/// newest-first. Empty until the snapshot carries any  the Blog surface shows
/// its empty state rather than a fabricated list.
final postsProvider = Provider<List<Post>>(
  (ref) => ref.watch(snapshotExtrasProvider).posts,
);

/// A single post by slug, or null when the snapshot doesn't carry it.
final postBySlugProvider = Provider.family<Post?, String>((ref, slug) {
  for (final p in ref.watch(postsProvider)) {
    if (p.slug == slug) return p;
  }
  return null;
});

/// When the snapshot was last published (local time), or null on a v1/cached
/// body without a stamp. Drives the Markets "Updated …" line honestly.
final snapshotUpdatedProvider = Provider<DateTime?>(
  (ref) => ref.watch(snapshotExtrasProvider).generatedAt,
);

/// Hosted logo for an INSURER, resolved through its company exactly as
/// [logoUrlProvider] does for a fund.
///
/// This was the whole logo bug: every insure surface passed only `logoDomain`
/// to FundLogo and never a `logoUrl`, so an insurer whose company has a real
/// mark in the `logos` bucket still fell through to a monogram. Insurers are
/// rows in `funds`, so they carry `company_id` like any other row; nothing was
/// resolving it.
///
/// Null is a legitimate answer: the 29 insurers seeded straight off the IRA
/// register have no logo and no verified domain, and a monogram is the correct
/// rendering for them. It beats showing another company's mark.
final insurerLogoUrlProvider = Provider.family<String?, String?>((
  ref,
  companyId,
) {
  if (companyId == null) return null;
  return ref.watch(companiesProvider)[companyId]?.logoUrl;
});

/// Agents attached to a company, plus free agents.
final agentsForCompanyProvider = Provider.family<List<Agent>, String?>((
  ref,
  companyId,
) {
  final agents = ref.watch(snapshotExtrasProvider).agents;
  if (companyId == null) return agents.where((a) => a.isFree).toList();
  return agents
      .where((a) => a.isFree || a.companyIds.contains(companyId))
      .toList();
});

// ── Stocks (0047) ───────────────────────────────────────────────────────────

/// NSE-listed equities from the snapshot. Empty until the snapshot carries any,
/// so the Stocks surface shows its empty state rather than a fabricated list.
final stocksProvider = Provider<List<Stock>>(
  (ref) => ref.watch(snapshotExtrasProvider).stocks,
);

final stockByIdProvider = Provider.family<Stock?, String>((ref, id) {
  for (final s in ref.watch(stocksProvider)) {
    if (s.id == id) return s;
  }
  return null;
});

/// CMA-licensed brokers for the "Where to buy" section. Fructa routes out to
/// these and never places a trade.
final brokersProvider = Provider<List<Broker>>(
  (ref) => ref.watch(snapshotExtrasProvider).brokers,
);

/// Whether the snapshot carries licensed NSE prices.
///
/// This is derived from the DATA, not from a local flag: the publisher only
/// emits price fields when `stocks.prices_enabled` is on, so if no stock has a
/// price, the app has no licensed price to show and every price surface hides
/// itself. That means the app can never display market data the backend did not
/// license, even if a build shipped with the price widgets compiled in.
final stockPricesLiveProvider = Provider<bool>((ref) {
  for (final s in ref.watch(stocksProvider)) {
    if (s.hasPrice) return true;
  }
  return false;
});

// ── SACCOs (0062) ───────────────────────────────────────────────────────────

/// SASRA co-operative societies from the snapshot. Empty until the publisher has
/// `saccos.enabled` on, so the SACCO surface shows its empty state rather than a
/// fabricated list.
final saccosProvider = Provider<List<Sacco>>(
  (ref) => ref.watch(snapshotExtrasProvider).saccos,
);

final saccoByIdProvider = Provider.family<Sacco?, String>((ref, id) {
  for (final s in ref.watch(saccosProvider)) {
    if (s.id == id) return s;
  }
  return null;
});

/// Whether the SACCO surface has anything worth showing.
///
/// Derived from the DATA, not from a local flag, exactly as
/// [stockPricesLiveProvider] is. The publisher only emits societies when
/// `saccos.enabled` is on, so if none arrived there is nothing to show and the
/// tab hides itself. A build that shipped with the SACCO widgets compiled in
/// therefore still cannot render a SACCO the backend did not publish.
final saccosLiveProvider = Provider<bool>(
  (ref) => ref.watch(saccosProvider).isNotEmpty,
);

/// The societies that can actually be ranked: they have a declared deposit rate.
///
/// Sorted by that rate, highest first. NOT by the dividend, ever. The dividend is
/// paid on a capped pot of share capital and is nearly always the bigger
/// percentage, so ranking on it would sort the list by the number that matters
/// least, which is precisely the confusion the Learn course exists to undo.
///
/// A society with no declared rate is absent from this list and present in
/// [saccosProvider]. It is not ranked at zero: we do not know its rate, and
/// "unknown" is not "worst".
final rankedSaccosProvider = Provider<List<Sacco>>((ref) {
  final rated = ref
      .watch(saccosProvider)
      .where((s) => s.hasDepositRate)
      .toList();
  rated.sort(
    (a, b) => b.interestOnDeposits!.compareTo(a.interestOnDeposits!),
  );
  return rated;
});

/// Ranked AND joinable. What the SACCO tab leads with, and the only societies
/// eligible for the All league table.
///
/// A society with a brilliant rate and a closed bond is not a better option than
/// one with a duller rate you can actually join; it is not an option at all. An
/// unknown bond counts as not joinable, because SASRA does not publish the bond
/// and guessing "open" sends someone to a society whose membership is shut to
/// them.
final joinableSaccosProvider = Provider<List<Sacco>>(
  (ref) => ref.watch(rankedSaccosProvider).where((s) => s.joinable).toList(),
);

/// Whether SACCOs may enter the All league table beside money market funds and
/// T-bills, where they will usually be the top row.
///
/// Its own switch, separate from `saccos.enabled`, because it is its own
/// decision. A SACCO deposit rate is paid on money you cannot withdraw until you
/// resign your membership. An MMF yield is paid on money you get back in two
/// working days. As numbers they are the same shape. As promises they are not,
/// and the lock badge is the only thing carrying that difference.
final saccosInAllTabProvider = Provider<bool>((ref) {
  if (!ref.watch(saccosLiveProvider)) return false;
  return ref.watch(remoteConfigProvider).flag('saccos.in_all_tab', false);
});

/// Net-of-tax deposit rate for a SACCO, or NULL when we do not know it.
///
/// A SACCO declares its interest GROSS. Every other rate in this app is shown
/// and compounded net, because that is what lands in your account. To convert
/// we need the withholding rate on SACCO deposit interest, and the public
/// sources contradict each other on what it is (5, 10 and 15 percent all appear
/// in reputable places). So `saccos.tax_confirmed` starts false, and while it is
/// false this returns null.
///
/// Null means "no rate", NOT "zero rate". A holding with a null rate is carried
/// FLAT by PortfolioMath: principal, no invented growth. That is the honest
/// answer. The dishonest answer would be to compound the gross figure, which
/// would inflate a blended yield by roughly 1.5 percentage points of tax nobody
/// paid, which is wider than the entire spread between the best and worst money
/// market fund in the country.
///
/// Confirm the rate, flip the flag, and every SACCO holding starts accruing
/// correctly with no code change.
final saccoNetPctProvider = Provider.family<double?, String>((ref, saccoId) {
  final s = ref.watch(saccoByIdProvider(saccoId));
  final gross = s?.interestOnDeposits;
  if (gross == null) return null;

  final cfg = ref.watch(remoteConfigProvider);
  if (!cfg.flag('saccos.tax_confirmed', false)) return null;

  final wht = cfg.number('saccos.wht_deposits_pct', 0);
  if (wht <= 0 || wht >= 100) return gross;
  return gross * (1 - wht / 100);
});

/// What a holding is actually held IN, resolved across both tables.
///
/// The portfolio used to do `fundsById[h.fundId]` in six places and take a
/// `Fund?` everywhere. A SACCO holding fell through every one of them: it
/// rendered as the raw slug, carried no rate, and dropped silently out of the
/// blended yield. Rather than teach six call sites about a second table, they
/// all ask this one question and get one answer.
class HoldingSubject {
  const HoldingSubject({
    required this.name,
    required this.categoryKey,
    this.manager,
    this.ratePercent,
    this.taxFree = false,
    this.logoUrl,
    this.logoDomain,
    this.brandColor,
    this.isSacco = false,
    this.rateUnknown = false,
  });

  final String name;
  final String categoryKey;
  final String? manager;

  /// Already NET where we know it. [taxFree] is therefore true for a SACCO: not
  /// because a SACCO is tax free, but because the tax has already been taken off
  /// upstream and PortfolioMath must not take it off twice.
  final double? ratePercent;
  final bool taxFree;

  final String? logoUrl;
  final String? logoDomain;
  final Color? brandColor;
  final bool isSacco;

  /// A SACCO with a declared rate we cannot yet show net. The holding is carried
  /// flat and the tile says so, rather than showing a number we do not trust.
  final bool rateUnknown;

  /// Deposits are locked until you resign your membership. The one fact that
  /// makes a SACCO rate not comparable to an MMF yield.
  bool get locked => isSacco;
}

/// The subject of a holding: a fund, or a SACCO. Keyed by id AND kind, because
/// the id alone cannot tell them apart and a collision would value someone's
/// savings at an unrelated instrument's rate.
final holdingSubjectProvider =
    Provider.family<HoldingSubject?, ({String id, bool sacco})>((ref, key) {
      if (key.sacco) {
        final s = ref.watch(saccoByIdProvider(key.id));
        if (s == null) return null;
        final net = ref.watch(saccoNetPctProvider(key.id));
        return HoldingSubject(
          name: s.displayName,
          categoryKey: 'sacco',
          manager: s.county,
          // Net where known, else null. Never the gross figure, and never the
          // dividend: the dividend is paid on share capital, which is not what
          // this holding records.
          ratePercent: net,
          taxFree: true, // already net upstream; do not withhold twice
          logoUrl: s.logoUrl,
          logoDomain: s.website,
          brandColor: s.brandColor,
          isSacco: true,
          rateUnknown: s.interestOnDeposits != null && net == null,
        );
      }

      final f = ref.watch(fundsByIdProvider)[key.id];
      if (f == null) return null;
      return HoldingSubject(
        name: f.name,
        categoryKey: f.category,
        manager: f.manager,
        ratePercent: f.currentRate,
        taxFree: f.taxFree,
        logoUrl: ref.watch(logoUrlProvider(f.id)),
        logoDomain: f.logoDomain,
        brandColor: ref.watch(brandColorProvider(f.id)),
      );
    });

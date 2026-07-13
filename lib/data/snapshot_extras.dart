import 'dart:convert';

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

/// Everything in the v2 snapshot beyond `funds` (which keeps flowing through
/// the existing RatesRepository → ratesProvider path unchanged). Parsed
/// defensively: a v1 snapshot (no `schema`) yields empty extras.
class SnapshotExtras {
  final int schema;
  final Map<String, Company> companies;
  final List<Agent> agents;
  final Map<String, double> fx; // pair -> rate, e.g. 'USD/KES'
  final List<MarketEvent> events;
  final Map<String, List<String>> templateBank; // key -> phrasings
  final List<Insurer> insurers;
  final List<InsuranceType> insuranceTypes;
  final Map<String, double> _deltas; // fundId -> latest rate_change delta
  final Map<String, FundComposition> _composition; // fundId -> breakdown
  final RemoteConfig config; // V6 admin-editable copy/flags
  final LearnContent learn; // D2 admin-authored learn content
  final List<Post> posts; // D3 blog posts (articles + briefs)
  final List<Stock> stocks; // NSE-listed equities (0047)
  final List<Broker> brokers; // CMA-licensed stockbrokers (0047)
  final List<Sacco> saccos; // SASRA co-operative societies (0062)
  final DateTime? generatedAt; // snapshot publish time, for the "Updated" stamp

  const SnapshotExtras({
    required this.schema,
    required this.companies,
    required this.agents,
    required this.fx,
    required this.events,
    required this.templateBank,
    this.insurers = const [],
    this.insuranceTypes = const [],
    required Map<String, double> deltas,
    Map<String, FundComposition> composition = const {},
    this.config = RemoteConfig.empty,
    this.learn = LearnContent.empty,
    this.posts = const [],
    this.stocks = const [],
    this.brokers = const [],
    this.saccos = const [],
    this.generatedAt,
  }) : _deltas = deltas,
       _composition = composition;

  static const empty = SnapshotExtras(
    schema: 1,
    companies: {},
    agents: [],
    fx: {},
    events: [],
    templateBank: {},
    insurers: [],
    insuranceTypes: [],
    deltas: {},
    composition: {},
    config: RemoteConfig.empty,
  );

  double? deltaFor(String fundId) => _deltas[fundId];

  /// Holdings breakdown for a fund, or null when the snapshot carries none
  /// the Company "What the fund holds" section hides itself on null.
  FundComposition? compositionFor(String fundId) {
    final c = _composition[fundId];
    return (c == null || c.isEmpty) ? null : c;
  }

  factory SnapshotExtras.parse(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final schema = (m['schema'] as num?)?.toInt() ?? 1;
    if (schema < 2) return empty;

    final companies = <String, Company>{};
    for (final c in (m['companies'] as List? ?? const [])) {
      final co = Company.fromJson((c as Map).cast<String, dynamic>());
      companies[co.id] = co;
    }

    final agents = (m['agents'] as List? ?? const [])
        .map((a) => Agent.fromJson((a as Map).cast<String, dynamic>()))
        .toList();

    final fx = <String, double>{};
    for (final f in (m['fx'] as List? ?? const [])) {
      final row = (f as Map);
      final pair = row['pair'] as String?;
      final rate = (row['rate'] as num?)?.toDouble();
      if (pair != null && rate != null) fx[pair] = rate;
    }

    final events = (m['events'] as List? ?? const [])
        .map((e) => MarketEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final bank = <String, List<String>>{};
    for (final t in (m['insight_templates'] as List? ?? const [])) {
      final row = (t as Map);
      final key = row['key'] as String?;
      final tpl = row['template'] as String?;
      if (key != null && tpl != null) (bank[key] ??= []).add(tpl);
    }

    // Latest rate_change delta per fund (events are newest-first).
    final deltas = <String, double>{};
    for (final e in events) {
      if (e.type == 'rate_change' && e.fundId != null && e.delta != null) {
        deltas.putIfAbsent(e.fundId!, () => e.delta!);
      }
    }

    final insurers = (m['insurers'] as List? ?? const [])
        .map((e) => Insurer.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final insuranceTypes = (m['insurance_types'] as List? ?? const [])
        .map((e) =>
            InsuranceType.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    // Composition  sibling array keyed by fund_id (mirrors the deltas
    // pattern: fund model & rates path untouched).
    final composition = <String, FundComposition>{};
    for (final c in (m['composition'] as List? ?? const [])) {
      final row = (c as Map).cast<String, dynamic>();
      final id = row['fund_id'] as String?;
      if (id == null) continue;
      final fc = FundComposition.fromJson(row);
      if (!fc.isEmpty) composition[id] = fc;
    }

    final learn = m['learn'] is Map
        ? LearnContent.fromJson((m['learn'] as Map).cast<String, dynamic>())
        : LearnContent.empty;

    final posts = (m['posts'] as List? ?? const [])
        .map((e) => Post.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    // Stocks (0047). The price fields inside each Stock are null unless the
    // publisher had `stocks.prices_enabled` on, so nothing here needs to know
    // about the licence: an unlicensed snapshot simply carries no prices and
    // Stock.hasPrice reads false all the way up the widget tree.
    final stocks = (m['stocks'] as List? ?? const [])
        .map((e) => Stock.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final brokers = (m['brokers'] as List? ?? const [])
        .map((e) => Broker.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    // SACCOs (0062). Empty unless the publisher had `saccos.enabled` on, so
    // nothing here needs to know about the switch: a snapshot with SACCOs off
    // simply carries none and every SACCO surface hides itself.
    //
    // A society with no declared rate still arrives. It is a real licensed
    // institution and the directory is worth something on its own; it is kept
    // out of ranked lists by Sacco.hasDepositRate rather than ranked at zero.
    final saccos = (m['saccos'] as List? ?? const [])
        .map((e) => Sacco.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final generatedAt = DateTime.tryParse(
      (m['generated_at'] ?? '') as String,
    )?.toLocal();

    return SnapshotExtras(
      schema: 2,
      learn: learn,
      posts: posts,
      stocks: stocks,
      brokers: brokers,
      saccos: saccos,
      generatedAt: generatedAt,
      companies: companies,
      agents: agents,
      fx: fx,
      events: events,
      templateBank: bank,
      insurers: insurers,
      insuranceTypes: insuranceTypes,
      deltas: deltas,
      composition: composition,
      config: RemoteConfig(
        ((m['config'] as Map?) ?? const {}).cast<String, dynamic>(),
      ),
    );
  }
}

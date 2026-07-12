/// An insurer product (funds row, kind='insurance'). Motor is modelled as a
/// percent-of-value rate with a premium floor. Travel is region-priced
/// ([travelRegions]: a base per-traveller price for ea/af/ww/sch), scaled by
/// trip length and traveller count. The legacy [plans] tiers are kept for
/// back-compat but superseded by the region model.
/// Vehicle class. Kenyan motor is rated separately per class and an insurer may
/// write one and refuse another, so this is a first-class dimension, not a flag.
enum MotorClass {
  private('private', 'Private'),
  commercial('commercial', 'Commercial'),
  psv('psv', 'PSV');

  const MotorClass(this.key, this.label);
  final String key;
  final String label;
}

/// Comprehensive covers your own vehicle plus third parties. TPO (third party
/// only) is the legal minimum: it pays for damage you cause to others, nothing
/// for your own car. TPO is a flat annual figure, so vehicle value is irrelevant.
enum CoverType {
  comprehensive('comprehensive', 'Comprehensive'),
  tpo('tpo', 'Third party only');

  const CoverType(this.key, this.label);
  final String key;
  final String label;
}

/// One rate band of a comprehensive tariff: [rate]% of sum insured, for vehicles
/// valued between [min] and [max]. [max] null means open-ended (top band).
class MotorBand {
  const MotorBand({required this.min, this.max, required this.rate});
  final num min;
  final num? max;
  final double rate;

  bool contains(num value) => value >= min && (max == null || value <= max!);

  static MotorBand? tryParse(Object? v) {
    if (v is! Map) return null;
    final rate = (v['rate'] as num?)?.toDouble();
    if (rate == null) return null;
    return MotorBand(
      min: (v['min'] as num?) ?? 0,
      max: v['max'] as num?,
      rate: rate,
    );
  }
}

/// What an insurer charges for one vehicle class.
///
/// Every field is nullable on purpose. A null is a fact: this insurer does not
/// publish, or does not offer, that cover. It is never a licence to price at
/// zero, and [comprehensivePremium] / [tpoPremium] return null rather than 0 so
/// callers must decide explicitly to exclude the insurer.
class ClassTariff {
  const ClassTariff({
    this.bands = const [],
    this.flatRate,
    this.minPremium,
    this.tpo,
  });

  final List<MotorBand> bands;
  final double? flatRate; // used when no bands are published
  final num? minPremium; // premium floor
  final num? tpo; // flat annual third-party-only premium

  bool get hasComprehensive => bands.isNotEmpty || flatRate != null;
  bool get hasTpo => tpo != null;

  /// The rate that applies to a vehicle of this [value]: the matching band, or
  /// the flat rate, or null if this insurer publishes neither.
  double? rateFor(num value) {
    for (final b in bands) {
      if (b.contains(value)) return b.rate;
    }
    // Value above every published band: the top band still governs, since a
    // tariff's last band is open-ended in practice. Only fall back to flat.
    if (bands.isNotEmpty) return bands.last.rate;
    return flatRate;
  }

  /// Annual comprehensive premium, floored at the published minimum. Null when
  /// the insurer does not write comprehensive for this class.
  double? comprehensivePremium(num value) {
    final rate = rateFor(value);
    if (rate == null) return null;
    final raw = value * rate / 100;
    final rounded = (raw / 100).round() * 100;
    final floor = minPremium?.toDouble();
    if (floor == null) return rounded.toDouble();
    return rounded < floor ? floor : rounded.toDouble();
  }

  /// Annual TPO premium. Null when the insurer does not publish TPO here.
  double? tpoPremium() => tpo?.toDouble();

  static ClassTariff? tryParse(Object? v) {
    if (v is! Map) return null;
    final comp = v['comprehensive'];
    final bands = <MotorBand>[];
    double? flat;
    num? minP;
    if (comp is Map) {
      final raw = comp['bands'];
      if (raw is List) {
        for (final b in raw) {
          final band = MotorBand.tryParse(b);
          if (band != null) bands.add(band);
        }
        bands.sort((a, b) => a.min.compareTo(b.min));
      }
      flat = (comp['rate'] as num?)?.toDouble();
      minP = comp['min_premium'] as num?;
    }
    final t = ClassTariff(
      bands: bands,
      flatRate: flat,
      minPremium: minP,
      tpo: v['tpo'] as num?,
    );
    return (t.hasComprehensive || t.hasTpo) ? t : null;
  }
}

/// The full motor tariff: what this insurer writes, per class.
class MotorTariff {
  const MotorTariff(this.byClass);
  final Map<MotorClass, ClassTariff> byClass;

  ClassTariff? forClass(MotorClass c) => byClass[c];
  bool writes(MotorClass c) => byClass.containsKey(c);
  Iterable<MotorClass> get classes => byClass.keys;
  bool get isEmpty => byClass.isEmpty;

  static MotorTariff? tryParse(Object? v) {
    if (v is! Map) return null;
    final out = <MotorClass, ClassTariff>{};
    for (final c in MotorClass.values) {
      final t = ClassTariff.tryParse(v[c.key]);
      if (t != null) out[c] = t;
    }
    return out.isEmpty ? null : MotorTariff(out);
  }
}

class Insurer {
  final String id;
  final String name;
  final String? companyId;
  final String currency;
  final double? motorRate; // % of vehicle value (legacy flat; see motorTariff)
  /// Per-class tariff (migration 0045). Authoritative when present. The legacy
  /// flat [motorRate] is only a fallback for rows not yet migrated.
  final MotorTariff? motorTariff;
  final num? minPremium;
  final double? excessPct;
  final num? excessMin;
  final int? claimsDays;
  final int? rating; // 1..5 stars
  final List<String> benefits;
  final String? logoDomain;
  final List<TravelPlan> plans; // legacy named tiers

  // IN-3 detail surface (migration 0039).
  final double? settlePct; // IRA claims-paid %
  final int? licensedSince; // year licensed
  final String? phone;
  final String? whatsapp; // wa.me number
  final String? email;
  final String? paybill;
  final String? website;
  final String? brandColor; // hex, e.g. "#4E8FE8" (parsed by the screen)
  final List<InsClass> classes; // IRA authorized classes
  final List<InsSignal> signals; // objective signals
  final TravelRegions? travelRegions; // {ea,af,ww,sch} base per-traveller price
  final String? travelCover; // headline cover, e.g. "KES 5M med"

  // Trust + regulatory surface (migration 0044). Real, sourced values only.
  // There is NO published per-insurer claims-settlement % in Kenya, so
  // [settlePct] above is deprecated and never seeded. The honest proxies are
  // [combinedRatio] (AKI, annual) and [complaintsCount] (IRA, quarterly).
  final String? licenseStatus; // active | statutory_management | closed
  final int? licenseYear;
  final List<String> iraClassCodes; // e.g. ['07','08','12']
  final String? financialRating; // GCR national scale, e.g. "AA-(KE)"
  final String? ratingAgency;
  final String? ratingOutlook;
  final String? ratingAsOf;
  final double? marketSharePct;
  final double? combinedRatio; // %, below 100 = underwriting profit
  final double? gwpKes;
  final String? ratiosAsOf;
  final int? complaintsCount; // null = NOT separately reported, never zero
  final int? complaintsResolved;
  final String? complaintsPeriod;
  final String? dataSource;

  const Insurer({
    required this.id,
    required this.name,
    this.companyId,
    this.currency = 'KES',
    this.motorRate,
    this.motorTariff,
    this.minPremium,
    this.excessPct,
    this.excessMin,
    this.claimsDays,
    this.rating,
    this.benefits = const [],
    this.logoDomain,
    this.plans = const [],
    this.settlePct,
    this.licensedSince,
    this.phone,
    this.whatsapp,
    this.email,
    this.paybill,
    this.website,
    this.brandColor,
    this.classes = const [],
    this.signals = const [],
    this.travelRegions,
    this.travelCover,
    this.licenseStatus,
    this.licenseYear,
    this.iraClassCodes = const [],
    this.financialRating,
    this.ratingAgency,
    this.ratingOutlook,
    this.ratingAsOf,
    this.marketSharePct,
    this.combinedRatio,
    this.gwpKes,
    this.ratiosAsOf,
    this.complaintsCount,
    this.complaintsResolved,
    this.complaintsPeriod,
    this.dataSource,
  });

  bool get hasMotor => motorRate != null || (motorTariff?.isEmpty == false);

  /// The tariff to price from. Rows migrated by 0045 carry a real [motorTariff];
  /// anything still on the legacy flat rate is treated as a private-car-only
  /// comprehensive tariff, which is what that column always meant.
  MotorTariff get tariff {
    final t = motorTariff;
    if (t != null && !t.isEmpty) return t;
    if (motorRate == null) return const MotorTariff({});
    return MotorTariff({
      MotorClass.private: ClassTariff(
        flatRate: motorRate,
        minPremium: minPremium,
      ),
    });
  }

  /// Does this insurer write [cls] at all?
  bool writesClass(MotorClass cls) => tariff.writes(cls);

  /// Does it offer [cover] for [cls]?
  bool offers(MotorClass cls, CoverType cover) {
    final t = tariff.forClass(cls);
    if (t == null) return false;
    return cover == CoverType.tpo ? t.hasTpo : t.hasComprehensive;
  }

  /// The annual premium, or NULL when this insurer does not write that class or
  /// does not publish that cover.
  ///
  /// Null is load-bearing. Callers must drop the insurer from the comparison,
  /// never coerce to 0, or we would show a company as "cheapest" precisely
  /// because we do not know what it charges.
  double? quote(num value, {required MotorClass cls, required CoverType cover}) {
    final t = tariff.forClass(cls);
    if (t == null) return null;
    return cover == CoverType.tpo
        ? t.tpoPremium()
        : t.comprehensivePremium(value);
  }

  /// The rate that produced a comprehensive quote, for the "3.00% of value" line.
  double? rateFor(num value, MotorClass cls) =>
      tariff.forClass(cls)?.rateFor(value);

  num? minPremiumFor(MotorClass cls) => tariff.forClass(cls)?.minPremium;
  bool get hasTravel => travelRegions != null && travelRegions!.isNotEmpty;

  /// Under statutory management or closed: cannot write new business. The UI
  /// must warn rather than sell. Unknown status is treated as fine (not a
  /// silent accusation) since older rows may predate the trust fields.
  bool get canWriteNewBusiness =>
      licenseStatus == null || licenseStatus == 'active';
  bool get underStatutoryManagement =>
      licenseStatus == 'statutory_management';

  /// Any trust datum worth rendering. Nothing seeded means the panel hides.
  bool get hasTrustData =>
      licenseStatus != null ||
      financialRating != null ||
      combinedRatio != null ||
      complaintsCount != null ||
      marketSharePct != null;

  /// Underwriting profitability (AKI). Below 100 means premiums covered claims
  /// plus expenses. Our public proxy for claims-paying soundness; it is NOT a
  /// settlement rate and must never be labelled as one.
  bool get underwritesProfitably =>
      combinedRatio != null && combinedRatio! < 100;

  /// Legacy entry point: private-car comprehensive. Retained so existing call
  /// sites keep compiling; new code should use [quote], which can say "no".
  double premium(num value) =>
      quote(value, cls: MotorClass.private, cover: CoverType.comprehensive) ??
      _legacyPremium(value);

  double _legacyPremium(num value) {
    final rate = motorRate ?? 0;
    final raw = value * rate / 100;
    final rounded = (raw / 100).round() * 100;
    final floor = (minPremium ?? 37500).toDouble();
    return rounded < floor ? floor : rounded.toDouble();
  }

  /// Travel price for a booking: base(region) x day-multiplier x travellers,
  /// rounded to the nearest 50. Null when the region carries no base price.
  /// Multiplier tiers: <=7d x1, <=14d x1.6, <=30d x2.4, else x3.6.
  double? travelPrice(String region, {int days = 7, int pax = 1}) {
    final base = travelRegions?.priceFor(region);
    if (base == null) return null;
    final mult = days <= 7
        ? 1.0
        : days <= 14
        ? 1.6
        : days <= 30
        ? 2.4
        : 3.6;
    final raw = base.toDouble() * mult;
    return ((raw / 50).round() * 50 * pax).toDouble();
  }

  /// Cheapest region base, for "from KES X / trip" labels.
  num? get travelFrom => travelRegions?.minPrice;

  /// e.g. "2.5% . min 15k"
  String get excessLabel {
    final parts = <String>[];
    if (excessPct != null) parts.add('${excessPct!.toStringAsFixed(1)}%');
    if (excessMin != null) {
      final k = excessMin! >= 1000
          ? '${(excessMin! / 1000).round()}k'
          : '$excessMin';
      parts.add('min $k');
    }
    return parts.join(' \u00b7 ');
  }

  factory Insurer.fromJson(Map<String, dynamic> j) => Insurer(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    companyId: j['company_id'] as String?,
    currency: (j['currency'] ?? 'KES') as String,
    motorRate: (j['motor_rate'] as num?)?.toDouble(),
    motorTariff: MotorTariff.tryParse(j['motor_tariff']),
    minPremium: j['min_premium'] as num?,
    excessPct: (j['excess_pct'] as num?)?.toDouble(),
    excessMin: j['excess_min'] as num?,
    claimsDays: (j['claims_days'] as num?)?.toInt(),
    rating: (j['rating'] as num?)?.toInt(),
    benefits: ((j['benefits'] as List?) ?? const []).cast<String>(),
    logoDomain: j['logo_domain'] as String?,
    plans: ((j['plans'] as List?) ?? const [])
        .map((p) => TravelPlan.fromJson((p as Map).cast<String, dynamic>()))
        .toList(),
    settlePct: (j['settle_pct'] as num?)?.toDouble(),
    licensedSince: (j['licensed_since'] as num?)?.toInt(),
    phone: j['phone'] as String?,
    whatsapp: j['whatsapp'] as String?,
    email: j['email'] as String?,
    paybill: j['paybill'] as String?,
    website: j['website'] as String?,
    brandColor: j['brand_color'] as String?,
    classes: ((j['classes'] as List?) ?? const [])
        .map((c) => InsClass.fromJson((c as Map).cast<String, dynamic>()))
        .toList(),
    signals: ((j['signals'] as List?) ?? const [])
        .map((s) => InsSignal.fromJson((s as Map).cast<String, dynamic>()))
        .toList(),
    travelRegions: j['travel_regions'] is Map
        ? TravelRegions.fromJson(
            (j['travel_regions'] as Map).cast<String, dynamic>(),
          )
        : null,
    travelCover: j['travel_cover'] as String?,
    licenseStatus: j['license_status'] as String?,
    licenseYear: (j['license_year'] as num?)?.toInt(),
    iraClassCodes:
        ((j['ira_class_codes'] as List?) ?? const []).map((v) => '$v').toList(),
    financialRating: j['financial_rating'] as String?,
    ratingAgency: j['rating_agency'] as String?,
    ratingOutlook: j['rating_outlook'] as String?,
    ratingAsOf: j['rating_as_of'] as String?,
    marketSharePct: (j['market_share_pct'] as num?)?.toDouble(),
    combinedRatio: (j['combined_ratio'] as num?)?.toDouble(),
    gwpKes: (j['gwp_kes'] as num?)?.toDouble(),
    ratiosAsOf: j['ratios_as_of'] as String?,
    complaintsCount: (j['complaints_count'] as num?)?.toInt(),
    complaintsResolved: (j['complaints_resolved'] as num?)?.toInt(),
    complaintsPeriod: j['complaints_period'] as String?,
    dataSource: j['data_source'] as String?,
  );
}

/// Legacy named travel tier. Superseded by [TravelRegions] but retained so a
/// snapshot carrying old `plans` data still parses.
class TravelPlan {
  final String name;
  final num price;
  const TravelPlan({required this.name, required this.price});

  factory TravelPlan.fromJson(Map<String, dynamic> j) => TravelPlan(
    name: (j['name'] ?? '') as String,
    price: (j['price'] as num?) ?? 0,
  );
}

/// Region base prices per traveller for a standard (<=7 day) trip. Keys:
/// ea (East Africa), af (Africa), ww (Worldwide), sch (Schengen).
class TravelRegions {
  static const keys = ['ea', 'af', 'ww', 'sch'];
  final Map<String, num> prices;
  const TravelRegions(this.prices);

  bool get isNotEmpty => prices.values.any((v) => v > 0);

  num? priceFor(String region) {
    final v = prices[region];
    return (v != null && v > 0) ? v : null;
  }

  num? get minPrice {
    final xs = prices.values.where((v) => v > 0);
    return xs.isEmpty ? null : xs.reduce((a, b) => a < b ? a : b);
  }

  factory TravelRegions.fromJson(Map<String, dynamic> j) => TravelRegions({
    for (final k in keys)
      if (j[k] is num) k: j[k] as num,
  });
}

/// An IRA-authorized insurance class chip, e.g. code "07", label "Motor Priv".
class InsClass {
  final String code;
  final String label;
  const InsClass({required this.code, required this.label});

  factory InsClass.fromJson(Map<String, dynamic> j) => InsClass(
    code: (j['code'] ?? '') as String,
    label: (j['label'] ?? '') as String,
  );
}

/// An objective, editor-written signal. [tag] is one of STRENGTH, WATCH, NOTE
/// and drives both the label and the colour on the detail screen.
class InsSignal {
  final String tag; // STRENGTH | WATCH | NOTE
  final String label;
  final String text;
  const InsSignal({required this.tag, required this.label, required this.text});

  factory InsSignal.fromJson(Map<String, dynamic> j) {
    final tag = ((j['tag'] ?? 'NOTE') as String).toUpperCase();
    return InsSignal(
      tag: tag,
      label: (j['label'] ?? tag) as String,
      text: (j['text'] ?? '') as String,
    );
  }
}

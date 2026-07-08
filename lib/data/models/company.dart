import 'package:flutter/material.dart';

Color? parseHexColor(String? s) {
  if (s == null || s.isEmpty) return null;
  var h = s.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

class Company {
  final String id;
  final String name;
  final String type; // fund_manager | insurer | sacco | government
  final Color? brandColor;
  final String? logoUrl;
  final String? website;
  final double? aumKes; // scheme AUM, CMA Table 1 (0017)
  final double? marketShare; // % of total CIS AUM (0017)
  final String? aumAsOf; // YYYY-MM-DD quarter end

  // Custody chain (snapshot 0026)  manager-family trust signals. Nullable;
  // surfaced on the fund detail credentials strip, hidden when unseeded.
  final String? trustee;
  final String? custodian;
  final String? auditor;

  const Company({
    required this.id,
    required this.name,
    required this.type,
    this.brandColor,
    this.logoUrl,
    this.website,
    this.aumKes,
    this.marketShare,
    this.aumAsOf,
    this.trustee,
    this.custodian,
    this.auditor,
  });

  factory Company.fromJson(Map<String, dynamic> j) => Company(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    type: (j['type'] ?? 'fund_manager') as String,
    brandColor: parseHexColor(j['brand_color'] as String?),
    logoUrl: j['logo_url'] as String?,
    website: j['website'] as String?,
    aumKes: (j['aum_kes'] as num?)?.toDouble(),
    marketShare: (j['market_share'] as num?)?.toDouble(),
    aumAsOf: j['aum_as_of'] as String?,
    trustee: j['trustee'] as String?,
    custodian: j['custodian'] as String?,
    auditor: j['auditor'] as String?,
  );
}

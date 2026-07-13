import 'package:flutter/material.dart';

import 'company.dart' show parseHexColor;

/// One year's rates, as declared at the annual general meeting.
///
/// TWO rates, and they are not interchangeable. Keeping them as separate,
/// separately-named fields is the entire point of this class: the moment there
/// is one field that could hold either number, something will put the bigger one
/// in it.
class SaccoRate {
  /// The year that ENDED. A March 2026 AGM declaring for the year to
  /// 31 December 2025 is financialYear 2025.
  final int financialYear;

  /// Paid on member SAVINGS, which are uncapped. The number the app ranks on,
  /// because it is the one that decides how much money a member receives.
  final double? interestOnDeposits;

  /// Paid on member SHARE CAPITAL, which is capped. Nearly always the bigger
  /// percentage and nearly always the smaller cheque. Display only.
  final double? dividendOnShareCapital;

  final String? declaredOn; // YYYY-MM-DD, the AGM
  final String? sourceUrl;
  final String? sourceDoc;

  const SaccoRate({
    required this.financialYear,
    this.interestOnDeposits,
    this.dividendOnShareCapital,
    this.declaredOn,
    this.sourceUrl,
    this.sourceDoc,
  });

  factory SaccoRate.fromJson(Map<String, dynamic> j) => SaccoRate(
    financialYear: (j['financial_year'] as num).toInt(),
    interestOnDeposits: (j['interest_on_deposits'] as num?)?.toDouble(),
    dividendOnShareCapital: (j['dividend_on_share_capital'] as num?)?.toDouble(),
    declaredOn: j['declared_on'] as String?,
    sourceUrl: j['source_url'] as String?,
    sourceDoc: j['source_doc'] as String?,
  );
}

/// A SASRA-regulated co-operative society.
///
/// Deliberately NOT a Fund. A Fund has one yield. A SACCO has two rates paid on
/// two different pots of money, and flattening that into a single `currentRate`
/// is exactly the mistake the product exists to correct.
///
/// A member with 500,000 in deposits at 13% and 50,000 in shares at 20% earns
/// 65,000 from the 13% and 10,000 from the 20%. The bigger percentage pays the
/// smaller cheque, every time, because it is paid on a capped pot. Every SACCO
/// marketing headline in Kenya leads with the dividend. Fructa does not.
///
/// THE TWO INVARIANTS, both enforced here rather than left to the widget layer:
///
///   1. There is no `rate` getter. Not a convenience one, not a "primary" one.
///      Any such getter is one refactor away from being the number a tile prints
///      without a label, and an unlabelled SACCO percentage is a lie about which
///      pot it came from. Widgets ask for [interestOnDeposits] or for
///      [dividendOnShareCapital] and therefore have to know which one they mean.
///
///   2. [locked] is a constant, not a parsed field. Deposits are not withdrawable
///      while you remain a member: that is what a SACCO IS, and there is no row
///      where it is false. Reading it from JSON would create a parse default that
///      a refactor could flip, and would let a malformed row present locked money
///      as liquid.
class Sacco {
  // Identity and regulation.
  final String id;
  final String name; // verbatim from the SASRA register
  final String displayName; // short form for tiles
  final String? sasraLicensedUntil;
  final int? tier;

  // Membership. This matters MORE than the rate: a society you cannot join has
  // no business outranking one you can.
  final String bond; // open | closed | unknown
  final String? bondNote; // 'University of Nairobi staff'
  final bool joinable; // bond == 'open'. Unknown is NOT joinable.

  // Location and contact.
  final String? county;
  final String? physicalLocation;
  final int? branches;
  final String? website;
  final String? phone;
  final String? email;

  // Brand.
  final String? logoUrl;
  final Color? brandColor;
  final String? about;

  // The two rates, from the most recent declared year.
  final double? interestOnDeposits;
  final double? dividendOnShareCapital;
  final int? rateYear;
  final String? rateDeclaredOn;
  final String? rateSourceUrl;
  final String? rateSourceDoc;

  /// Every declared year, newest first. Drives the AGM history chart.
  final List<SaccoRate> rateHistory;

  // Joining terms.
  final double? registrationFeeKes;
  final double? minShareCapitalKes;
  final double? minMonthlyDepositKes;
  final double? loanMultiple; // borrow up to Nx your deposits
  final int? depositNoticeDays;
  final bool? hasFosa; // null means not checked, which is not the same as no

  // The institution, from the SASRA supervision report.
  final double? totalAssetsKes;
  final double? depositsKes;
  final int? members;
  final int? registeredYear;
  final String? financialsAsOf;

  const Sacco({
    required this.id,
    required this.name,
    required this.displayName,
    this.sasraLicensedUntil,
    this.tier,
    this.bond = 'unknown',
    this.bondNote,
    this.joinable = false,
    this.county,
    this.physicalLocation,
    this.branches,
    this.website,
    this.phone,
    this.email,
    this.logoUrl,
    this.brandColor,
    this.about,
    this.interestOnDeposits,
    this.dividendOnShareCapital,
    this.rateYear,
    this.rateDeclaredOn,
    this.rateSourceUrl,
    this.rateSourceDoc,
    this.rateHistory = const [],
    this.registrationFeeKes,
    this.minShareCapitalKes,
    this.minMonthlyDepositKes,
    this.loanMultiple,
    this.depositNoticeDays,
    this.hasFosa,
    this.totalAssetsKes,
    this.depositsKes,
    this.members,
    this.registeredYear,
    this.financialsAsOf,
  });

  factory Sacco.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '') as String;
    return Sacco(
      id: j['id'] as String,
      name: name,
      displayName: (j['display_name'] as String?) ?? name,
      sasraLicensedUntil: j['sasra_licensed_until'] as String?,
      tier: (j['tier'] as num?)?.toInt(),

      bond: (j['bond'] as String?) ?? 'unknown',
      bondNote: j['bond_note'] as String?,
      // Defaults to FALSE. An unknown bond is not an open one, and a society the
      // user cannot join must never be presented as joinable on a parse default.
      joinable: (j['joinable'] as bool?) ?? false,

      county: j['county'] as String?,
      physicalLocation: j['physical_location'] as String?,
      branches: (j['branches'] as num?)?.toInt(),
      website: j['website'] as String?,
      phone: j['phone'] as String?,
      email: j['email'] as String?,

      logoUrl: j['logo_url'] as String?,
      brandColor: parseHexColor(j['brand_color'] as String?),
      about: j['about'] as String?,

      interestOnDeposits: (j['interest_on_deposits'] as num?)?.toDouble(),
      dividendOnShareCapital: (j['dividend_on_share_capital'] as num?)
          ?.toDouble(),
      rateYear: (j['rate_year'] as num?)?.toInt(),
      rateDeclaredOn: j['rate_declared_on'] as String?,
      rateSourceUrl: j['rate_source_url'] as String?,
      rateSourceDoc: j['rate_source_doc'] as String?,
      rateHistory: ((j['rate_history'] as List?) ?? const [])
          .map((r) => SaccoRate.fromJson((r as Map).cast<String, dynamic>()))
          .toList(),

      registrationFeeKes: (j['registration_fee_kes'] as num?)?.toDouble(),
      minShareCapitalKes: (j['min_share_capital_kes'] as num?)?.toDouble(),
      minMonthlyDepositKes: (j['min_monthly_deposit_kes'] as num?)?.toDouble(),
      loanMultiple: (j['loan_multiple'] as num?)?.toDouble(),
      depositNoticeDays: (j['deposit_notice_days'] as num?)?.toInt(),
      hasFosa: j['has_fosa'] as bool?,

      totalAssetsKes: (j['total_assets_kes'] as num?)?.toDouble(),
      depositsKes: (j['deposits_kes'] as num?)?.toDouble(),
      members: (j['members'] as num?)?.toInt(),
      registeredYear: (j['registered_year'] as num?)?.toInt(),
      financialsAsOf: j['financials_as_of'] as String?,
    );
  }

  /// Always true. See invariant 2 in the class doc: this is not read from JSON,
  /// because there is no SACCO whose member deposits are withdrawable on demand,
  /// and a parsed default is a thing a future edit can quietly flip.
  ///
  /// It is a getter and not a bare constant so that every widget that ranks a
  /// SACCO against a money market fund has to reach for it by name and is
  /// reminded, at the call site, that these two numbers are the same shape and
  /// not the same promise.
  bool get locked => true;

  /// A deposit rate exists, so this society can be ranked. The ONLY gate on
  /// entering a sorted list.
  ///
  /// A society with no declared rate is still shown in the directory: it is a
  /// real, licensed institution and that is worth knowing. It is simply not
  /// ranked, rather than ranked at zero, which would be a claim we cannot make.
  bool get hasDepositRate => interestOnDeposits != null;

  bool get hasDividend => dividendOnShareCapital != null;

  /// Both numbers are present, which is what the two-pot explainer needs.
  bool get hasBothRates => hasDepositRate && hasDividend;

  /// Confirmed open bond AND a rate to rank on. This is the only combination
  /// that is actually useful to a user, and it is what the SACCO tab leads with.
  bool get isActionable => joinable && hasDepositRate;

  /// The bond has not been confirmed either way. Rendered as such, never as
  /// closed and never as open: SASRA does not publish it, so most societies sit
  /// here until someone checks.
  bool get bondUnknown => bond == 'unknown';

  /// The worked example that kills the headline-dividend illusion, computed for
  /// a given pair of balances rather than hard-coded, so the detail page can let
  /// the user move the numbers.
  ///
  /// Returns null unless both rates are present, because the comparison is
  /// meaningless with one of them missing and a half-drawn version of this
  /// argument is worse than none.
  ({double fromDeposits, double fromShares})? earningsOn({
    required double deposits,
    required double shares,
  }) {
    final d = interestOnDeposits;
    final s = dividendOnShareCapital;
    if (d == null || s == null) return null;
    return (
      fromDeposits: deposits * d / 100,
      fromShares: shares * s / 100,
    );
  }
}

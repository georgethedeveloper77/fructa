import '../data/models/period_return.dart';

/// Kenyan withholding tax on investment interest.
///
/// Two things were wrong with the four-line version of this file, and both were
/// invisible because the output looked plausible.
///
/// ONE, THE RATE WAS HARDCODED. `Tax.wht` was a `const 0.15`, while the LABEL
/// beside every figure it produced came from `benchmark.wht_pct` in remote
/// config. Set that key to anything but 15 and the label and the number disagree
/// with each other on the same line, with no error anywhere.
///
/// TWO, IT ASKED THE WRONG QUESTION. `Tax.net(gross)` takes a number and assumes
/// tax is owed on it. That assumption holds for a money market yield and fails
/// for a fund that publishes net of tax already, and the app had no way to tell
/// the two apart, so it deducted 15% from both. On the Etica Special Multi Asset
/// page that turned a figure the manager published as final into one nobody had
/// ever quoted.
///
/// The replacement asks whether tax is due before deducting any, and takes the
/// rate from the caller, who has the config.
class Tax {
  const Tax._();

  /// Fallback withholding rate, %, used only when remote config carries none.
  ///
  /// A default rather than a constant. The live figure is `benchmark.wht_pct`,
  /// edited in admin, and it exists so a rate change is a config edit rather
  /// than a release. This value is what the app falls back to before the first
  /// snapshot lands, and it should never be read in preference to config.
  static const double defaultWhtPct = 15;

  /// Whether withholding tax is still owed on a figure.
  ///
  /// [taxFree] wins over everything: an infrastructure bond pays no withholding
  /// however its return is quoted. Otherwise the answer comes from [netOf], and
  /// a null [netOf] is read as [NetOf.fees], which is the Kenyan unit trust
  /// convention and the assumption the app has always made. Reading null as
  /// "already taxed" would suppress a deduction that is genuinely due, which is
  /// the more damaging of the two possible mistakes: it overstates what a holder
  /// keeps.
  static bool isDue({required NetOf? netOf, bool taxFree = false}) {
    if (taxFree) return false;
    return (netOf ?? NetOf.fees).whtStillDue;
  }

  /// [value] after withholding tax, when any is owed, and unchanged when none
  /// is. Percentages and amounts both work: the operation is proportional.
  ///
  /// This is the only function in the app that may reduce a number for tax.
  static double apply(
    double value, {
    required NetOf? netOf,
    bool taxFree = false,
    double whtPct = defaultWhtPct,
  }) {
    if (!isDue(netOf: netOf, taxFree: taxFree)) return value;
    if (whtPct <= 0 || whtPct >= 100) return value;
    return value * (1 - whtPct / 100);
  }

  /// The fraction of a return that survives tax, for compounding engines that
  /// need a multiplier rather than a figure.
  static double surviving({
    required NetOf? netOf,
    bool taxFree = false,
    double whtPct = defaultWhtPct,
  }) {
    if (!isDue(netOf: netOf, taxFree: taxFree)) return 1;
    if (whtPct <= 0 || whtPct >= 100) return 1;
    return 1 - whtPct / 100;
  }

  // ── Legacy call sites ──────────────────────────────────────────────────────
  //
  // RESTORED AFTER BEING DELETED IN ERROR. The deletion was justified by an
  // analyze run showing no deprecation warnings, but the annotations below and
  // the deletion shipped together, so no build ever existed in which these were
  // annotated AND present. Absence of warnings meant the audit had not run, not
  // that it had passed. It has now run, against the compiler, and found six
  // uses in four files:
  //
  //   core/insights/signal_engine.dart:139   Tax.net
  //   engine/accrual_engine.dart:22          Tax.net
  //   engine/accrual_engine.dart:33          Tax.wht
  //   engine/bond_engine.dart:41, 54, 80     Tax.net
  //   features/compare/compare_overlay.dart:17  Tax.net
  //
  // Every one of them is wrong in the way described at the top of this file:
  // it assumes tax is owed and it assumes the rate is 15. Two of them matter
  // more than the rest. accrual_engine values what a holding has actually
  // earned, and bond_engine prices a bond fund, so a fund quoting net of tax
  // has 15% taken off its accrual and off its yield to maturity.
  //
  // THE DELETION CRITERION, this time stated so it can be checked: these go
  // when `flutter analyze` reports zero `deprecated_member_use` hits on Tax,
  // in a build where the annotations are present and the members still are.

  /// Legacy. Assumes tax is due and that the rate is 15%.
  ///
  /// Deprecated rather than deleted so `flutter analyze` LISTS every remaining
  /// call site instead of the build simply failing at the first one. Work the
  /// list, then delete both of these.
  @Deprecated('Use Tax.surviving(netOf:, taxFree:, whtPct:) with the config rate')
  static const double wht = defaultWhtPct / 100;

  /// Legacy. Prefer [apply], which asks whether tax is owed at all.
  @Deprecated('Use Tax.apply(value, netOf:, taxFree:, whtPct:)')
  static double net(double gross) => gross * (1 - defaultWhtPct / 100);
}

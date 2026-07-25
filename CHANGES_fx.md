# FX: comparison page, card onTap, real-return bar, dollar view

Three new files, two edits, one i18n fragment of 51 keys. Paste the keys BEFORE
extracting, or `t()` renders raw key names on the new surfaces.

```
NEW  lib/features/markets/currency_compare_page.dart
NEW  lib/features/company/widgets/real_return_bar.dart
NEW  lib/features/company/widgets/usd_view_card.dart
EDIT lib/features/markets/widgets/fx_context_card.dart   (onTap)
EDIT lib/data/snapshot_providers.dart                    (fxFundPairProvider)
     assets/lang/en.fx_compare.json                      (merge into en.json)
```

## fx.spread_pct: 1.5, unchanged

Restating my call in the engine's own units, because I gave it in round-trip
terms last time and `FxQuote.spread` is a ONE WAY fraction. 1.5 one way is the
3 percent round trip I was arguing for, so the existing default is already the
answer and nothing needs to change.

Why 1.5 and not something else:

- It has to exist. OXR is mid-market, a price nobody in Nairobi transacts at.
  With no spread the buy-USD hurdle is understated and the card tells a retail
  Kenyan that dollar funds win in cases where they do not.
- One number, not a measured bid and ask. We have no per-bank data, so a split
  would imply precision we do not hold. The engine already derives both legs
  from it, and `roundTrip` comes out near 3 percent, which is most of a year of
  USD money market yield.
- Kenyan bank boards commonly run 2 to 4 shillings on a ~129 mean, and retail
  gets worse than the posted rate. Round trip at a counter is realistically 3 to
  5 percent. 1.5 each way is conservative without being alarmist.
- It must NOT be derived. There is no free feed of Kenyan retail buy/sell, and a
  derived number that looks live but is not is exactly the mistake the old CBK
  page parse was. `fxQuoteProvider` already refuses CBK's legs for this reason.

The new page labels it as an assumption in the "What this ran on" list and says
the reader's own bank is the number that decides it. That is the honest version
of a figure arrived at by judgement.

Change it when you have a real quote from a real counter, not before.

## currency_compare_page.dart

The page behind "RUN YOUR OWN NUMBERS". Reads only providers that already
existed. Sections:

- **The quote.** Buy leg, mean, sell leg, and what a round trip costs.
- **Where you are.** All three stances. Hedged gets no hurdle, no race and no
  record, and says why: there is no currency position to price. It does not get
  a comparison invented for it.
- **How long.** 1, 3, 5 years, feeding `FxCase.years`.
- **What the shilling has to do.** The breakeven per dollar, the implied fall,
  the annualised hurdle, and the band chip off `FxCase.hurdleBand`.
- **If you had started then.** `FxEngine.race` over the horizon that has just
  ended, both paths in shillings on one axis, with amount chips (KES for a
  buyer, USD for a holder). Not a projection: it is what the two choices did.
- **Every time this bet could have been placed.** `FxEngine.rollingRecord`, one
  tick per window, and the count. This is the counterweight to the hurdle: a
  hurdle alone reads as impossible or trivial depending on the reader's priors.
- **What this ran on.** Mean, assumed spread, both fund NAMES and both net
  yields, then the note about the spread being an assumption.

The race and the record each hide themselves when the history is too short for a
complete window, rather than running on a truncated one and presenting it whole.

## fxFundPairProvider

`fxFundRatesProvider` picked the two best MMFs and returned only their rates, so
the page had no way to name them without re-running the same selection. Two
copies of a selection rule drift; that is the bug I just took out of the insurer
page. Now `fxFundPairProvider` picks the funds and `fxFundRatesProvider` derives
its record from it. Same rule, one place. No call site changes: the rates
provider keeps its exact signature.

## real_return_bar.dart

The fund page already prints gross, net and real in a row and never shows the
sizes. 13.74 gross against 4.67 real is a two thirds haircut and nothing says so.

The bar is the gross yield with three segments that sum to it exactly, because
they are differences of figures the page already displays: `tax = gross - net`,
`inflation = net - real`, `kept = real`.

When the real return is negative the segments cannot fit inside the gross, which
is the finding. The bar then runs the full width with a marker where the gross
ran out, inflation is drawn last so the overshoot is painted in its colour, and
the legend says "Short by" instead of "Kept".

Presentational, no provider, no config read. The caller passes inflation for the
fund's OWN currency, which is why `Fund.realRate` takes it as an argument. Pass
nothing for a USD fund and the bar never renders: Kenyan CPI does not deflate a
dollar.

Drop it into `company_page.dart` beside the gross/net/real row:

```dart
if (fund.currency == 'KES')
  Builder(builder: (_) {
    final wht = cfg.whtPct;                  // whatever you already call it here
    final infl = /* your Kenyan CPI figure, as a percentage */;
    final gross = fund.currentRate;
    final net = fund.netRate(wht);
    final real = fund.realRate(infl, whtPct: wht);
    if (gross == null || net == null || real == null) return const SizedBox.shrink();
    return RealReturnBar(gross: gross, net: net, real: real, inflation: infl);
  }),
```

I have not seen `company_page.dart` or `remote_config.dart`, so the inflation
accessor above is the one thing you fill in. Everything else is checked against
the real `Fund` API.

## usd_view_card.dart

`FxEngine.inUsd`, as one card for the foot of the fund page, where you asked for
it. It takes the fund and reads `fxSeriesProvider` itself, so the call site is
one line:

```dart
UsdViewCard(fund),
```

Put it at the bottom, after peer compare. It is context on a figure the page has
already argued for, not a competing headline.

Uses `return1y` where the fund publishes one and says the fund RETURNED that.
Falls back to the current yield for a yield-basis fund and says a year at
today's yield WOULD return it. Two different claims, two different sentences.
Restates the gross figure, deliberately: mixing withholding in muddies the one
thing the card is for, and the FX delta is the finding.

Hides for a non-KES fund, a fund with neither a return nor a yield, and a
snapshot with fewer than 13 monthly FX points.

## fx_context_card.dart

`onTap: null` replaced with a push to the comparison page. The `_cta` block was
already gated on `onTap != null`, so "RUN YOUR OWN NUMBERS" appears now with no
other change.

## Versioning

`snapshot_providers.dart` is edited from the copy you uploaded this session. If
you have touched it since that upload, take the `fxFundPairProvider` block out of
the zip by hand rather than overwriting.

## Verified

No em dash. No emoji or glyph icons. Brackets balanced across all five files.
Every `t()` key resolves against the fragment or against a key already shipped,
and every key in the fragment is referenced. No `Colors.*` and no colour literal
in anything new (`Colors.transparent` in fx_context_card is pre-existing and is
the standard InkWell idiom). No Dart SDK in this container, so this is not an
`analyze` pass: paste the output if anything trips.

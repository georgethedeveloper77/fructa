# Insurer detail + reviews, built

```
EDIT lib/features/insure/insurer_detail_page.dart
EDIT lib/features/insure/insurer_reviews.dart
     assets/lang/en.insure_v2.json   (33 keys, paste before extracting)
```

Includes the contact-grid gap fix from the previous drop, so this file
supersedes it.

## Detail page

**Where this sits.** The rail, built from `_peerPrices`, which re-prices every
insurer at exactly this page's inputs. Nothing is fetched: the list screen
already priced the whole book to build itself. Recomputed rather than passed in,
so the directory (which opens on a default 3.45m private comprehensive) gets a
rail measured against that same default instead of whatever the motor screen
last had. Rank counts strictly-cheaper quotes, so identical premiums share a
place. Hides below three quotes, because a rail with two pips is a pair, not a
market, and "2nd of 2" flatters the dearer one.

**What you get, without a benefit list.** `_Terms` prints the cover, the excess
and the floor off the tariff the premium was computed from, then says plainly
that this insurer publishes no list. Every figure was already used above it, so
it invents nothing.

**Will they pay, with nothing to show.** `InsurerTrustPanel` returns
`SizedBox.shrink()` whenever `hasTrustData` is false, which is how a page became
a premium and half a screen of black. `_Standing` renders in exactly that case:
licence, rating, settlement time, complaints, each answered or explicitly "not
published". Absence is the finding. An insurer that publishes none of it has
told the reader how much it is willing to be measured by.

**The CTA says what it does.** "Get this quote" implied fructa sells the cover,
which is the one thing the disclaimer at the foot of the page exists to deny.
It dials a phone, so it says "Call CIC".

## Reviews

**The claims split is the headline, not the average.** `claims_holder` is
already on every row. Splitting on it gives "had a claim 2.2 / never claimed
4.1" and a sentence naming the gap, which is the only comparison that matters in
insurance and which nothing else in Kenya prints.

Two guards, both deliberate:

- It renders only when the loaded page IS the whole set (`reviews.length ==
  stats.count`). `list()` is capped at twenty, so past that this would be the
  split of a sample presented as the split of the market.
- The sentence appears only at a gap of half a star or more. Below that the two
  groups agree and announcing a 0.2 difference is reading noise as signal.

If you want it for insurers with more than twenty reviews, extend
`insurer_review_stats` with claims-holder counts and averages; the widget can
then read them instead of counting the page. Not needed yet.

**Order: claim, then words, then newest.** The API already floated reviews
carrying words, which was right as far as it went. The sharper cut is whether
the writer ever tested the cover: five stars from a policy nobody has claimed on
is the least informative thing on the page, however recent.

**The empty state teaches.** "No reviews yet" leaves a reader with no idea why
they would write one. It now names what helps a stranger most: whether you
claimed, how long it took, what they argued about.

## Not built

The Helpful count from the mockup. It needs a `review_votes` table and a unique
constraint on (review, device), which is a schema change rather than a widget.
Say if you want it and I will write the migration.

## Verified

No em dash, no emoji, no `Colors.*`, no truncation. Brackets balanced on both
files. All 33 new keys used, none unused. No Dart SDK here, so still not an
`analyze` pass.

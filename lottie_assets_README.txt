PHASE 2 - Lottie dual-source (admin URL first, then bundled asset, then icon)
=============================================================================

The app now tries, in order:
  1. the admin lottie_url (network)          <- wins when set and valid
  2. assets/lottie/<key>.json                <- bundled fallback
  3. the Material icon                        <- always-safe last resort

To use the bundled fallback, drop the animation files in assets/lottie/ named by
the insurance type KEY (the same key the admin type uses), e.g.:

  assets/lottie/motor.json
  assets/lottie/travel.json
  assets/lottie/health.json
  assets/lottie/home.json
  assets/lottie/business.json
  assets/lottie/marine.json
  assets/lottie/life.json
  assets/lottie/pet.json
  assets/lottie/education.json
  assets/lottie/last_expense.json

Then register the folder in pubspec.yaml (under flutter: -> assets:):

  flutter:
    assets:
      - assets/lottie/

Plain .json Lottie works out of the box. A .lottie (dotLottie) file needs a
decoder and will NOT parse via the default loader - export/download the JSON.

WHY THE ADMIN URL MAY NOT SHOW (check these):
  - lottie_url must be a DIRECT json url (e.g. https://lottie.host/xxxx/xxxx.json),
    not a lottiefiles.com share/page link. A page URL never parses.
  - The snapshot must carry lottie_url on insurance_types AND be rebuilt after
    you save it in admin. If the app is falling back to the baked motor/travel
    types, no URL reaches it - rebuild the snapshot and confirm snapshot.ts
    publishes lottie_url for each type.
  - With the change above, a bad/missing URL now shows the bundled asset (or the
    icon) instead of nothing, so the row is never blank while you sort the URL.

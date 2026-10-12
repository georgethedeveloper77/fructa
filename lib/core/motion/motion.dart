/// Fructa motion language.
///
/// Three effects, each tied to a moment that means something:
///
/// * [StretchSwap]: a value replaced by the user's own action (category,
///   net/gross, range) squashes and springs into place.
/// * [Glitch]: a value replaced by the market (a new rate print) splits into
///   accent and down channels for half a second, then settles.
/// * [ThanosDismiss]: a card the user dismisses turns to dust left to right,
///   then the space it held closes.
///
/// Every effect is skipped when the platform asks for reduced motion.
library;

import 'package:flutter/widgets.dart';

export 'glitch.dart';
export 'stretch_swap.dart';
export 'thanos_dismiss.dart';

/// True when the user has asked the OS to reduce or disable animation.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

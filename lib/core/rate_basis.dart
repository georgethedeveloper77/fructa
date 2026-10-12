import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// Which figure the app leads with: gross (the rate managers advertise and
/// CMA publishes) or net of withholding tax.
///
/// One setting for the whole app, remembered between launches, so Today,
/// Markets and the fund rows never disagree about what the big number means.
/// Gross by default: it is the figure a reader can check against any fact
/// sheet or advert.
class RateBasisNotifier extends Notifier<bool> {
  static const _key = 'rate_basis_net';

  Box get _box => Hive.box('settings');

  /// True when net is shown, false for gross.
  @override
  bool build() => _box.get(_key, defaultValue: false) as bool;

  Future<void> setNet(bool net) async {
    if (net == state) return;
    state = net;
    await _box.put(_key, net);
  }
}

/// True when the app shows NET figures; false (default) for GROSS.
final showNetProvider = NotifierProvider<RateBasisNotifier, bool>(
  RateBasisNotifier.new,
);

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_loader.dart';

/// Settings footer: the wordmark and the running version, read from the build
/// via package_info, never hardcoded. Tapping it checks the store for a newer
/// build and says what it found.
///   - Android: Play in-app-update availability.
///   - iOS: the iTunes lookup for the current App Store version.
///
/// It only reports; it does not force an update. Both platforms surface the
/// result in a snackbar so the user decides.
class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({super.key});

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {
      // Leave the version blank rather than show a fabricated one.
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);

    String msg;
    try {
      if (Platform.isAndroid) {
        final info = await InAppUpdate.checkForUpdate();
        msg = info.updateAvailability == UpdateAvailability.updateAvailable
            ? 'An update is available on Google Play.'
            : 'You are on the latest version.';
      } else if (Platform.isIOS) {
        msg = await _checkAppStore();
      } else {
        msg = 'You are on the latest version.';
      }
    } catch (_) {
      msg = 'Could not check for updates right now.';
    }

    if (!mounted) return;
    setState(() => _checking = false);

    final c = context.c;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: c.s3,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            msg,
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
  }

  /// iTunes lookup by bundle id returns the live App Store version.
  Future<String> _checkAppStore() async {
    final info = await PackageInfo.fromPlatform();
    final res = await http.get(
      Uri.parse('https://itunes.apple.com/lookup?bundleId=${info.packageName}'),
    );
    if (res.statusCode != 200) {
      return 'Could not reach the App Store right now.';
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    if (results.isEmpty) return 'You are on the latest version.';
    final storeVersion =
        (results.first as Map)['version']?.toString() ?? info.version;
    return _isNewer(storeVersion, info.version)
        ? 'An update is available on the App Store.'
        : 'You are on the latest version.';
  }

  /// True when [store] is a higher dotted version than [current].
  bool _isNewer(String store, String current) {
    List<int> parts(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(store), b = parts(current);
    for (var i = 0; i < a.length; i++) {
      final bi = i < b.length ? b[i] : 0;
      if (a[i] != bi) return a[i] > bi;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: InkWell(
        onTap: _check,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Fructa',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 20,
                child: _checking
                    ? const AppLoader(size: 18)
                    : Text(
                        _version,
                        style: TextStyle(
                          color: c.faint,
                          fontFamily: fructaFonts.mono,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

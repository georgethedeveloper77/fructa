import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/local_notify.dart';
import '../../../core/push.dart';
import '../../../core/settings_prefs.dart';
import '../../../core/theme.dart';
import '../../../data/providers.dart';

/// Notification delivery state, in plain language.
///
/// A push has to clear four independent gates to reach the drawer, and when any
/// one of them fails it fails SILENTLY: no exception, no log, no error anywhere
/// in the app or on the server. That is the whole reason notifications felt
/// random rather than broken. This panel reads all four and shows them.
///
/// Insert into settings_page.dart wherever the notifications section lives:
///
///     const NotificationDiagnostics(),
///
class NotificationDiagnostics extends ConsumerWidget {
  const NotificationDiagnostics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final async = ref.watch(pushDiagnosticsProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Delivery status',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Re-check',
                visualDensity: VisualDensity.compact,
                onPressed: () => ref.invalidate(pushDiagnosticsProvider),
                icon: Icon(Icons.refresh_rounded, size: 20, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'All four have to be true for an alert to reach this phone.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.faint),
          ),
          const SizedBox(height: 14),
          async.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.muted,
                  ),
                ),
              ),
            ),
            error: (e, _) => Text(
              'Could not read the notification state on this device: $e',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.down),
            ),
            data: (d) => _Body(d: d, ref: ref),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.d, required this.ref});

  final PushDiagnostics d;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final localFunds =
        ((Hive.box('settings').get('subs', defaultValue: <String>[]) as List)
                .cast<String>())
            .length;
    final localStocks =
        ((Hive.box('settings').get('stockSubs', defaultValue: <String>[])
                    as List)
                .cast<String>())
            .length;
    final wanted = localFunds + localStocks;
    final held = d.followTagCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Check(
          ok: d.permitted,
          label: 'Notifications allowed',
          bad: 'Android and iOS drop every alert silently until this is on.',
        ),
        _Check(
          ok: d.optedIn,
          label: 'Subscribed to alerts',
          bad:
              'Turned off by "All alerts off". Following a fund does nothing '
              'while this is false.',
        ),
        _Check(
          ok: (d.subscriptionId ?? '').isNotEmpty,
          label: 'Registered with the alert service',
          bad:
              'This phone has no push token yet. Usually a network problem on '
              'first launch. Reopening the app fixes it.',
        ),
        _Check(
          ok: wanted == 0 || held >= wanted,
          label: 'Follows synced ($held of $wanted)',
          bad:
              'Some of the funds you follow never reached the alert service. '
              'Tap Re-sync to fix.',
        ),

        if (d.error != null) ...[
          const SizedBox(height: 10),
          Text(
            d.error!,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: c.faint),
          ),
        ],

        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  await Push.ensureDeliverable();
                  final s = Hive.box('settings');
                  await Push.reconcile(
                    funds:
                        ((s.get('subs', defaultValue: <String>[]) as List)
                                .cast<String>())
                            .toSet(),
                    stocks:
                        ((s.get('stockSubs', defaultValue: <String>[]) as List)
                                .cast<String>())
                            .toSet(),
                    digest:
                        s.get('pref_weeklyDigest', defaultValue: true) as bool,
                    // Same derivation main() uses. Never hand-roll the mute key
                    // names here: a third copy is a third thing to drift.
                    mutes: SettingsPrefs.muteTagsFrom(s),
                  );
                  ref.invalidate(pushDiagnosticsProvider);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.line2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Re-sync'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                // Cuts the server, the tags and FCM entirely out of the picture
                // and exercises only permission, channel and icon. If this one
                // does not appear, the problem is on the handset, not the
                // pipeline, and that is worth knowing in one tap.
                onPressed: LocalNotify.test,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.line2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Send a test'),
              ),
            ),
          ],
        ),

        if (d.subscriptionId != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            'Device ${d.subscriptionId}',
            style: TextStyle(
              fontSize: 10.5,
              color: c.faint,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
        ],
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label, required this.bad});

  final bool ok;
  final String label;

  /// What it means when this one is false, said in a way that tells the user
  /// what to do about it rather than which subsystem let them down.
  final String bad;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 17,
              color: ok ? c.up : c.down,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: ok ? c.text : c.muted,
                  ),
                ),
                if (!ok) ...[
                  const SizedBox(height: 3),
                  Text(
                    bad,
                    style: TextStyle(fontSize: 12, height: 1.4, color: c.faint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

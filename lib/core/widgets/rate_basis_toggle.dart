import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n.dart';
import '../rate_basis.dart';
import '../theme.dart';

/// Gross | Net segmented switch bound to the app-wide [showNetProvider].
/// Gross sits first because it is the default.
class RateBasisToggle extends ConsumerWidget {
  const RateBasisToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final net = ref.watch(showNetProvider);

    Widget pill(String label, bool on, bool value) => Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => ref.read(showNetProvider.notifier).setNet(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.text : c.s2.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? c.bg : c.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(t('basis.gross'), !net, false),
          pill(t('basis.net'), net, true),
        ],
      ),
    );
  }
}

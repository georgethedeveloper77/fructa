import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import 'compare_controller.dart';
import 'compare_overlay.dart';

/// Saved comparisons row. Hidden when there are none.
class SavedComparisonsSection extends ConsumerWidget {
  const SavedComparisonsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final saved = ref.watch(savedComparisonsProvider);
    if (saved.isEmpty) return const SizedBox.shrink();
    final byId = ref.watch(fundsByIdProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('compare.savedTitle').toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final s in saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CompareOverlay(s.fundIds),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            s.fundIds
                                .map((id) => byId[id])
                                .whereType<Fund>()
                                .map((f) => f.name.split(' ').first)
                                .join(' · '),
                            style: TextStyle(color: c.text, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(savedComparisonsProvider.notifier)
                          .toggleNotify(s.id),
                      icon: Icon(
                        s.notify
                            ? Icons.notifications_active
                            : Icons.notifications_off_outlined,
                        color: s.notify ? c.accent : c.faint,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(savedComparisonsProvider.notifier)
                          .remove(s.id),
                      icon: Icon(Icons.close, color: c.faint, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/categories.dart';
import '../../../core/theme.dart';
import '../../../data/providers.dart';
import '../market_filters.dart';

class CategoryCards extends ConsumerWidget {
  const CategoryCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(ratesProvider).valueOrNull ?? const [];
    final selected = ref.watch(marketFiltersProvider).category;

    // categories present, in canonical order, with count + top rate
    final present = categoryOrder
        .where((c) => all.any((f) => f.category == c))
        .toList();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: present.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final key = present[i];
          final rows = all.where((f) => f.category == key).toList();
          final top = rows
              .map((f) => f.currentRate)
              .whereType<double>()
              .fold<double?>(null, (m, r) => m == null || r > m ? r : m);
          final active = selected == key;
          return GestureDetector(
            onTap: () =>
                ref.read(marketFiltersProvider.notifier).toggleCategory(key),
            child: Container(
              width: 132,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: active ? const Color(0x1AE0B34C) : AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active ? AppColors.gold : AppColors.line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    categoryLabel(key),
                    style: TextStyle(
                      color: active ? AppColors.gold : AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        top != null ? '${top.toStringAsFixed(2)}%' : '',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '${rows.length} ${rows.length == 1 ? "fund" : "funds"}',
                        style: const TextStyle(
                          color: AppColors.faint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

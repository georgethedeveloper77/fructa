import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/insurer.dart';
import 'insure_motion.dart';

/// Vehicle class and cover type. Two decisions that change the price more than
/// anything else, so they sit above the value input, not buried in a filter.
///
/// [availableClasses] is computed from what insurers actually write. A class
/// nobody in the book covers is not offered as a choice, so the user can never
/// land on an empty comparison and conclude the app is broken.
class MotorCoverSelector extends StatelessWidget {
  const MotorCoverSelector({
    super.key,
    required this.cls,
    required this.cover,
    required this.availableClasses,
    required this.tpoAvailable,
    required this.onClass,
    required this.onCover,
  });

  final MotorClass cls;
  final CoverType cover;
  final Set<MotorClass> availableClasses;
  final bool tpoAvailable;
  final ValueChanged<MotorClass> onClass;
  final ValueChanged<CoverType> onCover;

  @override
  Widget build(BuildContext context) {
    final classes = MotorClass.values.where(availableClasses.contains).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (classes.length > 1) ...[
            _Label(t('insure.vehicleClass')),
            const SizedBox(height: 7),
            SlidingSegments<MotorClass>(
              values: classes,
              selected: cls,
              labelOf: (c) => t('insure.class.${c.key}'),
              onTap: onClass,
            ),
            const SizedBox(height: 14),
          ],
          _Label(t('insure.coverType')),
          const SizedBox(height: 7),
          SlidingSegments<CoverType>(
            values: CoverType.values,
            selected: cover,
            labelOf: (c) => t('insure.cover.${c.key}'),
            // TPO is disabled, not hidden, when nobody publishes it for this
            // class. Hiding it would imply the cover does not exist; disabling
            // says the truth, which is that we have no published prices for it.
            enabledOf: (c) => c == CoverType.comprehensive || tpoAvailable,
            onTap: onCover,
          ),
          if (!tpoAvailable) ...[
            const SizedBox(height: 7),
            Text(
              t('insure.tpoUnpublished'),
              style: TextStyle(
                color: context.c.faint,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: context.c.faint,
      fontSize: 9.5,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w700,
    ),
  );
}

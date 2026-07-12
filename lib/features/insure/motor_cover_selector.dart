import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/insurer.dart';

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
    final classes =
        MotorClass.values.where(availableClasses.contains).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (classes.length > 1) ...[
            _Label(t('insure.vehicleClass')),
            const SizedBox(height: 7),
            _Segments<MotorClass>(
              values: classes,
              selected: cls,
              labelOf: (c) => t('insure.class.${c.key}'),
              onTap: onClass,
            ),
            const SizedBox(height: 14),
          ],
          _Label(t('insure.coverType')),
          const SizedBox(height: 7),
          _Segments<CoverType>(
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
                  color: context.c.faint, fontSize: 11, height: 1.4),
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

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onTap,
    this.enabledOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final bool Function(T)? enabledOf;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: _Segment(
                label: labelOf(v),
                active: v == selected,
                enabled: enabledOf?.call(v) ?? true,
                onTap: () => onTap(v),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = !enabled
        ? c.faint
        : active
            ? c.bg
            : c.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.text : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fg,
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

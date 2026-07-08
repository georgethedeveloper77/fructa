import 'package:flutter/material.dart';

import '../theme.dart';

class EarnCell {
  const EarnCell(this.label, this.value);
  final String label;
  final String value;
}

/// v5 `.earn3`  flat cells split by left hairlines; mono up-green values.
/// Typically three cells (day / month / year) but any count works.
class EarnStrip extends StatelessWidget {
  const EarnStrip(this.cells, {super.key});

  final List<EarnCell> cells;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 13),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(left: BorderSide(color: c.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cells[i].label.toUpperCase(),
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.85,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      cells[i].value,
                      style: TextStyle(
                        color: c.up,
                        fontFamily: fructaFonts.mono,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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

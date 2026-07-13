import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/sacco.dart';

/// Directory tile for a SACCO. A deliberate sibling of `FundTile` and
/// `StockTile`: same Material shell, hairline border, r16, 13/11 padding, same
/// fading rank badge, same mono tabular figures. A SACCO should read as the same
/// KIND of object as a fund, because to the user it is: a place to put money.
///
/// TWO THINGS MAKE IT DIFFERENT, and both are on the tile because leaving either
/// off would make the row a lie:
///
/// 1. THE HEADLINE IS THE DEPOSIT RATE, AND IT SAYS SO.
///    A SACCO has two rates. The dividend on share capital is nearly always the
///    bigger percentage (21% against 11.3% is a real, current pair) and nearly
///    always the smaller cheque, because shares are capped and savings are not.
///    A member with 500,000 saved and 50,000 in shares earns 65,000 from the
///    "small" number and 10,000 from the "big" one. Every SACCO advertisement in
///    Kenya leads with the big one.
///
///    So the large figure is ALWAYS interest on deposits, it always carries the
///    words ON DEPOSITS beneath it, and the dividend rides alongside as a
///    separate, explicitly labelled chip. There is no state of this widget in
///    which a bare percentage appears.
///
/// 2. THE MONEY IS LOCKED, AND IT SAYS SO.
///    The rate is the same shape as a money market yield. The promise is not.
///    The fund gives your money back in two working days; the SACCO gives it back
///    when you resign your membership. The lock chip is not decoration and it is
///    not conditional.
class SaccoTile extends ConsumerStatefulWidget {
  const SaccoTile(
    this.sacco, {
    super.key,
    required this.onTap,
    this.rank,
    this.netRate,
  });

  final Sacco sacco;
  final VoidCallback onTap;
  final int? rank;

  /// Net-of-tax deposit rate, supplied ONLY when this tile is sitting in the All
  /// league table next to funds, which show gross above net.
  ///
  /// Passed in rather than computed here, and passed in as the very number the
  /// list SORTED by, so the figure the user reads and the figure the ranking
  /// used cannot drift apart. Null everywhere else, including on the SACCO tab,
  /// where there is nothing to compare against and a net figure would just be
  /// noise. Null when the withholding rate has not been confirmed, which is the
  /// current state: see saccoNetPctProvider.
  final double? netRate;

  @override
  ConsumerState<SaccoTile> createState() => _SaccoTileState();
}

class _SaccoTileState extends ConsumerState<SaccoTile> {
  bool _showRank = true;

  String _members(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.sacco;

    final meta = [
      if (s.county != null && s.county!.isNotEmpty) s.county!,
      if (s.tier != null) 'Tier ${s.tier}',
      if (s.members != null) '${_members(s.members!)} members',
    ].join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          FundLogo(
                            domain: null,
                            logoUrl: s.logoUrl,
                            seed: s.name,
                            size: 34,
                            brandColor: s.brandColor,
                          ),
                          if (widget.rank != null)
                            Positioned(
                              left: -5,
                              top: -5,
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: _showRank ? 1 : 0,
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOut,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                    ),
                                    height: 18,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widget.rank! <= 3 ? c.accent : c.s2,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: c.s1, width: 1.5),
                                    ),
                                    child: Text(
                                      '${widget.rank}',
                                      style: TextStyle(
                                        color: widget.rank! <= 3
                                            ? c.onAccent
                                            : c.muted,
                                        fontFamily: fructaFonts.mono,
                                        fontSize: 10,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.displayName,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            style: TextStyle(
                              color: c.faint,
                              fontFamily: fructaFonts.mono,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _figure(context, s),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(height: 1, color: c.line),
                const SizedBox(height: 9),
                _chips(context, s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The headline. ALWAYS the deposit rate, and it always wears its label.
  ///
  /// A society with no declared rate shows a dash, never a zero and never the
  /// dividend standing in for it. It is in the directory because it is a real
  /// licensed institution; it is simply not ranked, and the tile says as much.
  Widget _figure(BuildContext context, Sacco s) {
    final c = context.c;

    if (!s.hasDepositRate) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\u2014',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'NOT DECLARED',
            style: TextStyle(
              color: c.faint,
              fontSize: 8.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${s.interestOnDeposits!.toStringAsFixed(2)}%',
          style: TextStyle(
            color: c.up,
            fontFamily: fructaFonts.mono,
            fontSize: 19,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        // The label is not optional. An unlabelled percentage on a SACCO tile
        // does not say which of the two pots it was paid on, and that is the
        // whole question.
        Text(
          'ON DEPOSITS',
          style: TextStyle(
            color: c.faint,
            fontSize: 8.5,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        // In the All table only. Funds print gross above net, so a SACCO sitting
        // beside them must do the same or it is being compared on a different
        // basis to the one the reader can see.
        if (widget.netRate != null) ...[
          const SizedBox(height: 3),
          Text(
            '${widget.netRate!.toStringAsFixed(2)}% net',
            style: TextStyle(
              color: c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  /// The lock, the dividend, the bond. In that order, because that is the order
  /// in which they change a decision.
  Widget _chips(BuildContext context, Sacco s) {
    final c = context.c;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        // Not conditional. There is no SACCO whose deposits are withdrawable on
        // demand, and Sacco.locked is a constant for that reason.
        _Chip(
          icon: Icons.lock_outline,
          label: 'Locked until you exit',
          fg: c.muted,
          bg: c.s2,
          border: c.line2,
        ),

        if (s.hasDividend)
          _Chip(
            label: 'Dividend',
            value: '${s.dividendOnShareCapital!.toStringAsFixed(2)}%',
            fg: c.accent,
            bg: c.accentSoft,
            border: c.accent.withValues(alpha: 0.3),
          ),

        // The bond is the gate before the rate. Unknown reads as unknown: SASRA
        // does not publish it, and presenting an unchecked society as joinable
        // would send someone to a membership that is shut to them.
        if (s.joinable)
          _Chip(
            icon: Icons.how_to_reg_outlined,
            label: 'Open to anyone',
            fg: c.up,
            bg: c.upSoft,
            border: c.up.withValues(alpha: 0.3),
          )
        else if (s.bondUnknown)
          _Chip(
            icon: Icons.help_outline,
            label: 'Membership not confirmed',
            fg: c.faint,
            bg: c.s2,
            border: c.line,
          )
        else
          _Chip(
            icon: Icons.block_outlined,
            label: s.bondNote == null
                ? 'Membership restricted'
                : 'Members: ${s.bondNote}',
            fg: c.faint,
            bg: c.s2,
            border: c.line,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    this.icon,
    this.value,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 4),
            Text(
              value!,
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

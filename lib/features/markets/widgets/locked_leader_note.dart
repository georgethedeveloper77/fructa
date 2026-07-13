import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../markets_controller.dart';

/// The one thing that must be said when a SACCO reaches the top of the All list.
///
/// It will reach the top. Kenyan SACCO deposit rates sit around 11% to 13% while
/// money market funds pay around 9% to 10%, so once the merge is on, the row
/// above every fund on the page is almost always a SACCO. That is not a bug and
/// the list is not wrong: the SACCO really does pay more.
///
/// It is also, on that same page, the only row whose money you cannot have back
/// next week. A money market fund returns your money in two working days. A
/// SACCO returns your deposits when you resign your membership, after a notice
/// period, and only once you are not guaranteeing anyone else's loan.
///
/// Those two facts are both true and a ranked list can only express the first
/// one. The lock chip on the tile carries some of the second. This note carries
/// the rest, and it appears exactly when it is needed: when the ranking is about
/// to tell someone that the least accessible option on the page is the best one.
///
/// It hides itself the moment that stops being true.
class LockedLeaderNote extends ConsumerWidget {
  const LockedLeaderNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(saccoLeadsAllProvider)) return const SizedBox.shrink();

    final c = context.c;

    // Baked in, not read from remote config, even though the admin Config page
    // carries a `saccos.access_disclaimer` key for it.
    //
    // I could not confirm a string accessor on RemoteConfig (it exposes flag()
    // and number(); the copy accessor was not in the files I had), and I will not
    // guess at one HERE of all places. If the getter name were wrong this
    // sentence would render as an empty box, and this sentence is the only thing
    // standing between a ranked list and a reader who thinks the top row is
    // money they can reach. Wire it to config once the accessor is confirmed;
    // until then the truth ships in the binary.
    const copy =
        'A SACCO pays more, but your money is locked until you leave the SACCO. '
        'A money market fund pays less and returns your money in two working days.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: c.accent, width: 2),
            top: BorderSide(color: c.line2),
            right: BorderSide(color: c.line2),
            bottom: BorderSide(color: c.line2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The top rate is not the most available money',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    copy,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

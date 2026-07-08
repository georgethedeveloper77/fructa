import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/push.dart';
import '../../data/models/alert.dart';
import '../../data/models/fund.dart';
import '../../data/models/saved_comparison.dart';
import '../../data/providers.dart';
import '../../data/repositories/comparisons_repository.dart';

const kMaxCompare = 4;

// ── Compare-as-mode state ──────────────────────────────────────────────────
final compareModeProvider = StateProvider<bool>((_) => false);

class CompareSelection extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void toggle(String id) {
    final s = [...state];
    if (s.contains(id)) {
      s.remove(id);
    } else if (s.length < kMaxCompare) {
      s.add(id);
    }
    state = s;
  }

  void clear() => state = const [];
}

final compareSelectionProvider =
    NotifierProvider<CompareSelection, List<String>>(CompareSelection.new);

// ── Saved comparisons ──────────────────────────────────────────────────────
final comparisonsRepositoryProvider = Provider(
  (ref) => ComparisonsRepository(Hive.box('settings')),
);

class SavedComparisonsNotifier extends Notifier<List<SavedComparison>> {
  ComparisonsRepository get _repo => ref.read(comparisonsRepositoryProvider);

  @override
  List<SavedComparison> build() => _repo.all();

  String? _leaderOf(List<String> ids) {
    final byId = ref.read(fundsByIdProvider);
    final members =
        ids
            .map((id) => byId[id])
            .whereType<Fund>()
            .where((f) => f.currentRate != null)
            .toList()
          ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
    return members.isEmpty ? null : members.first.id;
  }

  Future<void> save(List<String> fundIds) async {
    final item = SavedComparison(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fundIds: List.of(fundIds),
      leaderId: _leaderOf(fundIds),
      createdAt: DateTime.now(),
    );
    // Subscribe the device to each member's push tag so backend rate-changes
    // reach us; leader-flip is then recomputed on-device (see watcher).
    for (final id in fundIds) {
      Push.follow(id);
    }
    state = [item, ...state];
    await _repo.write(state);
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _repo.write(state);
  }

  Future<void> toggleNotify(String id) async {
    state = [
      for (final e in state) e.id == id ? e.copyWith(notify: !e.notify) : e,
    ];
    await _repo.write(state);
  }

  Future<void> _setLeader(String id, String leaderId) async {
    state = [
      for (final e in state) e.id == id ? e.copyWith(leaderId: leaderId) : e,
    ];
    await _repo.write(state);
  }
}

final savedComparisonsProvider =
    NotifierProvider<SavedComparisonsNotifier, List<SavedComparison>>(
      SavedComparisonsNotifier.new,
    );

/// On every fresh snapshot, recompute each saved set's leader. If it flipped
/// and the set has alerts on, raise a local alert. Kept alive by a `ref.watch`
/// in MarketsPage. Pure on-device  no server state.
final comparisonWatcherProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<List<Fund>>>(ratesProvider, (_, next) {
    final funds = next.valueOrNull;
    if (funds == null) return;
    final byId = {for (final f in funds) f.id: f};
    final sets = ref.read(savedComparisonsProvider);
    final notifier = ref.read(savedComparisonsProvider.notifier);
    final alerts = ref.read(alertsProvider.notifier);

    for (final s in sets) {
      final members =
          s.fundIds
              .map((id) => byId[id])
              .whereType<Fund>()
              .where((f) => f.currentRate != null)
              .toList()
            ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
      if (members.length < 2) continue;

      final leader = members.first;
      final flipped = s.leaderId != null && s.leaderId != leader.id;
      if (flipped && s.notify) {
        final old = byId[s.leaderId!];
        alerts.add(
          RateAlert(
            fundId: leader.id,
            oldRate: old?.currentRate ?? leader.currentRate!,
            newRate: leader.currentRate!,
            at: DateTime.now(),
          ),
        );
      }
      if (s.leaderId != leader.id) notifier._setLeader(s.id, leader.id);
    }
  });
});

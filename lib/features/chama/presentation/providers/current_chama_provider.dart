import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/chama.dart';
import 'chama_providers.dart';

/// Which chama the app is currently "in".
///
/// Home, Members and everything hanging off them show this one chama rather
/// than an aggregate, so the app reads as though you are inside a chama at
/// all times. Most people only ever have one; the switcher exists for the
/// minority who don't, and persists across launches so they aren't dropped
/// back into the wrong one every morning.
class CurrentChamaNotifier extends AsyncNotifier<String?> {
  static const _key = 'current_chama_id';

  @override
  Future<String?> build() async {
    final chamas = await ref.watch(myChamasProvider.future);
    if (chamas.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);

    // A saved id can outlive the membership it points at — removed from the
    // chama, or signed in as someone else on a shared handset. Falling back
    // to the first chama is what stops that showing an empty screen.
    if (saved != null && chamas.any((c) => c.id == saved)) return saved;

    final fallback = chamas.first.id;
    await prefs.setString(_key, fallback);
    return fallback;
  }

  Future<void> select(String chamaId) async {
    state = AsyncData(chamaId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, chamaId);
  }
}

final currentChamaIdProvider =
    AsyncNotifierProvider<CurrentChamaNotifier, String?>(CurrentChamaNotifier.new);

/// The current chama itself, resolved from the already-loaded list so
/// screens don't each fetch it again.
final currentChamaProvider = Provider<Chama?>((ref) {
  final id = ref.watch(currentChamaIdProvider).value;
  final chamas = ref.watch(myChamasProvider).value ?? const <Chama>[];
  if (chamas.isEmpty) return null;
  for (final c in chamas) {
    if (c.id == id) return c;
  }
  return chamas.first;
});

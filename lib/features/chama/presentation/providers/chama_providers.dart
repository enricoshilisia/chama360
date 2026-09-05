import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to a separate "legacy" import in Riverpod 3.x.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/services/connectivity_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/chama_repository.dart';
import '../../domain/models/chama.dart';
import '../../domain/models/chama_member.dart';
import '../../domain/models/chama_transaction.dart';

final chamaRepositoryProvider = Provider<ChamaRepository>((ref) {
  return ChamaRepository(ref.watch(supabaseClientProvider));
});

final myChamasProvider = FutureProvider.autoDispose<List<Chama>>((ref) async {
  final online = ref.watch(isOnlineProvider);
  return ref.watch(chamaRepositoryProvider).myChamas(online: online);
});

/// Selected chama id, driven by the router path (/chamas/:id).
final selectedChamaIdProvider = StateProvider<String?>((ref) => null);

final chamaTransactionsProvider = FutureProvider.autoDispose
    .family<List<ChamaTransaction>, String>((ref, chamaId) async {
  final online = ref.watch(isOnlineProvider);
  return ref.watch(chamaRepositoryProvider).transactionsFor(chamaId, online: online);
});

/// Looks up a single chama (with the viewer's own role/balance) from the
/// already-fetched myChamasProvider list, so screens don't need a second
/// network round trip just to know "am I an admin here".
final chamaByIdProvider = Provider.autoDispose.family<Chama?, String>((ref, chamaId) {
  final chamas = ref.watch(myChamasProvider).value ?? const [];
  for (final c in chamas) {
    if (c.id == chamaId) return c;
  }
  return null;
});

final chamaMembersProvider =
    FutureProvider.autoDispose.family<List<ChamaMember>, String>((ref, chamaId) async {
  return ref.watch(chamaRepositoryProvider).members(chamaId);
});

/// Feeds the home dashboard's activity list — recent transactions across
/// every chama the user belongs to.
final recentActivityProvider = FutureProvider.autoDispose<List<ChamaTransaction>>((ref) async {
  final chamas = await ref.watch(myChamasProvider.future);
  return ref.watch(chamaRepositoryProvider).recentActivity(chamas.map((c) => c.id).toList());
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../data/reports_repository.dart';
import '../../domain/models/chama_report.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

/// Pooled chama figures, computed in the database rather than from rows
/// the caller can read. A member's own report query only returns their own
/// contributions now, so summing it client-side would show them their
/// personal total labelled as the chama's.
final chamaTotalsProvider = FutureProvider.autoDispose
    .family<({double totalContributions, int memberCount, double totalOutstanding}), String>(
        (ref, chamaId) async {
  return ref.watch(chamaRepositoryProvider).chamaTotals(chamaId);
});

final chamaReportProvider =
    FutureProvider.autoDispose.family<ChamaReport, String>((ref, chamaId) async {
  return ref.watch(reportsRepositoryProvider).buildReport(chamaId);
});

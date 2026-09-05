import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/reports_repository.dart';
import '../../domain/models/chama_report.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

final chamaReportProvider =
    FutureProvider.autoDispose.family<ChamaReport, String>((ref, chamaId) async {
  return ref.watch(reportsRepositoryProvider).buildReport(chamaId);
});

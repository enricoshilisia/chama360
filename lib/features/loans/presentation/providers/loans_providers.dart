import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/loans_repository.dart';
import '../../domain/models/loan.dart';

final loansRepositoryProvider = Provider<LoansRepository>((ref) {
  return LoansRepository(ref.watch(supabaseClientProvider));
});

final chamaLoansProvider =
    FutureProvider.autoDispose.family<List<Loan>, String>((ref, chamaId) async {
  return ref.watch(loansRepositoryProvider).loansForChama(chamaId);
});

final loanRepaymentsProvider = FutureProvider.autoDispose
    .family<List<LoanRepayment>, String>((ref, loanId) async {
  return ref.watch(loansRepositoryProvider).repaymentsFor(loanId);
});

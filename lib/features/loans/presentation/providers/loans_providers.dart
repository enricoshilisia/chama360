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

/// What every loan in the chama would cost to clear today. Separate from
/// [chamaLoansProvider] because it is a moving figure: it depends on the
/// date, not just on the stored row.
final loanPayoffsProvider =
    FutureProvider.autoDispose.family<List<LoanPayoff>, String>((ref, chamaId) async {
  return ref.watch(loansRepositoryProvider).payoffsFor(chamaId);
});

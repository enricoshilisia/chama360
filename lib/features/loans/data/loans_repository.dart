import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/loan.dart';

/// Loan lifecycle: member requests (status=pending) -> admin either rejects
/// (status=rejected) or approves & disburses in one step (status=active,
/// which fires the handle_loan_activation DB trigger to compute total_due
/// and log the disbursement in the transactions ledger) -> repayments bring
/// it to status=repaid automatically once amount_repaid >= total_due (see
/// handle_loan_repayment trigger). All of this logic lives in
/// supabase/migrations/0001_init_schema.sql — this repository just calls it.
class LoansRepository {
  LoansRepository(this._client);

  final SupabaseClient _client;

  Future<List<Loan>> loansForChama(String chamaId) async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('loans')
        .select(
            '*, chama_members(user_id, managed_full_name:full_name, profiles(full_name, email))')
        .eq('chama_id', chamaId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => Loan.fromJson(r as Map<String, dynamic>, currentUserId: userId))
        .toList();
  }

  Future<void> requestLoan({
    required String chamaId,
    required String memberId,
    required double principal,
    String? purpose,
  }) async {
    await _client.from('loans').insert({
      'chama_id': chamaId,
      'member_id': memberId,
      'principal': principal,
      'purpose': purpose,
      'status': 'pending',
    });
  }

  /// Chairperson/treasurer records a loan directly as disbursed — used for
  /// members with no app account to "request" it themselves. See
  /// record_loan_for_member() in 0003_managed_members.sql.
  Future<String> recordLoanForMember({
    required String chamaId,
    required String memberId,
    required double principal,
    double interestRate = 0,
    String? purpose,
    DateTime? dueDate,
  }) async {
    final result = await _client.rpc('record_loan_for_member', params: {
      'p_chama_id': chamaId,
      'p_member_id': memberId,
      'p_principal': principal,
      'p_interest_rate': interestRate,
      'p_purpose': purpose,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    });
    return result as String;
  }

  Future<void> approveAndDisburse({
    required String loanId,
    required double interestRate,
    DateTime? dueDate,
  }) async {
    await _client.from('loans').update({
      'interest_rate': interestRate,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'status': 'active',
    }).eq('id', loanId);
  }

  Future<void> reject(String loanId) async {
    await _client.from('loans').update({'status': 'rejected'}).eq('id', loanId);
  }

  Future<List<LoanRepayment>> repaymentsFor(String loanId) async {
    final rows = await _client
        .from('loan_repayments')
        .select()
        .eq('loan_id', loanId)
        .order('repaid_at', ascending: false);
    return (rows as List)
        .map((r) => LoanRepayment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordRepayment({
    required String loanId,
    required double amount,
  }) async {
    await _client.from('loan_repayments').insert({
      'loan_id': loanId,
      'amount': amount,
      'recorded_by': _client.auth.currentUser!.id,
    });
  }
}

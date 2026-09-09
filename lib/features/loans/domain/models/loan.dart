/// A loan request/record, joined with the borrower's profile for display.
class Loan {
  const Loan({
    required this.id,
    required this.chamaId,
    required this.memberId,
    required this.principal,
    required this.interestRate,
    required this.totalDue,
    required this.amountRepaid,
    required this.status,
    this.purpose,
    this.dueDate,
    required this.createdAt,
    this.borrowerName,
    this.isMine = false,
    this.rejectionReason,
  });

  final String id;
  final String chamaId;
  final String memberId;
  final double principal;
  final double interestRate;
  final double totalDue;
  final double amountRepaid;
  final String status; // pending | approved | rejected | active | repaid | defaulted
  final String? purpose;
  final DateTime? dueDate;
  final DateTime createdAt;
  final String? borrowerName;
  final bool isMine;

  /// Why it was turned down. Always present on a rejected loan — the
  /// database refuses a rejection without one.
  final String? rejectionReason;

  double get outstanding => (totalDue - amountRepaid).clamp(0, double.infinity);

  factory Loan.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final memberJoin = json['chama_members'] as Map<String, dynamic>?;
    final profile = memberJoin?['profiles'] as Map<String, dynamic>?;
    final ownerUserId = memberJoin?['user_id'] as String?;

    return Loan(
      id: json['id'] as String,
      chamaId: json['chama_id'] as String,
      memberId: json['member_id'] as String,
      principal: (json['principal'] as num).toDouble(),
      interestRate: (json['interest_rate'] as num?)?.toDouble() ?? 0,
      totalDue: (json['total_due'] as num?)?.toDouble() ?? 0,
      amountRepaid: (json['amount_repaid'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String,
      purpose: json['purpose'] as String?,
      dueDate: json['due_date'] == null ? null : DateTime.parse(json['due_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      borrowerName: profile?['full_name'] as String? ??
          memberJoin?['managed_full_name'] as String? ??
          profile?['email'] as String?,
      isMine: currentUserId != null && ownerUserId == currentUserId,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }
}

class LoanRepayment {
  const LoanRepayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.repaidAt,
  });

  final String id;
  final String loanId;
  final double amount;
  final DateTime repaidAt;

  factory LoanRepayment.fromJson(Map<String, dynamic> json) => LoanRepayment(
        id: json['id'] as String,
        loanId: json['loan_id'] as String,
        amount: (json['amount'] as num).toDouble(),
        repaidAt: DateTime.parse(json['repaid_at'] as String),
      );
}

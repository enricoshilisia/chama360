/// How often a loan's interest rate is charged. A rate on its own says
/// nothing — "10%" is either the whole cost of the loan or 10% every
/// month, and over a year those differ tenfold.
enum InterestPeriod {
  oneOff('one_off', 'One-off', 'of the amount, once'),
  perMonth('per_month', 'Per month', 'of the amount, every month'),
  perAnnum('per_annum', 'Per year', 'of the amount, every year');

  const InterestPeriod(this.value, this.label, this.explainer);

  final String value;
  final String label;
  final String explainer;

  static InterestPeriod fromValue(String? v) => switch (v) {
        'per_month' => InterestPeriod.perMonth,
        'per_annum' => InterestPeriod.perAnnum,
        _ => InterestPeriod.oneOff,
      };

  /// Shown next to a rate, e.g. "5% a month".
  String get suffix => switch (this) {
        InterestPeriod.oneOff => '',
        InterestPeriod.perMonth => ' a month',
        InterestPeriod.perAnnum => ' a year',
      };
}

/// A loan request/record, joined with the borrower's profile for display.
class Loan {
  const Loan({
    required this.id,
    required this.chamaId,
    required this.memberId,
    required this.principal,
    required this.interestRate,
    this.interestPeriod = InterestPeriod.oneOff,
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
  final InterestPeriod interestPeriod;
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

  /// What the chama charges for this loan, over its whole term. This is
  /// the chama's income from lending, as opposed to the principal, which
  /// is its own money coming back.
  double get interestAmount => (totalDue - principal).clamp(0, double.infinity);

  /// "5% a month", or just "No interest".
  String get rateLabel => interestRate == 0
      ? 'No interest'
      : '${interestRate % 1 == 0 ? interestRate.toStringAsFixed(0) : interestRate}%'
          '${interestPeriod.suffix}';

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
      interestPeriod: InterestPeriod.fromValue(json['interest_period'] as String?),
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

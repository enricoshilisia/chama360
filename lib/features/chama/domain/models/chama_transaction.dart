/// Row from the `transactions` ledger table (auto-populated by DB triggers,
/// see supabase/migrations/0001_init_schema.sql), joined with the member's
/// name so the activity feed can show who a contribution/loan belongs to
/// without a second lookup.
class ChamaTransaction {
  const ChamaTransaction({
    required this.id,
    required this.chamaId,
    required this.memberId,
    required this.type,
    required this.amount,
    this.balanceAfter,
    required this.createdAt,
    this.memberName,
  });

  final String id;
  final String chamaId;
  final String? memberId;
  final String type; // contribution | loan_disbursement | loan_repayment | penalty | withdrawal
  final double amount;
  final double? balanceAfter;
  final DateTime createdAt;
  final String? memberName;

  factory ChamaTransaction.fromJson(Map<String, dynamic> json) {
    final memberJoin = json['chama_members'] as Map<String, dynamic>?;
    final profile = memberJoin?['profiles'] as Map<String, dynamic>?;
    final name = (profile?['full_name'] as String?)?.trim();
    final resolvedName = (name != null && name.isNotEmpty)
        ? name
        : (memberJoin?['managed_full_name'] as String? ?? profile?['email'] as String?);

    return ChamaTransaction(
      id: json['id'] as String,
      chamaId: json['chama_id'] as String,
      memberId: json['member_id'] as String?,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      balanceAfter: (json['balance_after'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      memberName: resolvedName,
    );
  }

  Map<String, Object?> toCacheRow() => {
        'id': id,
        'chama_id': chamaId,
        'member_id': memberId,
        'type': type,
        'amount': amount,
        'balance_after': balanceAfter,
        'created_at': createdAt.toIso8601String(),
        'member_name': memberName,
      };

  factory ChamaTransaction.fromCacheRow(Map<String, Object?> row) {
    return ChamaTransaction(
      id: row['id'] as String,
      chamaId: row['chama_id'] as String,
      memberId: row['member_id'] as String?,
      type: row['type'] as String,
      amount: (row['amount'] as num).toDouble(),
      balanceAfter: (row['balance_after'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
      memberName: row['member_name'] as String?,
    );
  }
}

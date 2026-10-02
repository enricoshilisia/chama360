/// One member's shares moved into another member's name.
///
/// The chama holds exactly what it held before — only the ownership
/// split changed — so this is deliberately not a contribution. What
/// somebody paid in, and when, stays a historical fact; this records that
/// the holding moved, who moved it and why.
class ShareTransfer {
  const ShareTransfer({
    required this.id,
    required this.amount,
    required this.reason,
    required this.createdAt,
    required this.fromMemberId,
    required this.fromName,
    required this.toMemberId,
    required this.toName,
    required this.performedByName,
  });

  final String id;
  final double amount;

  /// Always present — the database refuses a transfer without one.
  final String reason;

  final DateTime createdAt;
  final String fromMemberId;
  final String fromName;
  final String toMemberId;
  final String toName;

  /// The admin who carried it out, by name. The point of the audit.
  final String performedByName;

  bool isOutgoingFor(String memberId) => fromMemberId == memberId;
  bool involves(String memberId) => fromMemberId == memberId || toMemberId == memberId;

  /// How this transfer changed [memberId]'s holding: negative if they
  /// gave the shares away, positive if they received them.
  double signedFor(String memberId) {
    if (fromMemberId == memberId) return -amount;
    if (toMemberId == memberId) return amount;
    return 0;
  }

  factory ShareTransfer.fromJson(Map<String, dynamic> json) => ShareTransfer(
        id: json['id'] as String,
        amount: (json['amount'] as num).toDouble(),
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        fromMemberId: json['from_member_id'] as String,
        fromName: json['from_name'] as String? ?? 'A member',
        toMemberId: json['to_member_id'] as String,
        toName: json['to_name'] as String? ?? 'A member',
        performedByName: json['performed_by_name'] as String? ?? 'An administrator',
      );
}

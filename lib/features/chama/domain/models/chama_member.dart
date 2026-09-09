/// A member as returned by chama_roster(). Everyone in a chama can see who
/// else is in it and in what role; amounts come back null unless the caller
/// is an admin or it's their own row, which is enforced in the database
/// rather than here — see 0007_member_privacy_and_loan_approval.sql.
class ChamaMember {
  const ChamaMember({
    required this.id,
    required this.userId,
    required this.role,
    required this.displayName,
    this.balance,
    this.email,
    this.phone,
    this.isSelf = false,
  });

  final String id;
  final String? userId; // null => chairperson-managed, no app access
  final String role;
  final String displayName;

  /// Null when the viewer isn't allowed to know it. Not zero — zero is a
  /// real balance, and showing it would be a lie.
  final double? balance;

  final String? email;
  final String? phone;
  final bool isSelf;

  bool get hasAccount => userId != null;
  bool get canSeeBalance => balance != null;

  factory ChamaMember.fromRoster(Map<String, dynamic> json) {
    return ChamaMember(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      role: json['role'] as String? ?? 'member',
      displayName: json['display_name'] as String? ?? 'Member',
      balance: (json['balance'] as num?)?.toDouble(),
      phone: json['phone'] as String?,
      isSelf: json['is_self'] as bool? ?? false,
    );
  }
}

/// A member row, whether they have their own app account or were added
/// directly by the chairperson/treasurer with no login of their own.
class ChamaMember {
  const ChamaMember({
    required this.id,
    required this.userId,
    required this.role,
    required this.balance,
    required this.displayName,
    this.email,
    this.phone,
  });

  final String id;
  final String? userId; // null => chairperson-managed, no app access
  final String role;
  final double balance;
  final String displayName;
  final String? email;
  final String? phone;

  bool get hasAccount => userId != null;

  factory ChamaMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final managedName = json['managed_full_name'] as String?;
    final name = (profile?['full_name'] as String?)?.trim();

    return ChamaMember(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      role: json['role'] as String? ?? 'member',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      displayName: (name != null && name.isNotEmpty)
          ? name
          : (managedName ?? profile?['email'] as String? ?? 'Member'),
      email: profile?['email'] as String?,
      phone: json['managed_phone'] as String? ?? profile?['phone'] as String?,
    );
  }
}

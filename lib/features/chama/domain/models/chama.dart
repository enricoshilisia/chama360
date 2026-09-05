/// A chama the current user belongs to, joined with their own membership
/// row so role/balance are available without a second query.
class Chama {
  const Chama({
    required this.id,
    required this.name,
    this.description,
    required this.inviteCode,
    required this.currency,
    required this.memberId,
    required this.role,
    required this.balance,
  });

  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final String currency;
  final String memberId; // this user's chama_members.id
  final String role;
  final double balance;

  factory Chama.fromMemberJoin(Map<String, dynamic> row) {
    final chama = row['chamas'] as Map<String, dynamic>;
    return Chama(
      id: chama['id'] as String,
      name: chama['name'] as String,
      description: chama['description'] as String?,
      inviteCode: chama['invite_code'] as String,
      currency: chama['currency'] as String? ?? 'KES',
      memberId: row['id'] as String,
      role: row['role'] as String? ?? 'member',
      balance: (row['balance'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toCacheRow() => {
        'id': id,
        'name': name,
        'description': description,
        'invite_code': inviteCode,
        'currency': currency,
        'role': role,
        'balance': balance,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory Chama.fromCacheRow(Map<String, Object?> row) => Chama(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        inviteCode: row['invite_code'] as String? ?? '',
        currency: row['currency'] as String? ?? 'KES',
        memberId: '',
        role: row['role'] as String? ?? 'member',
        balance: (row['balance'] as num?)?.toDouble() ?? 0,
      );
}

/// Why a member is no longer on the active roster.
///
/// A fixed list rather than free text: "removed" with no reason told a
/// future chairperson nothing and read as expulsion whatever had actually
/// happened. Someone reading the chama's history in ten years should be
/// able to tell a death from a departure.
enum ArchiveReason {
  deceased('deceased', 'Deceased'),
  left('left', 'Left the chama'),
  relocated('relocated', 'Relocated'),
  inactive('inactive', 'Stopped contributing'),
  removed('removed', 'Removed by the chama'),
  other('other', 'Other');

  const ArchiveReason(this.value, this.label);

  final String value;
  final String label;

  /// "Other" is only useful if it says what the other thing was.
  bool get needsNote => this == ArchiveReason.other;

  static ArchiveReason? fromValue(String? v) {
    if (v == null) return null;
    for (final r in ArchiveReason.values) {
      if (r.value == v) return r;
    }
    return null;
  }
}

/// A member who has left the roster, with the reason kept against them.
class ArchivedMember {
  const ArchivedMember({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
    this.archivedAt,
    this.reason,
    this.note,
    this.archivedBalance,
    required this.balance,
    required this.archivedByName,
  });

  final String id;
  final String displayName;
  final String role;
  final String status;
  final DateTime? archivedAt;
  final ArchiveReason? reason;
  final String? note;

  /// What they held at the moment they were archived. Kept separately
  /// because shares can be transferred away afterwards, and then nothing
  /// else can answer "what did they have when they left".
  final double? archivedBalance;

  /// What stands in their name now.
  final double balance;

  final String archivedByName;

  /// Rows from before this was recorded carry no reason at all; saying so
  /// is better than inventing one.
  String get reasonLabel => reason?.label ?? 'No reason recorded';

  bool get stillHoldsShares => balance > 0;

  factory ArchivedMember.fromJson(Map<String, dynamic> json) => ArchivedMember(
        id: json['id'] as String,
        displayName: json['display_name'] as String? ?? 'Member',
        role: json['role'] as String? ?? 'member',
        status: json['status'] as String? ?? 'archived',
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
        reason: ArchiveReason.fromValue(json['archive_reason'] as String?),
        note: json['archive_note'] as String?,
        archivedBalance: (json['archived_balance'] as num?)?.toDouble(),
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        archivedByName: json['archived_by_name'] as String? ?? 'An administrator',
      );
}

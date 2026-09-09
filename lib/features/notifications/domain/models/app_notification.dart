class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.body,
    this.chamaId,
    required this.isRead,
    required this.createdAt,
    this.linkType,
    this.linkId,
  });

  final String id;
  final String title;
  final String? body;
  final String? chamaId;
  final bool isRead;
  final DateTime createdAt;

  /// What this notification is about, so tapping it can open that thing
  /// rather than leaving the reader to go and find it.
  /// 'loan_request' -> a member awaiting a decision (linkId = member id)
  /// 'loan'         -> a specific loan (linkId = loan id)
  final String? linkType;
  final String? linkId;

  bool get isLoanRequest => linkType == 'loan_request';

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      chamaId: json['chama_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      linkType: json['link_type'] as String?,
      linkId: json['link_id'] as String?,
    );
  }
}

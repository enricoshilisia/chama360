class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.body,
    this.chamaId,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? body;
  final String? chamaId;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      chamaId: json['chama_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

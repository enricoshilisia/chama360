import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/app_notification.dart';

/// In-app notifications, backed by the `notifications` table + DB triggers
/// (see supabase/migrations/0002_notifications.sql). Push delivery via
/// Firebase Cloud Messaging is a later step — this covers the in-app feed.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetch() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => AppNotification.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Stream<List<AppNotification>> watch() {
    final userId = _client.auth.currentUser!.id;
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }

  Future<void> markRead(String id) {
    return _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllRead() {
    final userId = _client.auth.currentUser!.id;
    return _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}

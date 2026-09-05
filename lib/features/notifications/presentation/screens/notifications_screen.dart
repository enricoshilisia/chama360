import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/app_notification.dart';
import '../providers/notifications_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationsRepositoryProvider).markAllRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifs) {
          if (notifs.isEmpty) {
            return Center(
              child: Text('No notifications yet',
                  style: TextStyle(color: Colors.grey.shade600)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
            itemCount: notifs.length,
            itemBuilder: (context, i) => _NotificationTile(notifs[i]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile(this.notification);

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 16,
        child: InkWell(
          onTap: () {
            if (!notification.isRead) {
              ref.read(notificationsRepositoryProvider).markRead(notification.id);
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!notification.isRead)
                Container(
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notification.title,
                        style: TextStyle(
                          fontWeight: notification.isRead
                              ? FontWeight.w500
                              : FontWeight.w700,
                        )),
                    if (notification.body != null) ...[
                      const SizedBox(height: 3),
                      Text(notification.body!,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${notification.createdAt.toLocal()}'.split('.').first,
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

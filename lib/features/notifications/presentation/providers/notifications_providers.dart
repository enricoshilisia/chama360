import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/app_notification.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

final notificationsStreamProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).watch();
});

final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(notificationsStreamProvider).value ?? [];
  return list.where((n) => !n.isRead).length;
});

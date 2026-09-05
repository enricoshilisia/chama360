import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits true/false whenever the device gains/loses a usable network path.
/// Screens use this to show an "Offline — showing cached data" banner and
/// to gate whether writes go straight to Supabase or into the local outbox.
final connectivityStreamProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));
});

final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityStreamProvider).value ?? true;
});

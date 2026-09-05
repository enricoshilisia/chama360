import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a Stream (Supabase's auth state changes) into a Listenable that
/// GoRouter's `refreshListenable` understands, so the router re-evaluates
/// its `redirect` callback every time the user signs in/out.
/// Standard go_router + Supabase integration snippet.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

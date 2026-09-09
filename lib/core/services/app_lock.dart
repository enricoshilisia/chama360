import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'biometric_providers.dart';

/// Locks the app and gets out of the way.
///
/// Locking without leaving would sit on the lock screen with the session
/// still in memory and the app still in the recents list showing whatever
/// was last on screen. Closing means the next launch starts cold at the
/// biometric prompt, which is the point of locking at all.
///
/// SystemNavigator.pop() is the Android "go to the home screen" gesture.
/// It is deliberately not called on iOS: Apple treats an app that quits
/// itself as a crash from the user's point of view, and rejects it. There,
/// the lock screen simply stays up.
Future<void> lockApp(WidgetRef ref) async {
  ref.read(isAppUnlockedProvider.notifier).state = false;

  if (kIsWeb) return;
  if (Platform.isAndroid) {
    await SystemNavigator.pop();
  }
}

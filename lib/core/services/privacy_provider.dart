// StateProvider moved to a separate "legacy" import in Riverpod 3.x.
import 'package:flutter_riverpod/legacy.dart';

/// The dashboard's "peek" toggle — when false, every money figure on the
/// home screen (hero balance, report stats, top contributors, chama
/// carousel, activity feed) masks itself behind dots instead of just the
/// one hero number. Not persisted — resets to visible each app launch,
/// same as any "hide balance" control in a banking app.
final balanceVisibleProvider = StateProvider<bool>((ref) => true);

/// Formats a money string, or masks it with dots when hidden.
String maskable(String formatted, bool visible) => visible ? formatted : '••••••';

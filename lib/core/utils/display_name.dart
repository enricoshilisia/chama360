import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_identity.dart';

/// How a person is shown across the app: the name they gave, falling back
/// to something recognisable rather than a raw synthetic email.
String displayNameFor(User? user) {
  final meta = user?.userMetadata;
  final name = (meta?['full_name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;

  final email = user?.email ?? '';
  // Members sign in with a synthetic 2547…@members.chama360.app address —
  // showing that verbatim would mean nothing to them, so prefer the phone.
  if (PhoneIdentity.isSynthetic(email)) return PhoneIdentity.phoneFromEmail(email);
  return email.isEmpty ? 'Member' : email;
}

/// One or two letters for the avatar: initials where a second name exists,
/// otherwise a single letter. Digits are skipped, so a phone-derived name
/// doesn't render as "25".
String initialsFor(String displayName) {
  final parts = displayName
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(p))
      .toList();

  if (parts.isEmpty) {
    final letter = RegExp(r'[A-Za-z]').firstMatch(displayName)?.group(0);
    return (letter ?? '#').toUpperCase();
  }
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

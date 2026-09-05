import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase RPCs raise their `raise exception '...'` text as a
/// PostgrestException — surface that message directly (it's written for
/// the end user, e.g. "You can only be part of one chama for now")
/// instead of a generic fallback.
String friendlyError(Object error, {String fallback = 'Something went wrong. Try again.'}) {
  if (error is PostgrestException) {
    return error.message;
  }
  return fallback;
}

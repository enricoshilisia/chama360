import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_db.dart';

/// Replays whatever was queued in `pending_actions` while the device was
/// offline. Called whenever connectivity flips back to online (see
/// app.dart, which listens to isOnlineProvider and triggers this).
class SyncService {
  SyncService(this._client);

  final SupabaseClient _client;
  final _localDb = LocalDb.instance;

  Future<void> syncPendingActions() async {
    final pending = await _localDb.getPendingActions();
    for (final action in pending) {
      final type = action['action_type'] as String;
      final payload = jsonDecode(action['payload'] as String) as Map<String, dynamic>;
      final localId = action['local_id'] as int;

      try {
        switch (type) {
          case 'add_contribution':
            await _client.from('contributions').insert({
              'chama_id': payload['chama_id'],
              'member_id': payload['member_id'],
              'amount': payload['amount'],
              'notes': payload['notes'],
              'contribution_date': payload['contribution_date'],
              'recorded_by': _client.auth.currentUser!.id,
            });
            break;
          default:
            // Unknown action type — leave it queued rather than drop it.
            continue;
        }
        await _localDb.markActionSynced(localId);
      } catch (_) {
        // Leave it queued; next connectivity change retries it.
      }
    }
  }
}

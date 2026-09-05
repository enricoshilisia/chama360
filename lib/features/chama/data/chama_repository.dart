import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/local_db.dart';
import '../domain/models/chama.dart';
import '../domain/models/chama_member.dart';
import '../domain/models/chama_transaction.dart';

/// All chama reads/writes go through here. Every read tries Supabase first
/// and falls back to the SQLite cache when offline; every successful read
/// refreshes the cache so the next offline open has fresh-enough data.
class ChamaRepository {
  ChamaRepository(this._client);

  final SupabaseClient _client;
  final _localDb = LocalDb.instance;

  Future<List<Chama>> myChamas({bool online = true}) async {
    if (!online) {
      final rows = await _localDb.getCachedChamas();
      return rows.map(Chama.fromCacheRow).toList();
    }

    try {
      final userId = _client.auth.currentUser!.id;
      final rows = await _client
          .from('chama_members')
          .select('id, role, balance, status, chamas(*)')
          .eq('user_id', userId)
          .eq('status', 'active');

      final chamas = (rows as List)
          .map((r) => Chama.fromMemberJoin(r as Map<String, dynamic>))
          .toList();

      for (final c in chamas) {
        await _localDb.upsertChama(c.toCacheRow());
      }
      return chamas;
    } catch (_) {
      final rows = await _localDb.getCachedChamas();
      return rows.map(Chama.fromCacheRow).toList();
    }
  }

  Future<String> createChama({
    required String name,
    String? description,
  }) async {
    final result = await _client.rpc('create_chama', params: {
      'p_name': name,
      'p_description': description,
    });
    return result as String;
  }

  Future<String> joinChamaByCode(String inviteCode) async {
    final result = await _client.rpc('join_chama_by_code', params: {
      'p_invite_code': inviteCode.trim().toUpperCase(),
    });
    return result as String;
  }

  Future<List<ChamaTransaction>> transactionsFor(
    String chamaId, {
    bool online = true,
  }) async {
    if (!online) {
      final rows = await _localDb.getCachedTransactions(chamaId);
      return rows.map(ChamaTransaction.fromCacheRow).toList();
    }

    try {
      final rows = await _client
          .from('transactions')
          .select()
          .eq('chama_id', chamaId)
          .order('created_at', ascending: false)
          .limit(50);

      final txns = (rows as List)
          .map((r) => ChamaTransaction.fromJson(r as Map<String, dynamic>))
          .toList();

      await _localDb.replaceTransactions(
        chamaId,
        txns.map((t) => t.toCacheRow()).toList(),
      );
      return txns;
    } catch (_) {
      final rows = await _localDb.getCachedTransactions(chamaId);
      return rows.map(ChamaTransaction.fromCacheRow).toList();
    }
  }

  /// Most recent ledger activity across every chama the user belongs to —
  /// powers the home dashboard's activity feed. A single query filtered by
  /// chama_id IN (...) rather than one query per chama.
  Future<List<ChamaTransaction>> recentActivity(List<String> chamaIds) async {
    if (chamaIds.isEmpty) return [];
    final rows = await _client
        .from('transactions')
        .select()
        .inFilter('chama_id', chamaIds)
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((r) => ChamaTransaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChamaMember>> members(String chamaId) async {
    final rows = await _client
        .from('chama_members')
        .select(
            'id, user_id, role, balance, joined_at, managed_full_name:full_name, managed_phone:phone, profiles(full_name, email, avatar_url, phone)')
        .eq('chama_id', chamaId)
        .eq('status', 'active');
    return (rows as List)
        .map((r) => ChamaMember.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Admin-only (enforced by the chama_members_admin_update RLS policy).
  Future<void> updateMemberRole(String memberId, String newRole) async {
    await _client.from('chama_members').update({'role': newRole}).eq('id', memberId);
  }

  /// Soft-removes a member (status -> 'removed') rather than deleting the
  /// row, so their historical contributions/loans stay intact.
  Future<void> removeMember(String memberId) async {
    await _client.from('chama_members').update({'status': 'removed'}).eq('id', memberId);
  }

  /// Chairperson/treasurer adds someone with no app account of their own —
  /// see add_managed_member() in 0003_managed_members.sql.
  Future<String> addManagedMember({
    required String chamaId,
    required String fullName,
    String? phone,
    String role = 'member',
  }) async {
    final result = await _client.rpc('add_managed_member', params: {
      'p_chama_id': chamaId,
      'p_full_name': fullName,
      'p_phone': phone,
      'p_role': role,
    });
    return result as String;
  }

  /// Records a contribution, optionally backdated (the chairperson logging
  /// a contribution someone made in the past). If offline, queues it in the
  /// local outbox instead of failing outright — SyncService replays it later.
  Future<void> addContribution({
    required String chamaId,
    required String memberId,
    required double amount,
    String? notes,
    DateTime? contributionDate,
    bool online = true,
  }) async {
    final dateStr = (contributionDate ?? DateTime.now()).toIso8601String().split('T').first;

    if (!online) {
      await _localDb.enqueueAction(
        'add_contribution',
        '{"chama_id":"$chamaId","member_id":"$memberId","amount":$amount,'
            '"notes":${notes == null ? 'null' : '"$notes"'},"contribution_date":"$dateStr"}',
      );
      return;
    }
    await _client.from('contributions').insert({
      'chama_id': chamaId,
      'member_id': memberId,
      'amount': amount,
      'notes': notes,
      'contribution_date': dateStr,
      'recorded_by': _client.auth.currentUser!.id,
    });
  }
}

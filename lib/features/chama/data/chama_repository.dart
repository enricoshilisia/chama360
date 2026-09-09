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

  /// Joins the ledger to the contributing/borrowing member's name — used by
  /// every transactions query so activity feeds never show a bare amount
  /// with no indication of whose it is.
  static const _transactionSelect =
      '*, chama_members(user_id, managed_full_name:full_name, profiles(full_name, email))';

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

  /// Submits an application to run a chama. Deliberately callable with no
  /// account — nothing exists on the platform until the owner approves,
  /// at which point the chama is created and Supabase invites the
  /// chairperson to set a password (see 0006_gated_registration.sql).
  ///
  /// Emailing the owner is best-effort: the application is already stored,
  /// so a mail failure shouldn't tell the applicant their submission
  /// failed when it didn't.
  Future<void> submitChamaRegistration({
    required String chamaName,
    String? description,
    required String contactName,
    required String contactPhone,
    required String contactEmail,
  }) async {
    final result = await _client.rpc('submit_chama_registration', params: {
      'p_chama_name': chamaName,
      'p_description': description,
      'p_contact_name': contactName,
      'p_contact_phone': contactPhone,
      'p_contact_email': contactEmail,
    });

    final row = (result as List).first as Map<String, dynamic>;
    final registrationId = row['registration_id'] as String;

    try {
      await _client.functions.invoke(
        'notify-chama-registration',
        body: {'registration_id': registrationId},
      );
    } catch (_) {
      // Stored either way; only the notification didn't go out.
    }
  }

  /// Creates a phone + temporary-password login for a member who doesn't
  /// have one. Returns the temporary password once, for the chairperson to
  /// pass on — it is never stored anywhere readable.
  Future<({String phone, String temporaryPassword})> createMemberLogin({
    required String chamaId,
    required String memberId,
    required String phone,
  }) async {
    final response = await _client.functions.invoke(
      'create-member-login',
      body: {'chama_id': chamaId, 'member_id': memberId, 'phone': phone},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception(data['error'] as String);
    }
    return (
      phone: data['phone'] as String,
      temporaryPassword: data['temporary_password'] as String,
    );
  }

  /// Issues a fresh temporary password for a member who already has a
  /// login — the "they forgot it" path. Returns it once, for the
  /// chairperson to pass on; the member must replace it on next sign-in.
  Future<({String memberName, String temporaryPassword})> resetMemberPassword({
    required String chamaId,
    required String memberId,
  }) async {
    final response = await _client.functions.invoke(
      'reset-member-password',
      body: {'chama_id': chamaId, 'member_id': memberId},
    );

    final data = response.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception(data['error'] as String);
    }
    return (
      memberName: data['member_name'] as String? ?? 'Member',
      temporaryPassword: data['temporary_password'] as String,
    );
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
          .select(_transactionSelect)
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

  /// A single member's full activity within a chama — contributions, loan
  /// disbursements, repayments — for their "history" view.
  Future<List<ChamaTransaction>> transactionsForMember(
    String chamaId,
    String memberId,
  ) async {
    final rows = await _client
        .from('transactions')
        .select(_transactionSelect)
        .eq('chama_id', chamaId)
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => ChamaTransaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Most recent ledger activity across every chama the user belongs to —
  /// powers the home dashboard's activity feed. A single query filtered by
  /// chama_id IN (...) rather than one query per chama.
  Future<List<ChamaTransaction>> recentActivity(List<String> chamaIds) async {
    if (chamaIds.isEmpty) return [];
    final rows = await _client
        .from('transactions')
        .select(_transactionSelect)
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

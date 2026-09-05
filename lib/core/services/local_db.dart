import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache for offline-first behaviour.
///
/// Two jobs:
///  1. Cache read-mostly data (chamas, balances, transactions, notifications)
///     so the app opens instantly and stays usable with no signal.
///  2. Queue writes made while offline (e.g. "record a contribution") in
///     `pending_actions`, then replay them through the matching repository
///     once connectivity returns (see ConnectivityService + SyncService).
///
/// `sqflite` has no web implementation, and web isn't the target platform
/// for this app (see README) — every method below is a no-op there instead
/// of throwing, so the rest of the app doesn't need to know or care.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'chama360.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_chamas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            invite_code TEXT,
            currency TEXT,
            role TEXT,
            balance REAL DEFAULT 0,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_transactions (
            id TEXT PRIMARY KEY,
            chama_id TEXT NOT NULL,
            member_id TEXT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            balance_after REAL,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_notifications (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            body TEXT,
            created_at TEXT,
            is_read INTEGER DEFAULT 0
          )
        ''');
        // Generic outbox: anything written while offline lands here first,
        // tagged with the repository action that should replay it.
        await db.execute('''
          CREATE TABLE pending_actions (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> upsertChama(Map<String, Object?> row) async {
    if (kIsWeb) return;
    final db = await database;
    await db.insert('cached_chamas', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getCachedChamas() async {
    if (kIsWeb) return [];
    final db = await database;
    return db.query('cached_chamas', orderBy: 'name ASC');
  }

  Future<void> replaceTransactions(
      String chamaId, List<Map<String, Object?>> rows) async {
    if (kIsWeb) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('cached_transactions',
          where: 'chama_id = ?', whereArgs: [chamaId]);
      for (final row in rows) {
        await txn.insert('cached_transactions', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, Object?>>> getCachedTransactions(
      String chamaId) async {
    if (kIsWeb) return [];
    final db = await database;
    return db.query('cached_transactions',
        where: 'chama_id = ?',
        whereArgs: [chamaId],
        orderBy: 'created_at DESC');
  }

  /// Queue a write made while offline. [actionType] identifies which
  /// repository method should replay [payloadJson] (e.g. "add_contribution").
  Future<void> enqueueAction(String actionType, String payloadJson) async {
    if (kIsWeb) return;
    final db = await database;
    await db.insert('pending_actions', {
      'action_type': actionType,
      'payload': payloadJson,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<List<Map<String, Object?>>> getPendingActions() async {
    if (kIsWeb) return [];
    final db = await database;
    return db.query('pending_actions',
        where: 'synced = 0', orderBy: 'created_at ASC');
  }

  Future<void> markActionSynced(int localId) async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete('pending_actions',
        where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<int> pendingActionCount() async {
    if (kIsWeb) return 0;
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM pending_actions WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'catet_duit_dewe.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE wallets (
            id TEXT PRIMARY KEY,
            name TEXT,
            balance REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            amount REAL,
            type TEXT, -- 'expense' atau 'income'
            category TEXT,
            wallet_id TEXT,
            source TEXT, -- 'chat', 'notif', 'manual'
            created_at TEXT
          )
        ''');

        // Saldo awal default dompet
        final initialWallets = [
          {'id': 'cimb', 'name': 'CIMB Niaga', 'balance': 8930697.0},
          {'id': 'bca', 'name': 'BCA', 'balance': 114307.0},
          {'id': 'mandiri', 'name': 'Mandiri', 'balance': 25666.0},
          {'id': 'ovo', 'name': 'OVO', 'balance': 13955.0},
          {'id': 'gopay', 'name': 'GoPay', 'balance': 4614.0},
        ];
        for (var w in initialWallets) {
          await db.insert('wallets', w);
        }
      },
    );
  }

  static Future<List>> getWallets() async {
    final db = await database;
    return await db.query('wallets');
  }

  static Future<List>> getTransactions() async {
    final db = await database;
    return await db.query('transactions', orderBy: 'id DESC');
  }

  static Future<void> insertTransaction({
    required String title,
    required double amount,
    required String type,
    required String category,
    required String walletId,
    required String source,
  }) async {
    final db = await database;
    await db.insert('transactions', {
      'title': title,
      'amount': amount,
      'type': type,
      'category': category,
      'wallet_id': walletId,
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Update saldo dompet terkait
    final wallets = await db.query('wallets', where: 'id = ?', whereArgs: [walletId]);
    if (wallets.isNotEmpty) {
      double current = (wallets.first['balance'] as num).toDouble();
      double updated = type == 'income' ? current + amount : current - amount;
      await db.update('wallets', {'balance': updated}, where: 'id = ?', whereArgs: [walletId]);
    }
  }
}

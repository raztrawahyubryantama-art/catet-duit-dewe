import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = p.join(await getDatabasesPath(), 'catet_duit_dewe.db');
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
            type TEXT,
            category TEXT,
            wallet_id TEXT,
            source TEXT,
            created_at TEXT
          )
        ''');

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

  static Future<List> getWallets() async {
    final db = await database;
    return await db.query('wallets');
  }

  static Future<List> getTransactions() async {
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

    final wallets = await db.query('wallets', where: 'id = ?', whereArgs: [walletId]);
    if (wallets.isNotEmpty) {
      double current = (wallets.first['balance'] as num).toDouble();
      double updated = type == 'income' ? current + amount : current - amount;
      await db.update('wallets', {'balance': updated}, where: 'id = ?', whereArgs: [walletId]);
    }
  }
}

class SmartFinanceParser {
  static const allowedPackages = [
    'id.co.cimbniaga.mobile.android',
    'com.bca',
    'id.bmri.livin',
    'com.gojek.app',
    'ovo.id',
    'com.google.android.gm',
  ];

  static const String geminiApiKey = '';

  static Future parseText(String rawText) async {
    final lower = rawText.toLowerCase();

    double amount = 0;
    final rbMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:rb|ribu|k)\b').firstMatch(lower);
    final jtMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:jt|juta)\b').firstMatch(lower);
    final rpMatch = RegExp(r'(?:rp\.?\s*)(\d{1,3}(?:[.,]\d{3})+|\d+)').firstMatch(lower);

    if (jtMatch != null) {
      amount = double.parse(jtMatch.group(1)!.replaceAll(',', '.')) * 1000000;
    } else if (rbMatch != null) {
      amount = double.parse(rbMatch.group(1)!.replaceAll(',', '.')) * 1000;
    } else if (rpMatch != null) {
      amount = double.parse(rpMatch.group(1)!.replaceAll('.', '').replaceAll(',', ''));
    }

    if (amount <= 0) return null;

    final isIncome = RegExp(r'\b(gaji|gajian|bonus|masuk|diterima|transfer masuk|kredit|cr|top up berhasil)\b').hasMatch(lower);
    final type = isIncome ? 'income' : 'expense';

    String walletId = 'cimb';
    if (lower.contains('bca')) {
      walletId = 'bca';
    } else if (lower.contains('mandiri') || lower.contains('livin')) {
      walletId = 'mandiri';
    } else if (lower.contains('ovo')) {
      walletId = 'ovo';
    } else if (lower.contains('gopay') || lower.contains('gojek')) {
      walletId = 'gopay';
    }

    String category = isIncome ? 'Gaji / Pemasukan' : 'Lain-lain';
    if (!isIncome) {
      if (RegExp(r'\b(makan|minum|kopi|nasi|jus|kantin|cafe|warteg|tuku|jajan)\b').hasMatch(lower)) {
        category = 'Makan dan Minum';
      } else if (RegExp(r'\b(bensin|pertalite|pertamax|parkir|tol|grab|gojek|ojol)\b').hasMatch(lower)) {
        category = 'Transportasi';
      } else if (RegExp(r'\b(game|nonton|bioskop|netflix|spotify|hiburan)\b').hasMatch(lower)) {
        category = 'Hiburan';
      } else if (RegExp(r'\b(listrik|token|wifi|pulsa|kuota|air)\b').hasMatch(lower)) {
        category = 'Tagihan & Utilitas';
      }
    }

    String cleanTitle = rawText.length > 42 ? '${rawText.substring(0, 42)}...' : rawText;
    if (geminiApiKey.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [{
              'parts': [{
                'text': 'Ekstrak transaksi keuangan dari teks ini menjadi JSON murni tanpa markdown: {"title":"nama transaksi singkat","amount":angka,"type":"income/expense","category":"Makan dan Minum/Transportasi/Hiburan/Tagihan/Gaji/Lain-lain","walletId":"cimb/bca/mandiri/ovo/gopay"}. Teks: "$rawText"'
              }]
            }]
          }),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final text = data['candidates'][0]['content']['parts'][0]['text']
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          return jsonDecode(text);
        }
      } catch (_) {}
    }

    return {
      'title': cleanTitle,
      'amount': amount,
      'type': type,
      'category': category,
      'walletId': walletId,
    };
  }
}

@pragma('vm:entry-point')
void notificationCallback(NotificationEvent evt) async {
  if (evt.packageName == null) return;
  if (!SmartFinanceParser.allowedPackages.contains(evt.packageName)) return;

  final fullText = '${evt.title ?? ''} ${evt.text ?? ''}'.trim();
  final parsed = await SmartFinanceParser.parseText(fullText);

  if (parsed != null) {
    await DBHelper.insertTransaction(
      title: parsed['title'],
      amount: (parsed['amount'] as num).toDouble(),
      type: parsed['type'],
      category: parsed['category'],
      walletId: parsed['walletId'],
      source: 'notif',
    );
    final SendPort? send = IsolateNameServer.lookupPortByName('_notif_port_');
    send?.send('refresh');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CatetDuitDeweApp());
}

class CatetDuitDeweApp extends StatelessWidget {
  const CatetDuitDeweApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catet Duit Dewe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        cardColor: const Color(0xFF151F32),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          surface: Color(0xFF151F32),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List wallets = [];
  List transactions = [];
  bool isListening = false;
  final ReceivePort _port = ReceivePort();
  final TextEditingController _chatController = TextEditingController();
  final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _initListener();
    _loadData();
  }

  Future<void> _initListener() async {
    IsolateNameServer.registerPortWithName(_port.sendPort, '_notif_port_');
    _port.listen((_) => _loadData());

    await NotificationsListener.initialize(callbackHandle: notificationCallback);
    bool? running = await NotificationsListener.isRunning;
    setState(() => isListening = running ?? false);
  }

  Future<void> _toggleNotificationService() async {
    bool? hasPerm = await NotificationsListener.hasPermission;
    if (hasPerm != true) {
      await NotificationsListener.openPermissionSettings();
      return;
    }
    if (!isListening) {
      await NotificationsListener.startService(
        title: 'Catet Duit Dewe Aktif',
        description: 'Mantau notifikasi transaksi otomatis',
      );
    } else {
      await NotificationsListener.stopService();
    }
    bool? running = await NotificationsListener.isRunning;
    setState(() => isListening = running ?? false);
  }

  Future<void> _loadData() async {
    final w = await DBHelper.getWallets();
    final t = await DBHelper.getTransactions();
    setState(() {
      wallets = w;
      transactions = t;
    });
  }

  Future<void> _handleChatSubmit() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final parsed = await SmartFinanceParser.parseText(text);
    if (parsed != null) {
      await DBHelper.insertTransaction(
        title: parsed['title'],
        amount: (parsed['amount'] as num).toDouble(),
        type: parsed['type'],
        category: parsed['category'],
        walletId: parsed['walletId'],
        source: 'chat',
      );
      _chatController.clear();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tercatet: ${parsed['title']} (${currency.format(parsed['amount'])})')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal durung ketangkep, coba tulis angkane (misal: kopi 20rb)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalExpense = transactions
        .where((t) => t['type'] == 'expense')
        .fold(0.0, (sum, item) => sum + (item['amount'] as num).toDouble());
    double monthlyBudget = 2500000;
    double remaining = monthlyBudget - totalExpense;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catet Duit Dewe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Mode Peteng • Auto-Track Gratis', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _toggleNotificationService,
            icon: Icon(
              isListening ? Icons.notifications_active : Icons.notifications_off,
              color: isListening ? Colors.greenAccent : Colors.orangeAccent,
              size: 18,
            ),
            label: Text(
              isListening ? 'Auto ON' : 'Aktifno Notif',
              style: TextStyle(color: isListening ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12),
            ),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: wallets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final w = wallets[index];
                  return Container(
                    width: 155,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151F32),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(w['name'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          currency.format(w['balance']),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF151F32),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Anggaran Sasi Iki', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${currency.format(totalExpense)} saka ${currency.format(monthlyBudget)}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Sisa ${currency.format(remaining)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (totalExpense / monthlyBudget).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white10,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF151F32),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      onSubmitted: (_) => _handleChatSubmit(),
                      decoration: const InputDecoration(
                        hintText: 'Ketik: "tuku kopi 25rb nggo gopay"...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _handleChatSubmit,
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF2563EB)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Catetan Terakhir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Durung ono catetan. Coba ketik nang ndhuwur utowo tunggu notif bank mlebu.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              )
            else
              ...transactions.map((t) {
                final isInc = t['type'] == 'income';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151F32),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t['title'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('${t['category']} • ${t['wallet_id'].toString().toUpperCase()} (${t['source']})',
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text(
                        '${isInc ? '+' : '-'}${currency.format(t['amount'])}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isInc ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

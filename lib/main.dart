import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';
import 'notification_service.dart';

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
  List> wallets = [];
  List> transactions = [];
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
            // Kartu Saldo Dompet Horizontal
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

            // Kartu Anggaran Bulanan
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

            // Input Chat Cepat
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

            // Daftar Transaksi Terbaru
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

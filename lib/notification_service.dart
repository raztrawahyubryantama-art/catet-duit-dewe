import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:http/http.dart' as http;
import 'db_helper.dart';

class SmartFinanceParser {
  // Daftar package aplikasi keuangan yang dipantau
  static const allowedPackages = [
    'id.co.cimbniaga.mobile.android', // OCTO Mobile
    'com.bca',                        // BCA mobile / myBCA
    'id.bmri.livin',                  // Livin' by Mandiri
    'com.gojek.app',                  // GoPay / Gojek
    'ovo.id',                         // OVO
    'com.google.android.gm',          // Gmail (untuk struk email)
  ];

  // Opsional: Isi API Key gratis dari Google AI Studio untuk parsing kalimat kompleks
  static const String geminiApiKey = '';

  static Future?> parseText(String rawText) async {
    final lower = rawText.toLowerCase();

    // 1. Deteksi Nominal (Rp 25.000, 25rb, 1.5jt, dll)
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

    // 2. Deteksi Jenis Arus Kas (Pemasukan vs Pengeluaran)
    final isIncome = RegExp(r'\b(gaji|gajian|bonus|masuk|diterima|transfer masuk|kredit|cr|top up berhasil)\b').hasMatch(lower);
    final type = isIncome ? 'income' : 'expense';

    // 3. Deteksi Dompet
    String walletId = 'cimb';
    if (lower.contains('bca')) walletId = 'bca';
    else if (lower.contains('mandiri') || lower.contains('livin')) walletId = 'mandiri';
    else if (lower.contains('ovo')) walletId = 'ovo';
    else if (lower.contains('gopay') || lower.contains('gojek')) walletId = 'gopay';

    // 4. Deteksi Kategori Otomatis
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

    // Jika Gemini API Key diisi, gunakan AI untuk merapikan judul transaksi
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

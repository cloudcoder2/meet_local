import 'package:intl/intl.dart';

/// Formats an amount in paisa as taka, e.g. `12350` → `৳123.50`, `12300` → `৳123`.
String formatMoney(int paisa, {String currency = 'BDT'}) {
  final symbol = currency == 'BDT' ? '৳' : '$currency ';
  final taka = paisa / 100;
  final digits = paisa % 100 == 0 ? 0 : 2;
  return '$symbol${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: digits).format(taka)}';
}

String formatDistance(int metres) =>
    metres < 1000 ? '$metres m' : '${(metres / 1000).toStringAsFixed(1)} km';

String formatDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

String formatDateTime(int epochMs) =>
    DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// Mirrors the backend's phone normalisation for Bangladeshi numbers.
String? normalizePhone(String input) {
  final raw = input.replaceAll(RegExp(r'[\s\-()]'), '');
  String phone;
  if (RegExp(r'^01[3-9]\d{8}$').hasMatch(raw)) {
    phone = '+88$raw';
  } else if (RegExp(r'^8801[3-9]\d{8}$').hasMatch(raw)) {
    phone = '+$raw';
  } else {
    phone = raw;
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone) ? phone : null;
}

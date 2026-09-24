import 'package:intl/intl.dart';

String formatMoney(double amount, {String currency = 'KES'}) {
  final formatter = NumberFormat.currency(
    locale: 'en_KE',
    symbol: '$currency ',
    decimalDigits: 2,
  );
  return formatter.format(amount);
}

/// A tighter rendering for figures that share a row on a phone: no
/// decimal places, and thousands shortened once the full number would
/// no longer fit. `KES 1,250,000.00` becomes `KES 1.25M`.
String formatMoneyCompact(double amount, {String currency = 'KES'}) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';

  if (abs >= 1000000) {
    final millions = abs / 1000000;
    final text = millions >= 10
        ? millions.round().toString()
        : millions.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$sign$currency ${text}M';
  }

  return '$sign$currency ${NumberFormat('#,##0', 'en_KE').format(abs)}';
}

import 'package:intl/intl.dart';

String formatMoney(double amount, {String currency = 'KES'}) {
  final formatter = NumberFormat.currency(
    locale: 'en_KE',
    symbol: '$currency ',
    decimalDigits: 2,
  );
  return formatter.format(amount);
}

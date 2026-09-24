import 'package:chama360/core/utils/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact figures stay short enough to share a row', () {
    expect(formatMoneyCompact(0), 'KES 0');
    expect(formatMoneyCompact(2400), 'KES 2,400');
    expect(formatMoneyCompact(48000.5), 'KES 48,001');
    expect(formatMoneyCompact(999999), 'KES 999,999');
    expect(formatMoneyCompact(1000000), 'KES 1M');
    expect(formatMoneyCompact(1250000), 'KES 1.25M');
    expect(formatMoneyCompact(1200000), 'KES 1.2M');
    expect(formatMoneyCompact(12500000), 'KES 13M');
    expect(formatMoneyCompact(-2400), '-KES 2,400');
  });
}

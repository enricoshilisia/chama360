import 'package:flutter_test/flutter_test.dart';

/// Mirrors loan_term_months() in 0016. Kept honest by a test because the
/// first version divided days by 30, which made a full year 13 months and
/// overcharged every annual loan by one month of interest.
int termMonths(DateTime issued, DateTime? due) {
  if (due == null || !due.isAfter(issued)) return 1;
  var months = (due.year - issued.year) * 12 + (due.month - issued.month);
  final dayShort = due.day < issued.day;
  if (dayShort) months -= 1;
  final remainder = dayShort || due.day > issued.day;
  return (months + (remainder ? 1 : 0)).clamp(1, 1200);
}

void main() {
  test('a year is twelve months, not thirteen', () {
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 12, 26)), 12);
  });

  test('a day past the year starts a thirteenth month', () {
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 12, 27)), 13);
  });

  test('a day short of the year is still the twelfth month, begun', () {
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 12, 25)), 12);
  });

  test('exact months come out whole', () {
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 1, 26)), 1);
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 6, 26)), 6);
  });

  test('a part month counts as begun', () {
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2026, 1, 27)), 2);
    expect(termMonths(DateTime(2025, 12, 26), DateTime(2025, 12, 27)), 1);
  });

  test('a February month-end does not lose a month', () {
    // 31 Jan to 28 Feb is a month begun but not completed.
    expect(termMonths(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), 1);
    expect(termMonths(DateTime(2026, 1, 31), DateTime(2026, 3, 31)), 2);
  });

  test('a due date on or before the issue date is one month', () {
    expect(termMonths(DateTime(2026, 1, 10), DateTime(2026, 1, 10)), 1);
    expect(termMonths(DateTime(2026, 1, 10), DateTime(2025, 1, 10)), 1);
    expect(termMonths(DateTime(2026, 1, 10), null), 1);
  });

  test('1% a month over a year is 12%, which is what the chama charges', () {
    const principal = 20000.0;
    final months = termMonths(DateTime(2025, 12, 26), DateTime(2026, 12, 26));
    // closeTo, not equals: binary floating point makes 20000 * 1.12 come
    // out as 22400.000000000004. The database rounds to two places, so
    // the stored figure is exact; this only guards the arithmetic.
    expect(principal * (1 + 0.01 * months), closeTo(22400, 0.01));
  });
}

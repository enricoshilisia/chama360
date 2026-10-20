import 'package:chama360/features/loans/domain/models/loan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors loan_accrued_total() in 0017: interest runs with time, so
/// clearing early costs less. Pinned here because it decides what a
/// member actually hands over.
double accrued(double principal, double rate, InterestPeriod period, int monthsRun,
    int monthsScheduled) {
  final months = monthsRun > monthsScheduled ? monthsScheduled : monthsRun;
  final multiplier = switch (period) {
    InterestPeriod.oneOff => rate / 100,
    InterestPeriod.perMonth => rate / 100 * months,
    InterestPeriod.perAnnum => rate / 100 * months / 12,
  };
  return double.parse((principal * (1 + multiplier)).toStringAsFixed(2));
}

void main() {
  group('a 20,000 loan at 1% a month, taken for 12 months', () {
    test('costs less the earlier it is cleared', () {
      expect(accrued(20000, 1, InterestPeriod.perMonth, 1, 12), 20200);
      expect(accrued(20000, 1, InterestPeriod.perMonth, 6, 12), 21200);
      expect(accrued(20000, 1, InterestPeriod.perMonth, 12, 12), 22400);
    });

    test('never costs more than the agreed total, however late', () {
      // Carrying it past the deadline does not quietly keep adding.
      expect(accrued(20000, 1, InterestPeriod.perMonth, 18, 12), 22400);
      expect(accrued(20000, 1, InterestPeriod.perMonth, 100, 12), 22400);
    });
  });

  test('a flat one-off fee does not shrink by paying early', () {
    // That is what choosing "one-off" rather than "per month" means.
    expect(accrued(20000, 10, InterestPeriod.oneOff, 1, 12), 22000);
    expect(accrued(20000, 10, InterestPeriod.oneOff, 12, 12), 22000);
  });

  test('a yearly rate is pro-rated over the months actually run', () {
    expect(accrued(20000, 12, InterestPeriod.perAnnum, 3, 12), 20600);
    expect(accrued(20000, 12, InterestPeriod.perAnnum, 12, 12), 22400);
  });

  test('the payoff model reads what the database sends', () {
    final p = LoanPayoff.fromJson({
      'loan_id': 'l1',
      'member_id': 'm1',
      'member_name': 'Charity Kimathi',
      'principal': 20000,
      'interest_rate': 1,
      'interest_period': 'per_month',
      'issued_at': '2025-12-26T09:00:00Z',
      'due_date': '2026-12-26',
      'status': 'active',
      'amount_repaid': 5000,
      'scheduled_total': 22400,
      'months_run': 6,
      'months_scheduled': 12,
      'interest_so_far': 1200,
      'settle_today': 16200,
      'saving': 1200,
    });
    expect(p.settleToday, 16200);
    expect(p.saving, 1200);
    expect(p.savesMoney, isTrue);
    expect(p.interestPeriod, InterestPeriod.perMonth);
  });

  test('a loan at its deadline shows nothing left to save', () {
    final p = LoanPayoff.fromJson({
      'loan_id': 'l2', 'member_id': 'm1', 'member_name': 'x',
      'principal': 20000, 'interest_rate': 1, 'interest_period': 'per_month',
      'issued_at': '2025-12-26T09:00:00Z', 'due_date': '2026-12-26',
      'status': 'active', 'amount_repaid': 0, 'scheduled_total': 22400,
      'months_run': 12, 'months_scheduled': 12, 'interest_so_far': 2400,
      'settle_today': 22400, 'saving': 0,
    });
    expect(p.savesMoney, isFalse);
  });
}

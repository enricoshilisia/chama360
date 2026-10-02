import 'package:chama360/features/loans/domain/models/loan.dart';
import 'package:chama360/features/reports/domain/models/chama_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Loan loan({
    required double principal,
    required double rate,
    required InterestPeriod period,
    required double totalDue,
    String status = 'active',
  }) =>
      Loan(
        id: 'l',
        chamaId: 'c',
        memberId: 'm',
        principal: principal,
        interestRate: rate,
        interestPeriod: period,
        totalDue: totalDue,
        amountRepaid: 0,
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  test('a rate reads with the period it is charged over', () {
    expect(loan(principal: 1, rate: 5, period: InterestPeriod.perMonth, totalDue: 1).rateLabel,
        '5% a month');
    expect(loan(principal: 1, rate: 12, period: InterestPeriod.perAnnum, totalDue: 1).rateLabel,
        '12% a year');
    expect(loan(principal: 1, rate: 10, period: InterestPeriod.oneOff, totalDue: 1).rateLabel,
        '10%');
    expect(loan(principal: 1, rate: 0, period: InterestPeriod.perMonth, totalDue: 1).rateLabel,
        'No interest');
  });

  test('interest is what is owed above the principal', () {
    // 5% a month on 10,000 over three months, as the database computes it.
    final l = loan(
        principal: 10000, rate: 5, period: InterestPeriod.perMonth, totalDue: 11500);
    expect(l.interestAmount, 1500);
  });

  test('a loan repaid for less than its principal never shows negative interest', () {
    final l = loan(principal: 10000, rate: 0, period: InterestPeriod.oneOff, totalDue: 0);
    expect(l.interestAmount, 0);
  });

  test('an unknown period from the database falls back to one-off', () {
    expect(InterestPeriod.fromValue(null), InterestPeriod.oneOff);
    expect(InterestPeriod.fromValue('something_new'), InterestPeriod.oneOff);
    expect(InterestPeriod.fromValue('per_month'), InterestPeriod.perMonth);
  });

  test('earnings add collected interest but never interest still owed', () {
    const report = ChamaReport(
      totalContributions: 111600,
      memberCount: 20,
      totalLoansDisbursed: 30000,
      totalOutstanding: 32800,
      activeLoanCount: 3,
      overdueLoanCount: 0,
      monthly: [],
      topContributors: [],
      interestEarned: 1500,
      interestExpected: 2800,
    );

    // Contributions plus interest collected, and nothing else.
    expect(report.totalEarnings, 113100);
    // Money the chama is owed is not money the chama has, so the 2,800
    // still to come in must not be in that figure.
    expect(report.totalEarnings,
        report.totalContributions + report.interestEarned);
  });
}

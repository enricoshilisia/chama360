import 'package:flutter/material.dart';

/// How a ledger row is drawn, in one place, because the activity feed, the
/// chama detail screen and a member's history all draw the same rows.
///
/// A reversal is stored with a negative amount (see reverse_contribution()
/// in 0008_reverse_contribution.sql), so the sign has to come from the
/// amount itself rather than from the type — otherwise a reversal renders
/// as "-KES -1,200".
class TransactionDisplay {
  const TransactionDisplay._({
    required this.label,
    required this.icon,
    required this.isCredit,
  });

  final String label;
  final IconData icon;
  final bool isCredit;

  factory TransactionDisplay.of(String type, double amount) {
    if (amount < 0) {
      return TransactionDisplay._(
        label: type == 'reversal' ? 'REVERSAL' : type.replaceAll('_', ' ').toUpperCase(),
        icon: Icons.undo_rounded,
        isCredit: false,
      );
    }

    return TransactionDisplay._(
      label: type.replaceAll('_', ' ').toUpperCase(),
      icon: switch (type) {
        'contribution' => Icons.savings_rounded,
        'loan_disbursement' => Icons.call_made_rounded,
        'loan_repayment' => Icons.call_received_rounded,
        'penalty' => Icons.warning_amber_rounded,
        'reversal' => Icons.undo_rounded,
        _ => Icons.swap_horiz_rounded,
      },
      isCredit: type == 'contribution' || type == 'loan_disbursement',
    );
  }
}

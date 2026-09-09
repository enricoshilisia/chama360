import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/utils/phone_identity.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../loans/domain/models/loan.dart';
import '../../../loans/presentation/providers/loans_providers.dart';
import '../../../loans/presentation/widgets/loan_decision.dart';
import '../../domain/models/chama_member.dart';
import '../../domain/models/chama_transaction.dart';
import '../providers/chama_providers.dart';

/// A member's full picture within a chama: who they are, their balance,
/// every contribution/loan movement against their name, and their loan
/// history. Reached from tapping a member in the roster, or a transaction
/// in an activity feed.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.chamaId, required this.memberId});

  final String chamaId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(chamaMembersProvider(chamaId));
    final txnsAsync = ref.watch(memberTransactionsProvider((chamaId, memberId)));
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) {
          final matches = members.where((m) => m.id == memberId);
          final member = matches.isEmpty ? null : matches.first;
          if (member == null) {
            return const Center(child: Text('Member not found'));
          }

          final memberLoans = (loansAsync.value ?? const <Loan>[])
              .where((l) => l.memberId == memberId)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberTransactionsProvider((chamaId, memberId)));
              ref.invalidate(chamaLoansProvider(chamaId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
              children: [
                GlassContainer(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        child: Text(member.displayName.substring(0, 1).toUpperCase()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.displayName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              ChamaRole.label(member.role) +
                                  (member.hasAccount ? '' : ' · no app access'),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                            ),
                            if (member.phone != null && member.phone!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(member.phone!,
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      if (member.balance != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatMoney(member.balance!, currency: currency),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('balance',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 11)),
                          ],
                        ),
                    ],
                  ),
                ),
                if (chama != null && ChamaRole.isAdmin(chama.role) && chama.isActive) ...[
                  const SizedBox(height: 14),
                  if (!member.hasAccount)
                    _GiveLoginButton(chamaId: chamaId, member: member)
                  else
                    _ResetPasswordButton(chamaId: chamaId, member: member),
                ],
                // Pending requests come first and carry their own
                // decision buttons: a notification drops an admin here, and
                // having to hunt for the loan afterwards defeats the point.
                for (final loan in memberLoans.where((l) => l.status == 'pending')) ...[
                  const SizedBox(height: 14),
                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pending_actions_rounded,
                                size: 18, color: Colors.orange),
                            const SizedBox(width: 8),
                            const Text('Loan request awaiting your decision',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(formatMoney(loan.principal, currency: currency),
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        if (loan.purpose != null && loan.purpose!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(loan.purpose!,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13)),
                        ],
                        if (chama != null && ChamaRole.isAdmin(chama.role)) ...[
                          const SizedBox(height: 14),
                          LoanDecisionButtons(loan: loan),
                        ],
                      ],
                    ),
                  ),
                ],
                if (memberLoans.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Loans', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final loan in memberLoans)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/chamas/$chamaId/loans/${loan.id}'),
                        title: Text(formatMoney(loan.principal, currency: currency)),
                        subtitle: Text(
                            loan.status == 'rejected' && loan.rejectionReason != null
                                ? 'REJECTED — ${loan.rejectionReason}'
                                : loan.status.toUpperCase(),
                            style: const TextStyle(fontSize: 11)),
                        trailing: loan.status == 'active'
                            ? Text('owes ${formatMoney(loan.outstanding, currency: currency)}',
                                style: const TextStyle(fontSize: 12))
                            : null,
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                const Text('History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                txnsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Could not load history: $e'),
                  data: (txns) {
                    if (txns.isEmpty) {
                      return Text('No activity yet', style: TextStyle(color: Colors.grey.shade600));
                    }
                    return Column(children: [for (final t in txns) _HistoryTile(t, currency)]);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Turns a chairperson-managed member into one who can sign in themselves.
/// The temporary password comes back exactly once — it is never stored
/// anywhere readable, so if the chairperson loses it before passing it on,
/// the only route is to reset it again.
class _GiveLoginButton extends ConsumerStatefulWidget {
  const _GiveLoginButton({required this.chamaId, required this.member});

  final String chamaId;
  final ChamaMember member;

  @override
  ConsumerState<_GiveLoginButton> createState() => _GiveLoginButtonState();
}

class _GiveLoginButtonState extends ConsumerState<_GiveLoginButton> {
  bool _busy = false;

  Future<void> _start() async {
    final phoneCtrl = TextEditingController(text: widget.member.phone ?? '');
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give this member a login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.member.displayName} will sign in with their phone number and a '
              'temporary password you give them. They must change it straight away.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '07XX XXX XXX',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, phoneCtrl.text),
            child: const Text('Create login'),
          ),
        ],
      ),
    );

    if (phone == null || !PhoneIdentity.looksLikePhone(phone)) {
      if (phone != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid phone number')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref.read(chamaRepositoryProvider).createMemberLogin(
            chamaId: widget.chamaId,
            memberId: widget.member.id,
            phone: phone,
          );
      ref.invalidate(chamaMembersProvider(widget.chamaId));
      if (mounted) await _showCredentials(result.phone, result.temporaryPassword);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCredentials(String phone, String tempPassword) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Login created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Give these to ${widget.member.displayName}. '
                'The password is shown only once.'),
            const SizedBox(height: 16),
            _CredentialRow(label: 'Phone', value: '+$phone'),
            const SizedBox(height: 8),
            _CredentialRow(label: 'Temporary password', value: tempPassword),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _start,
      icon: _busy
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.key_outlined),
      label: const Text('Give this member a login'),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          SelectableText(value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.txn, this.currency);

  final ChamaTransaction txn;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.type == 'contribution' || txn.type == 'loan_disbursement';
    final icon = switch (txn.type) {
      'contribution' => Icons.savings_rounded,
      'loan_disbursement' => Icons.call_made_rounded,
      'loan_repayment' => Icons.call_received_rounded,
      'penalty' => Icons.warning_amber_rounded,
      _ => Icons.swap_horiz_rounded,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isCredit ? Colors.green : Colors.orange).withValues(alpha: 0.15),
          child: Icon(icon, color: isCredit ? Colors.green : Colors.orange, size: 20),
        ),
        title: Text(txn.type.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        subtitle: Text('${txn.createdAt.toLocal()}'.split(' ').first,
            style: const TextStyle(fontSize: 11.5)),
        trailing: Text(
          '${isCredit ? '+' : '-'}${formatMoney(txn.amount, currency: currency)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isCredit ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        ),
      ),
    );
  }
}


/// Reissues a member's password when they've forgotten it. Same one-shot
/// disclosure as handing out the first one: the chairperson reads it out,
/// and it stops working the moment the member sets their own.
class _ResetPasswordButton extends ConsumerStatefulWidget {
  const _ResetPasswordButton({required this.chamaId, required this.member});

  final String chamaId;
  final ChamaMember member;

  @override
  ConsumerState<_ResetPasswordButton> createState() => _ResetPasswordButtonState();
}

class _ResetPasswordButtonState extends ConsumerState<_ResetPasswordButton> {
  bool _busy = false;

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password?'),
        content: Text(
          '${widget.member.displayName} will be given a new temporary password. '
          'Their current one stops working immediately.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(chamaRepositoryProvider).resetMemberPassword(
            chamaId: widget.chamaId,
            memberId: widget.member.id,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('New password ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Give this to ${result.memberName}. '
                  'It is shown only once, and they must change it when they sign in.'),
              const SizedBox(height: 16),
              if ((widget.member.phone ?? '').isNotEmpty) ...[
                _CredentialRow(label: 'Phone', value: '+${widget.member.phone}'),
                const SizedBox(height: 8),
              ],
              _CredentialRow(
                  label: 'Temporary password', value: result.temporaryPassword),
            ],
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _reset,
      icon: _busy
          ? const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.lock_reset_rounded),
      label: const Text('Reset password'),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
    );
  }
}

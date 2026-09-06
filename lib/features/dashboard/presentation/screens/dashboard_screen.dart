import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/privacy_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chama/domain/models/chama.dart';
import '../../../chama/domain/models/chama_transaction.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../../notifications/presentation/providers/notifications_providers.dart';
import '../../../reports/presentation/widgets/chama_report_section.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final chamasAsync = ref.watch(myChamasProvider);
    final unread = ref.watch(unreadNotificationsCountProvider);

    final firstName = ((user?.userMetadata?['full_name'] as String?) ??
            user?.email ??
            'there')
        .split(' ')
        .first;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 72,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.55),
                ),
              ),
            ),
            title: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  child: Text(
                    firstName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_greeting(),
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                      Text(firstName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded),
                      onPressed: () => context.push('/notifications'),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text('$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: chamasAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e'),
              ),
              data: (chamas) {
                if (chamas.isEmpty) return const _NewUserOnboarding();
                final pending = chamas.where((c) => c.isPending).toList();
                if (pending.length == chamas.length) {
                  return _AwaitingApproval(chama: pending.first);
                }
                return _ActiveHome(chamas: chamas.where((c) => c.isActive).toList());
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A brand-new account with no chama yet. Joining an existing one someone
/// invited them to is the common case, so it's the primary action; creating
/// their own chama is the secondary path.
class _NewUserOnboarding extends StatelessWidget {
  const _NewUserOnboarding();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, kShellBottomInset),
      child: GlassContainer(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
              ),
              child: Icon(Icons.groups_rounded,
                  size: 34, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 18),
            const Text('Welcome to Chama360',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'You\'re not part of a chama yet. Join one with the invite code from '
              'your chairperson.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/chamas/join'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Join a chama'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Registered but not yet approved. Nothing can be recorded yet, so there's
/// nothing to show but the state of the request itself — saying so plainly
/// beats an empty dashboard that looks broken.
class _AwaitingApproval extends StatelessWidget {
  const _AwaitingApproval({required this.chama});

  final Chama chama;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, kShellBottomInset),
      child: GlassContainer(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: 0.14),
              ),
              child: const Icon(Icons.hourglass_top_rounded, size: 34, color: Colors.orange),
            ),
            const SizedBox(height: 18),
            Text(chama.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Your registration is with us for review. Once it\'s approved you\'ll be '
              'able to add members and start recording contributions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Awaiting approval',
                  style: TextStyle(
                      color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Existing member(s): the balance overview plus a real activity feed.
/// Creating/joining another chama lives on the Chamas tab from here on —
/// this screen is about what's happening, not account setup.
class _ActiveHome extends ConsumerWidget {
  const _ActiveHome({required this.chamas});

  final List<Chama> chamas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final balanceVisible = ref.watch(balanceVisibleProvider);
    final total = chamas.fold<double>(0, (sum, c) => sum + c.balance);
    final activityAsync = ref.watch(recentActivityProvider);
    final chamaNames = {for (final c in chamas) c.id: c.name};

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, kShellBottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isOnline) ...[
            const _OfflinePill(),
            const SizedBox(height: 12),
          ],
          _HeroBalanceCard(
            total: total,
            chamaCount: chamas.length,
            visible: balanceVisible,
            onToggleVisible: () =>
                ref.read(balanceVisibleProvider.notifier).state = !balanceVisible,
          ),
          const SizedBox(height: 26),
          Text('Recent activity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          activityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load activity: $e'),
            data: (activity) {
              if (activity.isEmpty) {
                return GlassContainer(
                  child: Text('No activity yet — record a contribution to get started.',
                      style: TextStyle(color: Colors.grey.shade600)),
                );
              }
              return Column(
                children: [
                  for (final txn in activity)
                    _ActivityTile(
                      txn: txn,
                      chamaName: chamaNames[txn.chamaId] ?? 'Chama',
                      visible: balanceVisible,
                      onTap: () => txn.memberId == null
                          ? context.push('/chamas/${txn.chamaId}')
                          : context.push('/chamas/${txn.chamaId}/members/${txn.memberId}'),
                    ),
                ],
              );
            },
          ),
          if (chamas.length > 1) ...[
            const SizedBox(height: 26),
            Text('Your chamas',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _ChamaCarousel(chamas: chamas, visible: balanceVisible),
          ],
          if (chamas.isNotEmpty) ...[
            const SizedBox(height: 26),
            ChamaReportSection(chamaId: chamas.first.id, visible: balanceVisible),
          ],
        ],
      ),
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text('Offline — showing cached data',
                style: TextStyle(color: Colors.orange, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _HeroBalanceCard extends StatelessWidget {
  const _HeroBalanceCard({
    required this.total,
    required this.chamaCount,
    required this.visible,
    required this.onToggleVisible,
  });

  final double total;
  final int chamaCount;
  final bool visible;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [AppColors.seedDark, const Color(0xFF16281C)]
                    : [AppColors.seed, AppColors.seedDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.seedDark.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total across $chamaCount chama${chamaCount == 1 ? '' : 's'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onToggleVisible,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  visible ? formatMoney(total) : '••••••',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(Icons.savings_rounded,
                size: 120, color: Colors.white.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.txn,
    required this.chamaName,
    required this.visible,
    required this.onTap,
  });

  final ChamaTransaction txn;
  final String chamaName;
  final bool visible;
  final VoidCallback onTap;

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: 16,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: (isCredit ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                child: Icon(icon, size: 18, color: isCredit ? Colors.green : Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(txn.type.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      txn.memberName == null ? chamaName : '${txn.memberName} · $chamaName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    visible ? '${isCredit ? '+' : '-'}${formatMoney(txn.amount)}' : '••••',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCredit ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                  ),
                  Text(
                    '${txn.createdAt.toLocal()}'.split(' ').first,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChamaCarousel extends StatelessWidget {
  const _ChamaCarousel({required this.chamas, required this.visible});

  final List<Chama> chamas;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chamas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final chama = chamas[i];
          return InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.push('/chamas/${chama.id}'),
            child: SizedBox(
              width: 240,
              child: GlassContainer(
                borderRadius: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.groups_rounded,
                              size: 18, color: Theme.of(context).colorScheme.primary),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(chama.role,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(chama.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        visible
                            ? formatMoney(chama.balance, currency: chama.currency)
                            : '••••••',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

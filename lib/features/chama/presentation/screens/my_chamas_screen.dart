import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/connectivity_service.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/chama.dart';
import '../providers/chama_providers.dart';

class MyChamasScreen extends ConsumerWidget {
  const MyChamasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chamasAsync = ref.watch(myChamasProvider);
    final isOnline = ref.watch(isOnlineProvider);
    // One chama per person for now — once they have one, hide the
    // create/join actions instead of letting them tap into a server error.
    final hasChama = chamasAsync.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Chamas'),
        // Chamas aren't created from inside the app any more — they're
        // registered publicly and approved. Joining an existing one with
        // an invite code is all that's left here.
        actions: hasChama
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  tooltip: 'Join a chama',
                  onPressed: () => context.push('/chamas/join'),
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myChamasProvider),
        child: chamasAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Could not load chamas: $e')),
            ],
          ),
          data: (chamas) {
            if (chamas.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, kShellBottomInset),
                children: [
                  Icon(Icons.groups_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No chamas yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Join one with an invite code from your chairperson.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/chamas/join'),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Join a chama'),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, kShellBottomInset),
              children: [
                if (!isOnline) const _OfflineBanner(),
                for (final chama in chamas) _ChamaCard(chama: chama),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
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

class _ChamaCard extends StatelessWidget {
  const _ChamaCard({required this.chama});

  final Chama chama;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/chamas/${chama.id}'),
        child: GlassContainer(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.groups_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chama.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'You: ${chama.role[0].toUpperCase()}${chama.role.substring(1)}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(chama.balance, currency: chama.currency),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text('balance',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/biometric_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';

/// Offered once, immediately after someone sets their password or PIN —
/// the moment they're most receptive, having just typed a credential they'd
/// rather not type again. Skipping is a first-class option: biometrics can
/// be turned on later from Profile, and a member on a shared or basic
/// handset may not have them at all.
class BiometricSetupScreen extends ConsumerStatefulWidget {
  const BiometricSetupScreen({super.key});

  @override
  ConsumerState<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends ConsumerState<BiometricSetupScreen> {
  bool _working = false;

  void _finish() => ref.read(offerBiometricSetupProvider.notifier).state = false;

  Future<void> _enable() async {
    setState(() => _working = true);
    // setEnabled prompts for a real fingerprint/face first — if that's
    // declined, nothing is turned on and they stay on this screen.
    await ref.read(biometricEnabledProvider.notifier).setEnabled(true);
    if (!mounted) return;
    setState(() => _working = false);

    final enabled = ref.read(biometricEnabledProvider).value ?? false;
    if (enabled) {
      ref.read(isAppUnlockedProvider.notifier).state = true;
      _finish();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not set up — you can turn this on later in Profile.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _FingerprintMark(),
                  const SizedBox(height: 28),
                  const Text(
                    'Skip the password next time',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock Chama360 with your fingerprint or face instead of typing '
                    'your password every time you open it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, height: 1.5, fontSize: 14.5),
                  ),
                  const SizedBox(height: 26),
                  GlassContainer(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: const [
                        _Reassurance(
                          icon: Icons.phonelink_lock_rounded,
                          text: 'Your fingerprint never leaves your phone',
                        ),
                        SizedBox(height: 14),
                        _Reassurance(
                          icon: Icons.password_rounded,
                          text: 'Your password still works whenever you need it',
                        ),
                        SizedBox(height: 14),
                        _Reassurance(
                          icon: Icons.tune_rounded,
                          text: 'Turn it off any time from your profile',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _working ? null : _enable,
                      icon: _working
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.fingerprint_rounded),
                      label: const Text('Turn on biometric unlock'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _working ? null : _finish,
                    child: Text('Not now',
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A fingerprint sitting in concentric haloes — drawn rather than shipped
/// as an image so it stays crisp at any density and recolours with the
/// theme instead of needing a light and a dark asset.
class _FingerprintMark extends StatelessWidget {
  const _FingerprintMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _halo(150, 0.06),
          _halo(118, 0.10),
          _halo(88, 0.16),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.seed, AppColors.seedDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.seedDark.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.fingerprint_rounded, size: 46, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _halo(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.seed.withValues(alpha: alpha),
        ),
      );
}

class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
        ),
      ],
    );
  }
}

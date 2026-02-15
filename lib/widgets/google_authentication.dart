import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/services/auth_service.dart';
import 'package:link_up/styles/styles.dart';

class GoogleAuthentication extends ConsumerStatefulWidget {
  const GoogleAuthentication({super.key});

  @override
  ConsumerState<GoogleAuthentication> createState() =>
      _GoogleAuthenticationState();
}

class _GoogleAuthenticationState extends ConsumerState<GoogleAuthentication> {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _handleGoogleSignIn(),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Consumer(
        builder: (context, ref, _) {
          return ref.watch(isLoadingProvider)
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: AppColors.primaryBlue,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo/google_logo.webp',
                      height: 24,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.account_circle_outlined,
                          size: 24,
                          color: AppColors.textSecondary,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    const Text('Continue with Google'),
                  ],
                );
        },
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    if (!mounted) return;
    // Set loading to true using local state
    ref.read(isLoadingProvider.notifier).state = true;

    try {
      final userCredential = await GoogleSignInService.signInWithGoogle();

      if (!mounted) return;

      if (userCredential != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LandingPage()),
        );
      } else {
        // User cancelled sign-in
        if (!mounted) return;
        ref.read(isLoadingProvider.notifier).state = false;
      }
    } catch (e) {
      if (!mounted) return;

      ref.read(isLoadingProvider.notifier).state = false;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request not completed \n$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

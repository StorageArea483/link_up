import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:link_up/styles/styles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppErrorWidget extends ConsumerWidget {
  final ProviderBase provider;
  const AppErrorWidget({super.key, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'An error occurred please retry',
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.white,
              ),
              onPressed: () => ref.invalidate(provider),
              label: const Text("Retry"),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

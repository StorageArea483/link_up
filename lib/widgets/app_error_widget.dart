import 'package:flutter/material.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/styles/styles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppErrorWidget extends ConsumerWidget {
  const AppErrorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 32, color: Colors.red),
                const SizedBox(height: 12),
                const Text(
                  'An unexpected error occurred',
                  style: AppTextStyles.subtitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: TextButton(
                    onPressed: () {
                      ref.invalidate(userContactProvider);
                    },
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

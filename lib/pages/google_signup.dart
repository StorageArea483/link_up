import 'package:flutter/material.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/google_authentication.dart';

class GoogleSignup extends StatelessWidget {
  const GoogleSignup({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo/app_logo.webp',
                  height: 80,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.hub_outlined,
                      size: 80,
                      color: AppColors.primaryBlue,
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text('LinkUp', style: AppTextStyles.title),
                const SizedBox(height: 8),
                const Text(
                  'Connect instantly with anyone at anytime',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: 60),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.textSecondary),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    image: const DecorationImage(
                      image: AssetImage(
                        'assets/images/project_images/image_1.webp',
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                  width: double.infinity,
                  height: size.height * 0.40,
                ),
                const SizedBox(height: 60),
                const SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: GoogleAuthentication(),
                ),
                const SizedBox(height: 24),
                Text.rich(
                  TextSpan(
                    text: 'By continuing you agree to our ',
                    style: const TextStyle(
                      color: AppColors.textFooter,
                      fontSize: 12,
                    ),
                    children: [
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => _showTermsDialog(context),
                          child: const Text(
                            'Terms',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.underline,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' & '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => _showPrivacyDialog(context),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.underline,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            'Welcome to LinkUp!\n\n'
            '1. By using our app, you agree to these terms.\n\n'
            '2. You must be 18 years or older to use this service.\n\n'
            '3. We reserve the right to modify these terms at any time.\n\n'
            '4. You are responsible for maintaining the security of your account.\n\n'
            '5. We are not liable for any damages arising from your use of the app.\n\n'
            '6. These terms are governed by applicable laws.\n\n'
            'For full terms, please visit our website.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Agree',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'Your Privacy Matters\n\n'
            '1. We collect information you provide when creating an account.\n\n'
            '2. We use your data to provide and improve our services.\n\n'
            '3. We do not sell your personal information to third parties.\n\n'
            '4. We use cookies to enhance your experience.\n\n'
            '5. You can request deletion of your data at any time.\n\n'
            '6. We implement security measures to protect your information.\n\n'
            '7. This policy may be updated periodically.\n\n'
            'For complete privacy policy, visit our website.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Agree',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/user_profile.dart';
import 'package:link_up/providers/random_num_provider.dart';
import 'package:link_up/providers/user_profile_provider.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/widgets/check_connection.dart';

class EditUserInfo extends ConsumerStatefulWidget {
  const EditUserInfo({super.key});

  @override
  ConsumerState<EditUserInfo> createState() => _EditUserInfoState();
}

class _EditUserInfoState extends ConsumerState<EditUserInfo> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      ref.read(isLoadingProvider.notifier).state = true;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        if (!mounted) return;

        if (userDoc.exists) {
          // ✅ Only include fields that the user actually filled in
          final Map<String, dynamic> updatedFields = {};

          if (_nameController.text.trim().isNotEmpty) {
            updatedFields['name'] = _nameController.text.trim();
          }
          if (_numberController.text.trim().isNotEmpty) {
            updatedFields['user phone number'] = _numberController.text.trim();
          }
          if (_emailController.text.trim().isNotEmpty) {
            updatedFields['email'] = _emailController.text.trim();
          }

          // ✅ Nothing was filled in
          if (updatedFields.isEmpty) {
            ref.read(isLoadingProvider.notifier).state = false;
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please fill in at least one field to update'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          // ✅ update() merges with existing doc, won't delete other fields
          await userDoc.reference.update(updatedFields);

          ref.read(isLoadingProvider.notifier).state = false;
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully'),
              backgroundColor: Colors.green,
            ),
          );

          _numberController.clear();
          _nameController.clear();
          _emailController.clear();

          ref.invalidate(currentUserInfoProvider);
          ref.invalidate(userPhoneNumberProvider);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const CheckConnection(child: UserProfile()),
            ),
          );
        } else {
          if (!mounted) return;
          ref.read(isLoadingProvider.notifier).state = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update profile'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred, please try again'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const CheckConnection(child: UserProfile()),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 600;
              return AppBar(
                backgroundColor: AppColors.background,
                elevation: 0,
                automaticallyImplyLeading: false,
                flexibleSpace: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 640.0 : double.infinity,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CheckConnection(
                                            child: UserProfile(),
                                          ),
                                    ),
                                  ),
                            ),
                            Expanded(
                              child: Text(
                                'Edit Contact Info',
                                style: AppTextStyles.title.copyWith(
                                  fontSize: 20,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            // Invisible spacer to keep title truly centered
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 600;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet ? 640.0 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 30,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFieldLabel('LinkUp Number'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _numberController,
                            keyboardType: TextInputType.phone,
                            style: AppTextStyles.subtitle.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: _buildInputDecoration(
                              hint: 'Enter 9 digit number',
                              icon: Icons.copy_all_rounded,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null; // ✅ optional
                              }
                              if (!RegExp(r'^\d{9}$').hasMatch(value)) {
                                return 'Number must be exactly 9 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildFieldLabel('Contact Name'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            style: AppTextStyles.subtitle.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: _buildInputDecoration(
                              hint: 'Enter your new name',
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildFieldLabel('Email Address'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailController,
                            style: AppTextStyles.subtitle.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: _buildInputDecoration(
                              hint: 'Enter your new email',
                              icon: Icons.email_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null; // ✅ optional
                              }
                              // ✅ Regex check for valid email format
                              final emailRegex = RegExp(
                                r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$',
                              );
                              if (!emailRegex.hasMatch(value.trim())) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 48),
                          ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: AppColors.white,
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Consumer(
                              builder: (context, ref, _) {
                                return ref.watch(isLoadingProvider)
                                    ? const CircularProgressIndicator(
                                        color: AppColors.white,
                                      )
                                    : const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Text _buildFieldLabel(String label) {
    return Text(
      label,
      style: AppTextStyles.subtitle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 22),
      hintStyle: AppTextStyles.footer.copyWith(fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}

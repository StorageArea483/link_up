import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/styles/styles.dart';

class PhoneNumber extends ConsumerStatefulWidget {
  const PhoneNumber({super.key});

  @override
  ConsumerState<PhoneNumber> createState() => _PhoneNumberState();
}

class _PhoneNumberState extends ConsumerState<PhoneNumber> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      ref.read(isLoadingProvider.notifier).state = true;
      final phoneNumber = _numberController.text;
      final contactName = _nameController.text;
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'User not logged in',
              style: TextStyle(backgroundColor: Colors.red),
            ),
          ),
        );
        ref.read(isLoadingProvider.notifier).state = false;
        return;
      }

      try {
        // Query Firestore to see if a user exists with this phone number
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('user phone number', isEqualTo: phoneNumber)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final foundUserDoc = querySnapshot.docs.first;
          final foundUserId = foundUserDoc.id;
          final foundUserData = foundUserDoc.data();

          // Check if trying to add yourself
          if (foundUserId == currentUser.uid) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You cannot add yourself as a contact'),
                backgroundColor: Colors.orange,
              ),
            );
            ref.read(isLoadingProvider.notifier).state = false;
            return;
          }

          // Check if contact already exists
          final existingContact = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('contacts')
              .doc(foundUserId)
              .get();

          if (existingContact.exists) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This contact already exists'),
                backgroundColor: Colors.orange,
              ),
            );
            ref.read(isLoadingProvider.notifier).state = false;
            return;
          }

          // Add to current user's contacts
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('contacts')
              .doc(foundUserId)
              .set({
                'uid': foundUserId,
                'contact name': contactName,
                'phone number': phoneNumber,
                'photoURL': foundUserData['photoURL'] ?? '',
              });

          // Also add current user to scanned user's contacts (mutual connection)
          final currentUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

          final currentUserData = currentUserDoc.data()!;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(foundUserId)
              .collection('contacts')
              .doc(currentUser.uid)
              .set({
                'uid': currentUser.uid,
                'contact name': currentUserData['name'] ?? 'Unknown',
                'phone number': currentUserData['user phone number'] ?? '',
                'photoURL': currentUserData['photoURL'] ?? '',
              });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact Added Successfully'),
              backgroundColor: Colors.green,
            ),
          );
          ref.read(isLoadingProvider.notifier).state = false;

          // Clear fields and go back
          _numberController.clear();
          _nameController.clear();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LandingPage()),
          );
        } else {
          // User does not exist
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No user found with this LinkUp number'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred please try again'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LandingPage()),
          ),
        ),
        backgroundColor: AppColors.background,
        title: Text(
          'Add New Contact',
          style: AppTextStyles.title.copyWith(fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
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
                    if (value == null || value.isEmpty) {
                      return 'Number cannot be left empty';
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
                    hint: 'Enter contact name',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Contact Name cannot be left empty';
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
                              'Send Request',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/providers/random_num_provider.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/add_new_contact/qr_code.dart';
import 'package:link_up/widgets/add_new_contact/qr_scanner.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/add_new_contact/phone_number.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

class LandingPage extends ConsumerWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phoneAsync = ref.watch(userPhoneNumberProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('LinkUp', style: AppTextStyles.title),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: phoneAsync.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        error: (error, stack) =>
            AppErrorWidget(provider: userPhoneNumberProvider),
        data: (randomNumber) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 10.0),
                  child: Text('Your Number', style: AppTextStyles.subtitle),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 25,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        randomNumber,
                        style: AppTextStyles.title.copyWith(fontSize: 28),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: randomNumber));
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                const Text('Recent Contacts', style: AppTextStyles.subtitle),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Add New Button
                        Column(
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  _addNewContact(context, randomNumber),
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: AppColors.primaryBlue
                                    .withOpacity(0.1),
                                child: Container(
                                  height: 48,
                                  width: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.primaryBlue,
                                        Color(0xFF8ECAFF),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Add New',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        // Contacts List
                        Consumer(
                          builder: (context, ref, _) {
                            return ref
                                .watch(userContactProvider)
                                .when(
                                  skipLoadingOnRefresh: false,
                                  skipLoadingOnReload: false,
                                  data: (contacts) {
                                    if (contacts.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return SizedBox(
                                      height: 90,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        scrollDirection: Axis.horizontal,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: contacts.length,
                                        itemBuilder: (context, index) {
                                          final contact = contacts[index];
                                          return Column(
                                            children: [
                                              Stack(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 32,
                                                    backgroundColor: AppColors
                                                        .primaryBlue
                                                        .withOpacity(0.2),
                                                    child: ClipOval(
                                                      child: Image.network(
                                                        contact.profilePicture,
                                                        width: 64,
                                                        height: 64,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) {
                                                              return const Icon(
                                                                Icons
                                                                    .person_2_outlined,
                                                                color: AppColors
                                                                    .primaryBlue,
                                                                size: 32,
                                                              );
                                                            },
                                                        loadingBuilder:
                                                            (
                                                              context,
                                                              child,
                                                              loadingProgress,
                                                            ) {
                                                              if (loadingProgress ==
                                                                  null) {
                                                                return child;
                                                              }
                                                              return const CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              );
                                                            },
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    bottom: 0,
                                                    right: 0,
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        _editUserDetails(
                                                          context,
                                                          ref,
                                                          contact,
                                                        );
                                                      },
                                                      child: const CircleAvatar(
                                                        radius: 11,
                                                        backgroundColor:
                                                            AppColors.white,

                                                        child: CircleAvatar(
                                                          radius: 9,
                                                          backgroundColor:
                                                              AppColors
                                                                  .primaryBlue,
                                                          child: Icon(
                                                            Icons.edit,
                                                            color: Colors.white,
                                                            size: 11,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                width: 64,
                                                child: Text(
                                                  contact.name,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    );
                                  },
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                  error: (err, stack) => AppErrorWidget(
                                    provider: userContactProvider,
                                  ),
                                );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                const Text('Recent Calls', style: AppTextStyles.subtitle),
                const SizedBox(height: 10),
                const Text('No calls yet', style: AppTextStyles.footer),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavbar(currentIndex: 0),
    );
  }

  void _editUserDetails(
    BuildContext context,
    WidgetRef ref,
    UserContacts contact,
  ) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Contact', style: AppTextStyles.subtitle),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Text(
                'Contact Name',
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter new name',
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.primaryBlue,
                    size: 22,
                  ),
                  hintStyle: AppTextStyles.footer.copyWith(fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () async {
                      ref.read(isLoadingProvider.notifier).state = true;
                      final newName = nameController.text.trim();
                      if (newName.isEmpty) return;

                      final currentUser = FirebaseAuth.instance.currentUser;
                      if (currentUser == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('User not logged in'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                        ref.read(isLoadingProvider.notifier).state = false;
                        return;
                      }

                      try {
                        // Check if the contact user exists in the database
                        final contactUserDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(contact.uid)
                            .get();

                        if (contactUserDoc.exists) {
                          // Update the contact name in the current user's contacts subcollection
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUser.uid)
                              .collection('contacts')
                              .doc(contact.uid)
                              .update({'contact name': newName});

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Contact updated successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            ref.read(isLoadingProvider.notifier).state = false;
                            if (context.mounted) Navigator.pop(context);
                            ref.invalidate(userContactProvider);
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Contact user does not exist'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            ref.read(isLoadingProvider.notifier).state = false;
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error updating contact'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          ref.read(isLoadingProvider.notifier).state = false;
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: ref.watch(isLoadingProvider)
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryBlue,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addNewContact(BuildContext context, String phoneNumber) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Contact', style: AppTextStyles.subtitle),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              _buildAddOption(
                icon: Icons.call,
                label: 'By LinkUp number',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const PhoneNumber(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildAddOption(
                icon: Icons.link_rounded,
                label: 'By link',
                onTap: () async {
                  Navigator.pop(context);
                  await Share.share(
                    'Join me on LinkUp! My LinkUp number is: $phoneNumber',
                    subject: 'My LinkUp Number',
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildAddOption(
                icon: Icons.qr_code_rounded,
                label: 'Show my QR code',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const QrCode()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildAddOption(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan QR code',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const QrScanner()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.background.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryBlue.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryBlue, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.subtitle.copyWith(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textFooter,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

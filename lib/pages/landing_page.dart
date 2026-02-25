import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/incoming_call_screen.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/providers/random_num_provider.dart';
import 'package:link_up/services/call_service.dart';
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
import 'package:link_up/widgets/check_connection.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  StreamSubscription? _incomingCallSub;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForIncomingCalls();
    });
  }

  void _listenForIncomingCalls() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _incomingCallSub = CallService.subscribeToIncomingCalls(currentUser.uid, (
      response,
    ) {
      if (!mounted) return;

      final isOnline = ref.read(networkConnectivityProvider).value ?? true;
      if (!isOnline) {
        return;
      }
      final payload =
          response.payload; // ringing call data extracted from appwrite
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CheckConnection(
            child: IncomingCallScreen(
              callId: payload['\$id'] as String,
              callerName: payload['callerName'] as String? ?? 'Unknown',
              callerId: payload['callerId'] as String,
              offer: payload['offer'] as String,
              isVideo: payload['isVideo'] as bool? ?? true,
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phoneAsync = ref.watch(userPhoneNumberProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: Text(
          'LinkUp',
          style: AppTextStyles.title.copyWith(fontSize: 24),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Container(
              height: 40,
              width: 40,
              decoration: const BoxDecoration(
                color: AppColors.iconBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textPrimary,
              ),
            ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = (constraints.maxWidth >= 600)
                  ? 32.0
                  : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      'YOUR NUMBER',
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              randomNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.title.copyWith(fontSize: 30),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: randomNumber),
                              );
                            },
                            child: Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                color: AppColors.iconBackground,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.copy_rounded,
                                color: AppColors.linkBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'RECENT CONTACTS',
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 132,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Consumer(
                        builder: (context, ref, _) {
                          return ref
                              .watch(userContactProvider)
                              .when(
                                skipLoadingOnRefresh: false,
                                skipLoadingOnReload: false,
                                data: (contacts) {
                                  return ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    itemCount: contacts.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return Column(
                                          children: [
                                            GestureDetector(
                                              onTap: () => _addNewContact(
                                                context,
                                                randomNumber,
                                              ),
                                              child: Container(
                                                height: 64,
                                                width: 64,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppColors.primaryBlue
                                                      .withOpacity(0.06),
                                                  border: Border.all(
                                                    color: AppColors.primaryBlue
                                                        .withOpacity(0.35),
                                                    width: 2,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.add_rounded,
                                                  color: AppColors.linkBlue,
                                                  size: 30,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const SizedBox(
                                              width: 72,
                                              child: Text(
                                                'Add New',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }

                                      final contact = contacts[index - 1];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16,
                                        ),
                                        child: Column(
                                          children: [
                                            Stack(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    2,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: AppColors
                                                            .primaryBlue,
                                                      ),
                                                  child: CircleAvatar(
                                                    radius: 30,
                                                    backgroundColor:
                                                        AppColors.surface,
                                                    child: ClipOval(
                                                      child: Image.network(
                                                        contact.profilePicture,
                                                        width: 60,
                                                        height: 60,
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
                                                                size: 30,
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
                                                              return const Center(
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              );
                                                            },
                                                      ),
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
                                                            AppColors.linkBlue,
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
                                              width: 72,
                                              child: Text(
                                                contact.name,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
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
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'RECENT CALLS',
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              color: AppColors.divider.withOpacity(0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_outlined,
                              color: AppColors.textFooter,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No calls yet',
                            style: AppTextStyles.subtitle.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const SizedBox(
                            width: 220,
                            child: Text(
                              'Calls you make or receive will appear here.',
                              style: AppTextStyles.body,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              'Start a call',
                              style: AppTextStyles.link,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
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
        backgroundColor: AppColors.surface,
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
                    color: AppColors.linkBlue,
                    size: 22,
                  ),
                  hintStyle: AppTextStyles.footer.copyWith(fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.linkBlue),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.linkBlue,
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
                      if (!context.mounted) return;
                      ref.read(isLoadingProvider.notifier).state = true;
                      final newName = nameController.text.trim();
                      if (newName.isEmpty) {
                        if (!context.mounted) return;
                        ref.read(isLoadingProvider.notifier).state = false;
                        return;
                      }

                      final currentUser = FirebaseAuth.instance.currentUser;
                      if (currentUser == null) {
                        if (!context.mounted) return;
                        ref.read(isLoadingProvider.notifier).state = false;
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('User not logged in'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      try {
                        // Check if the contact user exists in the database
                        final contactUserDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(contact.uid)
                            .get();

                        if (!context.mounted) return;

                        if (contactUserDoc.exists) {
                          // Update the contact name in the current user's contacts subcollection
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUser.uid)
                              .collection('contacts')
                              .doc(contact.uid)
                              .update({'contact name': newName});

                          if (!context.mounted) return;
                          ref.read(isLoadingProvider.notifier).state = false;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Contact updated successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ref.invalidate(userContactProvider);
                        } else {
                          if (!context.mounted) return;
                          ref.read(isLoadingProvider.notifier).state = false;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Contact user does not exist'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ref.read(isLoadingProvider.notifier).state = false;
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error updating contact'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.linkBlue,
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
        backgroundColor: AppColors.surface,
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
                      builder: (context) =>
                          const CheckConnection(child: PhoneNumber()),
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
                    MaterialPageRoute(
                      builder: (context) =>
                          const CheckConnection(child: QrCode()),
                    ),
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
                    MaterialPageRoute(
                      builder: (context) =>
                          const CheckConnection(child: QrScanner()),
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
          color: AppColors.iconBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.linkBlue.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.linkBlue, size: 22),
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
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

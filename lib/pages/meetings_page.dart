import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/call_screen.dart';
import 'package:link_up/pages/incoming_call_screen.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/meetings_caller_provider.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/check_connection.dart';

class MeetingsPage extends ConsumerStatefulWidget {
  const MeetingsPage({super.key});

  @override
  ConsumerState<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends ConsumerState<MeetingsPage> {
  StreamSubscription? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
      _listenForIncomingCalls();
    });
  }

  void _initialize() {
    if (mounted) {
      ref.read(navigationProvider.notifier).state = 'null';
    }
  }

  void _listenForIncomingCalls() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _incomingCallSub = CallService.subscribeToIncomingCalls(currentUser.uid, (
      response,
    ) {
      if (!mounted) return;
      final payload =
          response.payload; // ringing call data extracted from appwrite
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => IncomingCallScreen(
            callId: payload['\$id'] as String,
            callerName: payload['callerName'] as String? ?? 'Unknown',
            callerId: payload['callerId'] as String,
            offer: payload['offer'] as String,
            isVideo: payload['isVideo'] as bool? ?? true,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const CheckConnection(child: LandingPage()),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('Meetings Page', style: AppTextStyles.title),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    const CheckConnection(child: LandingPage()),
              ),
            ),
            tooltip: 'Back to Landing Page',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final isChanged = ref.watch(
                    meetingsProvider.select((state) => state.isChanged),
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: TextField(
                      keyboardType: isChanged
                          ? TextInputType.text
                          : TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Search name or number...',
                        hintStyle: AppTextStyles.subtitle.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.primaryBlue,
                        ),
                        suffixIcon: IconButton(
                          icon: isChanged
                              ? const Icon(
                                  Icons.filter_list,
                                  color: AppColors.textPrimary,
                                )
                              : const Icon(
                                  Icons.filter_list_off,
                                  color: AppColors.textSecondary,
                                ),
                          onPressed: () => ref
                              .read(meetingsProvider.notifier)
                              .toggleChanged(),
                        ),
                        filled: true,
                        fillColor: AppColors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppColors.primaryBlue,
                            width: 2,
                          ),
                        ),
                      ),
                      cursorColor: AppColors.primaryBlue,
                      style: AppTextStyles.button.copyWith(fontSize: 16),
                      onChanged: (value) {
                        // Handle search input change
                        if (mounted) {
                          ref.read(meetingsProvider.notifier).search(value);
                        }
                      },
                    ),
                  );
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final contactsAsyncValue = ref.watch(userContactProvider);
                  final searchValue = ref.watch(
                    meetingsProvider.select((state) => state.value),
                  );
                  return contactsAsyncValue.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    data: (contacts) {
                      if (contacts.isEmpty && searchValue.isEmpty) {
                        return const SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: 600,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_2_outlined,
                                    size: 100,
                                    color: AppColors.textPrimary,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No registered contacts found.',
                                    style: AppTextStyles.subtitle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      if (searchValue.isNotEmpty) {
                        contacts = contacts.where((contact) {
                          final nameMatch = contact.name.toLowerCase().contains(
                            searchValue.toLowerCase(),
                          );
                          final phoneMatch = contact.phoneNumber.contains(
                            searchValue,
                          );
                          return nameMatch || phoneMatch;
                        }).toList();
                      }
                      return SingleChildScrollView(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            final contact = contacts[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 32,
                                  backgroundColor: AppColors.primaryBlue
                                      .withOpacity(0.2),
                                  child: ClipOval(
                                    child: Image.network(
                                      contact.profilePicture,
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.person_2_outlined,
                                              color: AppColors.primaryBlue,
                                              size: 32,
                                            );
                                          },
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                            if (loadingProgress == null) {
                                              return child;
                                            }
                                            return const CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.primaryBlue,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                                title: Text(
                                  contact.name,
                                  style: AppTextStyles.button.copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                subtitle: Text(
                                  contact.phoneNumber,
                                  style: AppTextStyles.subtitle,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.call_outlined,
                                        color: AppColors.primaryBlue,
                                        size: 28,
                                      ),
                                      onPressed: () {
                                        // Audio call
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => CallScreen(
                                              calleeId: contact.uid,
                                              calleeName: contact.name,
                                              calleeProfilePicture:
                                                  contact.profilePicture,
                                              isVideo: false,
                                              isCaller: true,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.video_call_outlined,
                                        color: AppColors.primaryBlue,
                                        size: 28,
                                      ),
                                      onPressed: () {
                                        // Video call
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => CallScreen(
                                              calleeId: contact.uid,
                                              calleeName: contact.name,
                                              calleeProfilePicture:
                                                  contact.profilePicture,
                                              isVideo: true,
                                              isCaller: true,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                    error: (err, stack) =>
                        AppErrorWidget(provider: userContactProvider),
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        bottomNavigationBar: const BottomNavbar(currentIndex: 1),
      ),
    );
  }
}

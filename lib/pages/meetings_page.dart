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
  final TextEditingController _searchController = TextEditingController();

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
    _searchController.dispose();
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
          title: Text(
            'Meetings Page',
            style: AppTextStyles.title.copyWith(fontSize: 20),
          ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = (constraints.maxWidth >= 600)
                  ? 32.0
                  : 20.0;

              return Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final isChanged = ref.watch(
                        meetingsProvider.select((state) => state.isChanged),
                      );

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          12,
                          horizontalPadding,
                          8,
                        ),
                        child: TextField(
                          controller: _searchController,
                          keyboardType: isChanged
                              ? TextInputType.text
                              : TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Search name or number...',
                            hintStyle: AppTextStyles.subtitle.copyWith(
                              color: AppColors.textFooter,
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppColors.textFooter,
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
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: AppColors.inputBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: AppColors.linkBlue,
                                width: 1.5,
                              ),
                            ),
                          ),
                          cursorColor: AppColors.linkBlue,
                          style: AppTextStyles.button.copyWith(fontSize: 16),
                          onChanged: (value) {
                            if (mounted) {
                              ref.read(meetingsProvider.notifier).search(value);
                            }
                          },
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final contactsAsyncValue = ref.watch(
                          userContactProvider,
                        );
                        final searchValue = ref.watch(
                          meetingsProvider.select((state) => state.value),
                        );

                        return contactsAsyncValue.when(
                          skipLoadingOnRefresh: false,
                          skipLoadingOnReload: false,
                          data: (contacts) {
                            var filteredContacts = contacts;

                            if (contacts.isEmpty && searchValue.isEmpty) {
                              return const SingleChildScrollView(
                                physics: AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: 600,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                              filteredContacts = contacts.where((contact) {
                                final nameMatch = contact.name
                                    .toLowerCase()
                                    .contains(searchValue.toLowerCase());
                                final phoneMatch = contact.phoneNumber.contains(
                                  searchValue,
                                );
                                return nameMatch || phoneMatch;
                              }).toList();
                            }

                            if (filteredContacts.isEmpty) {
                              return const SingleChildScrollView(
                                physics: AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: 600,
                                  child: Center(
                                    child: Text(
                                      'No contacts match your search.',
                                      style: AppTextStyles.subtitle,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                8,
                                horizontalPadding,
                                100,
                              ),
                              itemCount: filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = filteredContacts[index];
                                final hasProfilePicture = contact.profilePicture
                                    .trim()
                                    .isNotEmpty;

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
                                      child: hasProfilePicture
                                          ? ClipOval(
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
                                                        Icons.person_2_outlined,
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
                                                      return const Center(
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: AppColors
                                                                  .primaryBlue,
                                                            ),
                                                      );
                                                    },
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person_2_outlined,
                                              color: AppColors.primaryBlue,
                                              size: 32,
                                            ),
                                    ),
                                    title: Text(
                                      contact.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.button.copyWith(
                                        fontSize: 18,
                                      ),
                                    ),
                                    subtitle: Text(
                                      contact.phoneNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.subtitle,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ActionCircleButton(
                                          icon: Icons.call_rounded,
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    CallScreen(
                                                      calleeId: contact.uid,
                                                      calleeName: contact.name,
                                                      calleeProfilePicture:
                                                          contact
                                                              .profilePicture,
                                                      isVideo: false,
                                                      isCaller: true,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        _ActionCircleButton(
                                          icon: Icons.videocam_rounded,
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    CallScreen(
                                                      calleeId: contact.uid,
                                                      calleeName: contact.name,
                                                      calleeProfilePicture:
                                                          contact
                                                              .profilePicture,
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
                            );
                          },
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          error: (err, stack) =>
                              AppErrorWidget(provider: userContactProvider),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: AppColors.linkBlue,
          foregroundColor: AppColors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_rounded, size: 30),
        ),
        bottomNavigationBar: const BottomNavbar(currentIndex: 1),
      ),
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        height: 44,
        width: 44,
        decoration: const BoxDecoration(
          color: AppColors.iconBackground,
          shape: BoxShape.circle,
        ),
        child: Center(child: Icon(icon, color: AppColors.linkBlue)),
      ),
    );
  }
}

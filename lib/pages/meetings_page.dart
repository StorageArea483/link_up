import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/widgets/call_storage/call_screen.dart';
import 'package:link_up/pages/incoming_call_screen.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/providers/meetings_caller_provider.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'dart:developer';

class MeetingsPage extends ConsumerStatefulWidget {
  const MeetingsPage({super.key});

  @override
  ConsumerState<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends ConsumerState<MeetingsPage>
    with WidgetsBindingObserver {
  StreamSubscription? _incomingCallSub;
  final TextEditingController _searchController = TextEditingController();

  // List-based subscriptions — same pattern as user_chats.dart so every
  // contact stays subscribed (a Map/single field would cancel the previous
  // one on each iteration).
  final List<StreamSubscription> _presenceSubscriptions = [];

  String? currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
      _listenForIncomingCalls();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSub?.cancel();
    for (final sub in _presenceSubscriptions) {
      sub.cancel();
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
    }
  }

  void _handleAppDetached() {
    for (final sub in _presenceSubscriptions) {
      sub.cancel();
    }
    _presenceSubscriptions.clear();
  }

  void _handleAppPaused() {
    if (!mounted) return;
    for (final sub in _presenceSubscriptions) {
      sub.pause();
    }
    ref.read(userContactProvider).whenData((contacts) {
      for (final contact in contacts) {
        ref.read(isOnlineProvider(contact.uid).notifier).state = false;
      }
    });
  }

  void _handleAppResumed() {
    if (!mounted) return;
    currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Re-fetch real presence values from DB and resume/re-establish subs.
    if (_presenceSubscriptions.isEmpty) {
      _resubscribeFromProvider();
    } else {
      ref.read(userContactProvider).whenData((contacts) {
        for (final contact in contacts) {
          _fetchAndSetPresence(contact.uid);
        }
      });
      for (final sub in _presenceSubscriptions) {
        if (sub.isPaused) sub.resume();
      }
    }
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    ref.read(navigationProvider.notifier).state = null;

    currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final contacts = await ref.read(userContactProvider.future);
      if (!mounted) return;
      for (final contact in contacts) {
        if (!mounted) return;
        // Fetch real DB value immediately so the dot is correct on page open.
        _fetchAndSetPresence(contact.uid);
        // Then keep it live with a realtime subscription.
        _subscribeToPresence(contact.uid);
      }
    } catch (e) {
      // Continue if pre-loading fails
    }
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
      final payload = response.payload;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CheckConnection(
            child: IncomingCallScreen(
              callId: payload['\$id'] as String,
              callerName: payload['callerName'] as String? ?? 'Unknown',
              callerPhoneNumber: payload['callerPhoneNumber'] as String,
              callerProfilePicture: payload['callerProfilePicture'] as String,
              callerId: payload['callerId'] as String,
              offer: payload['offer'] as String,
              isVideo: payload['isVideo'] as bool? ?? true,
            ),
          ),
        ),
      );
    });
  }

  Future<void> _fetchAndSetPresence(String contactId) async {
    try {
      if (!mounted) return;
      final doc = await ChatService.getUserPresence(contactId);
      if (!mounted) return;
      ref.read(isOnlineProvider(contactId).notifier).state =
          doc?.data['online'] ?? false;
    } catch (e, stack) {
      log(
        'ERROR in _MeetingsPageState._fetchAndSetPresence: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _subscribeToPresence(String contactId) {
    try {
      if (!mounted) return;
      final sub = ChatService.subscribeToPresence(contactId, (response) {
        if (!mounted) return;
        try {
          final isOnline = response.payload['online'] ?? false;
          // Key matches _fetchAndSetPresence and how the UI watches the provider.
          ref.read(isOnlineProvider(contactId).notifier).state = isOnline;
        } catch (e, stack) {
          log(
            'ERROR in _MeetingsPageState._subscribeToPresence callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
      if (sub != null) _presenceSubscriptions.add(sub);
    } catch (e, stack) {
      log(
        'ERROR in _MeetingsPageState._subscribeToPresence: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Cancels + clears all subs, then re-subscribes for every contact using
  /// the already-cached provider value (no async needed).
  void _resubscribeFromProvider() {
    for (final sub in _presenceSubscriptions) {
      sub.cancel();
    }
    _presenceSubscriptions.clear();

    ref.read(userContactProvider).whenData((contacts) {
      for (final contact in contacts) {
        if (!mounted) return;
        _fetchAndSetPresence(contact.uid);
        _subscribeToPresence(contact.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reset all presence to false when network drops; re-fetch when it returns.
    ref.listen<AsyncValue<bool>>(networkConnectivityProvider, (previous, next) {
      if (!mounted) return;
      next.whenData((isOnline) async {
        if (isOnline) {
          currentUserId = FirebaseAuth.instance.currentUser?.uid;
          try {
            if (!mounted) return;
            _resubscribeFromProvider();
          } catch (e, stack) {
            log(
              'ERROR in _MeetingsPageState networkConnectivityProvider listener: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
          }
        } else {
          // Going offline — reset all dots to offline immediately.
          for (final sub in _presenceSubscriptions) {
            sub.pause();
          }
          ref.read(userContactProvider).whenData((contacts) {
            for (final contact in contacts) {
              ref.read(isOnlineProvider(contact.uid).notifier).state = false;
            }
          });
        }
      });
    });

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
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_off,
                                          size: 100,
                                          color: AppColors.textPrimary,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No contacts match your search.',
                                          style: AppTextStyles.subtitle,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
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
                                final userId =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (userId == null) {
                                  return const SizedBox.shrink();
                                }
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
                                            // Read by contact.uid — consistent
                                            // with how the provider is keyed.
                                            final isOnline = ref.read(
                                              isOnlineProvider(contact.uid),
                                            );
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    CheckConnection(
                                                      child: CallScreen(
                                                        calleeId: contact.uid,
                                                        calleeName:
                                                            contact.name,
                                                        callerProfilePicture:
                                                            contact
                                                                .profilePicture,
                                                        isVideo: false,
                                                        isCaller: true,
                                                        isOnline: isOnline,
                                                      ),
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        _ActionCircleButton(
                                          icon: Icons.videocam_rounded,
                                          onPressed: () {
                                            final isOnline = ref.read(
                                              isOnlineProvider(contact.uid),
                                            );
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    CheckConnection(
                                                      child: CallScreen(
                                                        calleeId: contact.uid,
                                                        calleeName:
                                                            contact.name,
                                                        callerProfilePicture:
                                                            contact
                                                                .profilePicture,
                                                        isVideo: true,
                                                        isCaller: true,
                                                        isOnline: isOnline,
                                                      ),
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

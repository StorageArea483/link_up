import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/pages/incoming_call_screen.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/chat_storage/chat_screen.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'dart:async';
import 'dart:developer';

class UserChats extends ConsumerStatefulWidget {
  const UserChats({super.key});

  @override
  ConsumerState<UserChats> createState() => _UserChatsState();
}

class _UserChatsState extends ConsumerState<UserChats>
    with WidgetsBindingObserver {
  StreamSubscription? messageSubscription;
  StreamSubscription? _incomingCallSub;
  final List<StreamSubscription> _presenceSubscriptions = [];
  final List<StreamSubscription> _typingSubscriptions = [];

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    messageSubscription?.cancel();
    _incomingCallSub?.cancel();
    for (final sub in _presenceSubscriptions) {
      sub.cancel();
    }
    for (final sub in _typingSubscriptions) {
      sub.cancel();
    }
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
    messageSubscription?.cancel();
    messageSubscription = null;
  }

  void _handleAppPaused() {
    if (!mounted) return;
    _pauseAllSubscriptions();
  }

  void _handleAppResumed() async {
    if (!mounted) return;
    currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    _resumeAllSubscriptions();

    try {
      ref.invalidate(userContactProvider);
      final contacts = await ref.read(userContactProvider.future);
      if (!mounted) return;
      _invalidateContactProviders(contacts);
    } catch (e, stack) {
      log(
        'ERROR in _UserChatsState._handleAppResumed: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to refresh chat data. Please restart the app.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _pauseAllSubscriptions() {
    messageSubscription?.pause();
    for (final sub in _presenceSubscriptions) {
      sub.pause();
    }
    for (final sub in _typingSubscriptions) {
      sub.pause();
    }
    ref.read(userContactProvider).whenData((contacts) {
      for (final contact in contacts) {
        ref.read(isOnlineProvider(contact.uid).notifier).state = false;
      }
    });
  }

  void _resumeAllSubscriptions() {
    if (messageSubscription == null) {
      _subscribeToMessages();
    } else if (messageSubscription!.isPaused) {
      messageSubscription!.resume();
    }
    if (_presenceSubscriptions.isEmpty) {
      _resubscribeContactStreamsFromProvider();
    } else {
      for (final sub in _presenceSubscriptions) {
        if (sub.isPaused) sub.resume();
      }
    }
    if (_typingSubscriptions.isEmpty) {
      _resubscribeContactStreamsFromProvider();
    } else {
      for (final sub in _typingSubscriptions) {
        if (sub.isPaused) sub.resume();
      }
    }
  }

  /// Invalidates last message and unread count providers for all contacts
  /// to force a fresh data fetch.
  void _invalidateContactProviders(List<dynamic> contacts) {
    for (final contact in contacts) {
      if (!mounted) return;
      ref.invalidate(lastMessageProvider(contact.uid));
      ref.invalidate(unreadCountProvider(contact.uid));
    }
  }

  void _subscribeToMessages() {
    try {
      if (!mounted) return;
      currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;
      messageSubscription?.cancel();
      messageSubscription = ChatService.subscribeToRealtimeMessages((message) {
        if (!mounted) return;
        try {
          final newMessage = Message.fromJson(message.payload);

          if (newMessage.senderId == currentUserId ||
              newMessage.receiverId == currentUserId) {
            final contactId = newMessage.senderId == currentUserId
                ? newMessage.receiverId
                : newMessage.senderId;

            if (!mounted) return;
            ref.invalidate(lastMessageProvider(contactId));
            ref.invalidate(unreadCountProvider(contactId));
          }
        } catch (e, stack) {
          log(
            'ERROR in _UserChatsState._subscribeToMessages callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
    } catch (e, stack) {
      log(
        'ERROR in _UserChatsState._subscribeToMessages: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      messageSubscription?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to connect to chat service. Please check your connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// One-time manual fetch of a contact's presence document from the database.
  /// Immediately seeds [isOnlineProvider] with the current value so the UI
  /// shows the correct online/offline dot as soon as the page opens, before
  /// any realtime event has arrived.
  Future<void> _fetchAndSetPresence(String contactId) async {
    try {
      if (!mounted) return;
      final doc = await ChatService.getUserPresence(contactId);
      if (!mounted) return;
      final isOnline = doc?.data['online'] ?? false;
      ref.read(isOnlineProvider(contactId).notifier).state = isOnline;
    } catch (e, stack) {
      log(
        'ERROR in _UserChatsState._fetchAndSetPresence: $e\nSTACK: $stack',
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
          ref.read(isOnlineProvider(contactId).notifier).state = isOnline;
        } catch (e, stack) {
          log(
            'ERROR in _UserChatsState._subscribeToPresence callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
      if (sub != null) _presenceSubscriptions.add(sub);
    } catch (e, stack) {
      log(
        'ERROR in _UserChatsState._subscribeToPresence: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to connect to presence service. Please check your connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _subscribeToTyping(String contactId) {
    try {
      if (!mounted || currentUserId == null) return;
      // ChatService.subscribeToTyping filters by chatId, not contactId.
      // Generate the same deterministic chatId used everywhere else.
      final chatId = ChatService.generateChatId(currentUserId!, contactId);
      final sub = ChatService.subscribeToTyping(chatId, (response) {
        if (!mounted) return;
        try {
          if (response.payload['userId'] != currentUserId) {
            ref.read(isTypingProvider(contactId).notifier).state =
                response.payload['isTyping'] ?? false;
          }
        } catch (e, stack) {
          log(
            'ERROR in _UserChatsState._subscribeToTyping callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
      if (sub != null) _typingSubscriptions.add(sub);
    } catch (e, stack) {
      log(
        'ERROR in _UserChatsState._subscribeToTyping: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to connect to typing service. Please check your connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resubscribeContactStreams(List<dynamic> contacts) {
    // Cancel and clear existing per-contact subscriptions before re-subscribing
    for (final sub in _presenceSubscriptions) {
      sub.cancel();
    }
    _presenceSubscriptions.clear();
    for (final sub in _typingSubscriptions) {
      sub.cancel();
    }
    _typingSubscriptions.clear();

    for (final contact in contacts) {
      if (!mounted) return;
      _subscribeToPresence(contact.uid);
      _subscribeToTyping(contact.uid);
    }
  }

  /// Used by _resumeAllSubscriptions when no contacts list is readily
  /// available — reads the already-cached contact provider value.
  void _resubscribeContactStreamsFromProvider() {
    final contactsValue = ref.read(userContactProvider);
    contactsValue.whenData((contacts) {
      _resubscribeContactStreams(contacts);
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    ref.read(navigationProvider.notifier).state = null;
    currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _subscribeToMessages();

    // Check connectivity before loading contacts
    try {
      final isOnline = await ref.read(networkConnectivityProvider.future);
      if (!mounted) return;
      if (!isOnline) {
        _pauseAllSubscriptions();
        return;
      }
    } catch (e) {
      // Continue even if connectivity check fails
    }

    // Load contacts, pre-warm providers and subscribe to streams
    try {
      ref.invalidate(userContactProvider);
      final contacts = await ref.read(userContactProvider.future);
      if (!mounted) return;

      for (final contact in contacts) {
        if (!mounted) return;
        ref.invalidate(lastMessageProvider(contact.uid));
        ref.invalidate(unreadCountProvider(contact.uid));
        // Pre-load data
        ref.read(lastMessageProvider(contact.uid));
        ref.read(unreadCountProvider(contact.uid));
        // Manually fetch the contact's current presence from the database.
        // This is necessary because CheckConnection.build() calls
        // ChatService.updatePresence(..., online: true) on every page load,
        // so the realtime subscription alone would miss the initial state
        // that was already written before the subscription was registered.
        _fetchAndSetPresence(contact.uid);
        // Subscribe to per-contact streams
        _subscribeToPresence(contact.uid);
        _subscribeToTyping(contact.uid);
      }
    } catch (e) {
      // Continue even if pre-loading fails - data will load on demand
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to network connectivity changes
    ref.listen<AsyncValue<bool>>(networkConnectivityProvider, (previous, next) {
      if (!mounted) return;

      next.whenData((isOnline) async {
        if (isOnline) {
          currentUserId = FirebaseAuth.instance.currentUser?.uid;
          _subscribeToMessages();

          try {
            ref.invalidate(userContactProvider);
            final contacts = await ref.read(userContactProvider.future);
            if (!mounted) return;
            _invalidateContactProviders(contacts);
            _resubscribeContactStreams(contacts);
          } catch (e, stack) {
            log(
              'ERROR in _UserChatsState networkConnectivityProvider listener: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
          }
        } else {
          _pauseAllSubscriptions();
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
          title: const Text('User Chats', style: AppTextStyles.title),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    const CheckConnection(child: LandingPage()),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = (constraints.maxWidth >= 600)
                  ? 32.0
                  : 20.0;
              return Consumer(
                builder: (context, ref, _) {
                  final contactsAsyncValue = ref.watch(userContactProvider);
                  return contactsAsyncValue.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    data: (contacts) {
                      if (contacts.isEmpty) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: const SizedBox(
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

                      return ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          8,
                          horizontalPadding,
                          100,
                        ),
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
                              leading: Consumer(
                                builder: (context, ref, _) {
                                  final unreadCountAsync = ref.watch(
                                    unreadCountProvider(contact.uid),
                                  );
                                  final int unreadCount =
                                      unreadCountAsync.value ?? 0;

                                  // Firebase Auth is synchronous — user is guaranteed logged in
                                  // here because CheckConnection wraps this page
                                  final userId =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (userId == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final isOnline = ref.watch(
                                    isOnlineProvider(contact.uid),
                                  );

                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
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
                                                (context, error, stackTrace) =>
                                                    const Icon(
                                                      Icons.person_2_outlined,
                                                      color:
                                                          AppColors.primaryBlue,
                                                      size: 32,
                                                    ),
                                            loadingBuilder:
                                                (
                                                  context,
                                                  child,
                                                  loadingProgress,
                                                ) {
                                                  if (loadingProgress == null) {
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
                                        ),
                                      ),

                                      // Unread badge
                                      if (unreadCount > 0)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          child: CircleAvatar(
                                            radius: 12,
                                            backgroundColor:
                                                AppColors.primaryBlue,
                                            child: Text(
                                              unreadCount.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),

                                      // Online / offline dot
                                      Positioned(
                                        right: 2,
                                        bottom: 2,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: isOnline
                                                ? AppColors.onlineGreen
                                                : AppColors.offlineGrey,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.white,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              title: Text(
                                contact.name,
                                style: AppTextStyles.button.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                              subtitle: Consumer(
                                builder: (context, ref, _) {
                                  final lastMessageAsync = ref.watch(
                                    lastMessageProvider(contact.uid),
                                  );

                                  final isTyping = ref.watch(
                                    isTypingProvider(contact.uid),
                                  );

                                  return lastMessageAsync.when(
                                    data: (lastMessage) => Text(
                                      isTyping
                                          ? 'Typing...'
                                          : lastMessage.isEmpty
                                          ? 'No messages yet'
                                          : lastMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.subtitle.copyWith(
                                        fontSize: 14,
                                      ),
                                    ),
                                    loading: () => Text(
                                      'Loading...',
                                      style: AppTextStyles.subtitle.copyWith(
                                        fontSize: 14,
                                      ),
                                    ),
                                    error: (_, _) => Text(
                                      'No messages yet',
                                      style: AppTextStyles.subtitle.copyWith(
                                        fontSize: 14,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => CheckConnection(
                                      child: ChatScreen(contact: contact),
                                    ),
                                  ),
                                );
                              },
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
              );
            },
          ),
        ),
        bottomNavigationBar: const BottomNavbar(currentIndex: 2),
      ),
    );
  }
}

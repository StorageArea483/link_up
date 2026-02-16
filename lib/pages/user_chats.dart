import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/chat_storage/chat_screen.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'dart:developer';

class UserChats extends ConsumerStatefulWidget {
  const UserChats({super.key});

  @override
  ConsumerState<UserChats> createState() => _UserChatsState();
}

class _UserChatsState extends ConsumerState<UserChats>
    with WidgetsBindingObserver {
  var messageSubscription;

  @override
  void initState() {
    super.initState();

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeText();
    });
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    messageSubscription?.cancel();
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
    try {
      if (!mounted) return;

      log('App detached - cancelling subscriptions', name: 'UserChats');
      // App is about to be terminated, clean up subscriptions
      messageSubscription?.cancel();
      // Set subscriptions to null so they can be re-established if needed
      messageSubscription = null;
    } catch (e) {
      log('Failed to handle app detached: $e', name: 'UserChats');
    }
  }

  void _handleAppResumed() async {
    try {
      if (!mounted) return;
      // Re-establish subscription if needed
      log('App resumed - adding subscriptions', name: 'UserChats');
      if (messageSubscription == null) {
        _subscribeToMessages();
      }

      // Invalidate and refresh all contact-related providers
      if (mounted) {
        ref.invalidate(userContactProvider);

        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null && mounted) {
          try {
            final contacts = await ref.read(userContactProvider.future);
            if (!mounted) return;

            for (final contact in contacts) {
              if (!mounted) return;
              ref.invalidate(lastMessageProvider(contact.uid));
              ref.invalidate(unreadCountProvider(contact.uid));
            }
          } catch (e) {
            log('Failed to handle app resumed: $e', name: 'UserChats');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Failed to refresh chat data. Please restart the app.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      log('Failed to handle app resume: $e', name: 'UserChats');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to restore chat connections. Please restart the app.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleAppPaused() {
    try {
      if (!mounted) return;
      log(
        'App paused - pausing subscriptions to save resources',
        name: 'UserChats',
      );
      // Pause subscriptions to save battery and network resources
      // They will be resumed when app comes back to foreground
      messageSubscription?.pause();
    } catch (e) {
      log('Failed to handle app pause: $e', name: 'UserChats');
    }
  }

  void _subscribeToMessages() {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Cancel existing subscription if it exists
      messageSubscription?.cancel();

      // Subscribe to all messages with status 'sent'
      messageSubscription = ChatService.subscribeToRealtimeMessages((message) {
        if (!mounted) return;

        try {
          final newMessage = Message.fromJson(message.payload);

          // Check if this message is relevant to the current user
          // (either sent by them or sent to them)
          if (newMessage.senderId == currentUserId ||
              newMessage.receiverId == currentUserId) {
            // Determine the contact (the OTHER person in this conversation)
            final contactId = newMessage.senderId == currentUserId
                ? newMessage
                      .receiverId // If I sent it, the contact is the receiver
                : newMessage
                      .senderId; // If I received it, the contact is the sender

            // Invalidate providers for this contact to trigger UI refresh
            if (!mounted) return;
            ref.invalidate(lastMessageProvider(contactId));
            ref.invalidate(unreadCountProvider(contactId));
          }
        } catch (e) {
          // Handle parsing errors silently - these are expected for malformed messages
          log('Failed to parse realtime message: $e', name: 'UserChats');
        }
      });
    } catch (e) {
      log('Failed to setup message subscription: $e', name: 'UserChats');
      messageSubscription?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to connect to chat service. Please check your connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeText() async {
    _subscribeToMessages();

    // Check initial network connectivity
    try {
      final isOnline = await ref.read(networkConnectivityProvider.future);
      if (!mounted) return;
      if (!isOnline) {
        messageSubscription?.pause();
      } else {
        messageSubscription?.resume();
      }
    } catch (e) {
      log('Failed to check network connectivity: $e', name: 'UserChats');
      // Continue initialization even if connectivity check fails
    }

    // Pre-warm the providers for better performance
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && mounted) {
      try {
        // This will trigger the providers to start loading data
        final contacts = await ref.read(userContactProvider.future);
        if (!mounted) return;
        for (final contact in contacts) {
          // Pre-load last messages and unread counts for all contacts
          if (!mounted) return;
          ref.read(lastMessageProvider(contact.uid));
          ref.read(unreadCountProvider(contact.uid));
        }
      } catch (e) {
        log('Failed to pre-load contact data: $e', name: 'UserChats');
        // Continue even if pre-loading fails - data will load on demand
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to network connectivity changes - this is the correct place for ref.listen
    ref.listen<AsyncValue<bool>>(networkConnectivityProvider, (previous, next) {
      if (!mounted) return;

      next.whenData((isOnline) {
        if (isOnline) {
          // Re-establish subscription (it will cancel existing one first)
          _subscribeToMessages();

          // Refresh all providers when coming back online
          if (!mounted) return;
          ref.invalidate(userContactProvider);

          // Also refresh all contact providers to ensure fresh data
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          if (currentUserId != null && mounted) {
            ref.read(userContactProvider.future).then((contacts) {
              for (final contact in contacts) {
                if (!mounted) return;
                ref.invalidate(lastMessageProvider(contact.uid));
                ref.invalidate(unreadCountProvider(contact.uid));
              }
            });
          }
        } else {
          messageSubscription?.pause();
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
          child: Consumer(
            builder: (context, ref, _) {
              final contactsAsyncValue = ref.watch(userContactProvider);
              return contactsAsyncValue.when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                data: (contacts) {
                  if (contacts.isEmpty) {
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
                  return ListView.builder(
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
                          leading: Consumer(
                            builder: (context, ref, _) {
                              final unreadCountAsync = ref.watch(
                                unreadCountProvider(contact.uid),
                              );
                              final int unreadCount =
                                  unreadCountAsync.value ?? 0;

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
                                  if (unreadCount > 0)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: AppColors.primaryBlue,
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
                                ],
                              );
                            },
                          ),
                          title: Text(
                            contact.name,
                            style: AppTextStyles.button.copyWith(fontSize: 18),
                          ),
                          subtitle: Consumer(
                            builder: (context, ref, _) {
                              final lastMessageAsync = ref.watch(
                                lastMessageProvider(contact.uid),
                              );
                              return lastMessageAsync.when(
                                data: (lastMessage) => Text(
                                  lastMessage.isEmpty
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
          ),
        ),
        bottomNavigationBar: const BottomNavbar(currentIndex: 2),
      ),
    );
  }
}

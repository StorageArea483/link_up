import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/pages/user_chats.dart';
import 'package:link_up/widgets/check_connection.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final UserContacts contact;
  const ChatScreen({super.key, required this.contact});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  var messageSubscription;
  var typingSubscription;
  var presenceSubscription;

  String? _currentUserId;
  String? _chatId;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
        // Prevent running logic on a State that no longer exists.
      }
      _initializeChat();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    messageSubscription?.cancel();
    typingSubscription?.cancel();
    presenceSubscription?.cancel();

    if (_currentUserId != null && _chatId != null) {
      ChatService.setTyping(
        chatId: _chatId!,
        userId: _currentUserId!,
        isTyping: false,
      );
    }
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    _currentUserId = userId;
    ref.read(currentUserIdProvider.notifier).state =
        userId; // this provider indicates the current user using the app

    if (userId == null) {
      ref.read(isLoadingStateProvider.notifier).state = false;
      return;
    }

    final chatId = ChatService.generateChatId(userId, widget.contact.uid);
    _chatId = chatId;
    ref.read(chatIdProvider.notifier).state =
        chatId; // the current chat id between authenticated users

    // Set current user as online
    await ChatService.updatePresence(
      userId: userId,
      online: true,
    ); // updating the current users presence to online

    await _loadMessages();
    _subscribeToMessages();
    _subscribeToTyping();
    _subscribeToPresence();

    // Check contact's presence after setting up subscriptions
    await _checkUserPresence();

    // Mark messages as delivered when user comes online and update UI
    await _markMessagesAsDeliveredAndUpdate(userId);

    ref.read(isLoadingStateProvider.notifier).state = false;
  }

  Future<void> _markMessagesAsDeliveredAndUpdate(String userId) async {
    if (_chatId == null) return;

    try {
      final updatedMessages = await ChatService.markMessagesAsDelivered(
        chatId: _chatId!,
        receiverId: userId,
      );

      if (updatedMessages.isNotEmpty && mounted) {
        // Update the messages provider with the new status
        final currentMessages = ref.read(messagesProvider);
        final updatedMessagesList = [...currentMessages];

        for (final updatedMessage in updatedMessages) {
          final updatedMsg = Message.fromJson(updatedMessage.data);
          final index = updatedMessagesList.indexWhere(
            (msg) => msg.id == updatedMsg.id,
          );
          if (index != -1) {
            updatedMessagesList[index] = updatedMsg;
          }
        }

        ref.read(messagesProvider.notifier).state = updatedMessagesList;
      }
    } catch (e) {
      // Silent failure
    }
  }

  Future<bool> _loadMessages() async {
    try {
      final chatId = ref.read(
        chatIdProvider,
      ); // indicating current chat between users
      if (chatId == null) return false;

      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final messagesList = docs.documents
            .map((doc) => Message.fromJson(doc.data))
            .toList();
        ref.read(messagesProvider.notifier).state = messagesList;
      }
    } catch (e) {
      return false;
    }
    return true;
  }

  void _subscribeToMessages() {
    final chatId = ref.read(
      chatIdProvider,
    ); // current chat id between the two users
    if (chatId == null) return;

    try {
      messageSubscription = ChatService.subscribeToMessages(chatId, (response) {
        if (!mounted) return;
        try {
          final newMessage = Message.fromJson(response.payload);
          final currentMessages = ref.read(messagesProvider);

          // Update existing message if it exists, otherwise add new
          final existingIndex = currentMessages.indexWhere(
            (msg) => msg.id == newMessage.id,
          );
          if (existingIndex != -1) {
            final updatedMessages = [...currentMessages];
            updatedMessages[existingIndex] = newMessage;
            ref.read(messagesProvider.notifier).state = updatedMessages;
          } else {
            ref.read(messagesProvider.notifier).state = [
              newMessage,
              ...currentMessages,
            ];
          }
        } catch (e) {}
      });
    } catch (e) {}
  }

  void _subscribeToTyping() {
    final chatId = ref.read(chatIdProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (chatId == null) return;

    try {
      typingSubscription = ChatService.subscribeToTyping(chatId, (response) {
        if (!mounted) return;
        try {
          if (response.payload['userId'] != currentUserId) {
            ref.read(isTypingProvider.notifier).state =
                response.payload['isTyping'] ?? false;
          }
        } catch (e) {}
      });
    } catch (e) {}
  }

  void _subscribeToPresence() {
    try {
      presenceSubscription = ChatService.subscribeToPresence(
        widget.contact.uid,
        (response) {
          if (!mounted) return;
          try {
            final isOnline = response.payload['online'] ?? false;
            final lastSeenStr = response.payload['lastSeen'];

            ref.read(isOnlineProvider.notifier).state = isOnline;

            // Update Last Seen Provider with robust parsing
            if (!isOnline &&
                lastSeenStr != null &&
                lastSeenStr.toString().isNotEmpty) {
              try {
                final lastSeenTime = DateTime.parse(lastSeenStr).toLocal();
                ref.read(lastSeenProvider.notifier).state =
                    'Last seen ${_formatTime(lastSeenTime)}';
              } catch (e) {
                // Fallback if date parsing fails
                ref.read(lastSeenProvider.notifier).state = 'Offline';
              }
            } else if (!isOnline) {
              ref.read(lastSeenProvider.notifier).state = 'Offline';
            } else {
              ref.read(lastSeenProvider.notifier).state = '';
            }

            // When contact comes online (transition from offline to online)
            // Note: We use the local variable isOnline here
            if (isOnline &&
                !_isOnlineProviderValue && // Use local check effectively
                _currentUserId != null &&
                _chatId != null) {
              // Update UI for messages
              _markMessagesAsDeliveredAndUpdate(widget.contact.uid);
            }
          } catch (e) {
            debugPrint('Error in presence listener: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('Error subscribing to presence: $e');
    }
  }

  // Helper to check current provider value to detect transition
  bool get _isOnlineProviderValue => ref.read(isOnlineProvider);

  Future<void> _checkUserPresence() async {
    try {
      final presence = await ChatService.getUserPresence(widget.contact.uid);
      // checking the presence of the reciever
      if (mounted) {
        // If no presence record exists, assume user is offline
        final isOnline = presence?.data['online'] ?? false;
        final lastSeenStr = presence?.data['lastSeen'];

        ref.read(isOnlineProvider.notifier).state =
            isOnline; // provider for updating the online\offline\lastSeen status of the other user

        if (!isOnline &&
            lastSeenStr != null &&
            lastSeenStr.toString().isNotEmpty) {
          try {
            final lastSeenTime = DateTime.parse(lastSeenStr).toLocal();
            ref.read(lastSeenProvider.notifier).state =
                'Last seen ${_formatTime(lastSeenTime)}';
          } catch (e) {
            ref.read(lastSeenProvider.notifier).state = 'Offline';
          }
        } else if (!isOnline) {
          ref.read(lastSeenProvider.notifier).state = 'Offline';
        }
      }
    } catch (e) {
      // On error, assume user is offline
      if (mounted) {
        ref.read(isOnlineProvider.notifier).state = false;
        ref.read(lastSeenProvider.notifier).state = 'Offline';
      }
    }
  }

  Future<void> _sendMessage() async {
    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);
    final networkOnlineAsync = ref.read(networkConnectivityProvider);
    final hasInternet = networkOnlineAsync.value ?? true;

    if (_messageController.text.trim().isEmpty ||
        currentUserId == null ||
        chatId == null) {
      return;
    }

    // Check internet connectivity first
    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message failed to send - No internet connection'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      // Create message with 'sent' status - will be updated to 'delivered' when receiver actually receives it
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: widget.contact.uid,
        text: messageText,
      );

      // Immediately add the message to the UI
      if (messageDoc != null && mounted) {
        final newMessage = Message.fromJson(messageDoc.data);
        final currentMessages = ref.read(messagesProvider);
        ref.read(messagesProvider.notifier).state = [
          newMessage,
          ...currentMessages,
        ];
      }

      await ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: false,
      );
    } catch (e) {}
  }

  void _onTypingChanged(String text) {
    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);

    if (currentUserId == null || chatId == null) return;

    if (text.isNotEmpty) {
      ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: true,
      );
    } else {
      ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to connectivity changes and pause/resume subscriptions
    final isOnlineAsync = ref.watch(networkConnectivityProvider);

    isOnlineAsync.whenData((isOnline) {
      if (isOnline != _wasOnline) {
        _wasOnline = isOnline;
        _handleConnectivityChange(isOnline);
      }
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
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildMessagesList(),
              _buildInputSection(),
            ],
          ),
        ),
      ),
    );
  }

  void _handleConnectivityChange(bool isOnline) {
    if (_currentUserId == null) return;

    if (isOnline) {
      // Try to resume subscriptions first
      messageSubscription?.resume();
      typingSubscription?.resume();
      presenceSubscription?.resume();

      // If subscriptions were null or failed, recreate them
      if (messageSubscription == null) {
        _subscribeToMessages();
      }
      if (typingSubscription == null) {
        _subscribeToTyping();
      }
      if (presenceSubscription == null) {
        _subscribeToPresence();
      }

      // Update presence to online and mark messages as delivered with UI update
      ChatService.updatePresence(userId: _currentUserId!, online: true);
      if (_chatId != null) {
        _markMessagesAsDeliveredAndUpdate(_currentUserId!);
      }

      // CRITICAL FIX: Reload messages when coming back online
      // This ensures we get any messages sent while we were offline
      _reloadMessagesAfterReconnection();

      // Check contact's presence again as we might have missed updates
      _checkUserPresence();
    } else {
      messageSubscription?.pause();
      typingSubscription?.pause();
      presenceSubscription?.pause();

      // Update local provider to offline since we are disconnected
      ref.read(isOnlineProvider.notifier).state = false;
    }
  }

  Future<void> _reloadMessagesAfterReconnection() async {
    try {
      final chatId = ref.read(chatIdProvider);
      if (chatId == null) return;
      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final newMessagesList = docs.documents
            .map((doc) => Message.fromJson(doc.data))
            .toList();

        // Only update if we have new messages
        final currentMessages = ref.read(messagesProvider);
        if (newMessagesList.length != currentMessages.length) {
          ref.read(messagesProvider.notifier).state = newMessagesList;
        }
      }
    } catch (e) {}
  }

  // Build header with contact info
  Widget _buildHeader() {
    return Column(
      children: [
        // Network status banner (only shown when sender is offline)
        Consumer(
          builder: (context, ref, _) {
            final networkOnlineAsync = ref.watch(networkConnectivityProvider);
            final networkOnline = networkOnlineAsync.value ?? true;

            if (!networkOnline) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                color: Colors.orange,
                child: const Text(
                  'No internet connection - Messages cannot be sent',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const UserChats()),
                ),
              ),
              CircleAvatar(
                radius: 20,
                child: ClipOval(
                  child: Image.network(
                    widget.contact.profilePicture,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.person_2_outlined,
                        color: AppColors.primaryBlue,
                        size: 24,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contact.name,
                      style: AppTextStyles.button.copyWith(fontSize: 16),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final isTyping = ref.watch(isTypingProvider);
                        final isContactOnline = ref.watch(isOnlineProvider);

                        // FIXED: Only show receiver's actual presence status
                        // Sender's network status does not affect receiver's status
                        return Text(
                          isTyping
                              ? 'typing...'
                              : isContactOnline
                              ? 'Online'
                              : ref.watch(lastSeenProvider).isEmpty
                              ? 'Offline'
                              : ref.watch(lastSeenProvider),
                          style: TextStyle(
                            color: isTyping
                                ? AppColors.primaryBlue
                                : isContactOnline
                                ? Colors.green
                                : AppColors.textFooter,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Build messages list
  Widget _buildMessagesList() {
    final isLoading = ref.watch(isLoadingStateProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }

    if (currentUserId == null) {
      return const Expanded(
        child: Center(
          child: Text('Unable to load messages', style: AppTextStyles.footer),
        ),
      );
    }

    final messages = ref.watch(messagesProvider);

    if (messages.isEmpty) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: AppColors.textFooter,
              ),
              SizedBox(height: 16),
              Text('No messages yet', style: AppTextStyles.footer),
              SizedBox(height: 8),
              Text(
                'Send a message to start chatting',
                style: TextStyle(fontSize: 12, color: AppColors.textFooter),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          final isSentByMe = message.isSentByMe(currentUserId);
          return _buildMessageBubble(message, isSentByMe);
        },
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isSentByMe) {
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isSentByMe ? AppColors.primaryBlue : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
            bottomRight: Radius.circular(isSentByMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isSentByMe ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    color: isSentByMe
                        ? Colors.white.withOpacity(0.7)
                        : AppColors.textFooter,
                    fontSize: 10,
                  ),
                ),
                if (isSentByMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == 'read'
                        ? Icons.done_all
                        : message.status == 'delivered'
                        ? Icons.done_all
                        : Icons.done,
                    size: 14,
                    color: message.status == 'read'
                        ? Colors.blue[200]
                        : Colors.white.withOpacity(0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
      decoration: const BoxDecoration(color: AppColors.white),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppColors.primaryBlue,
              size: 28,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: () {},
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                ),
              ),
              child: TextField(
                controller: _messageController,
                onChanged: _onTypingChanged,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  hintStyle: AppTextStyles.footer,
                ),
                maxLines: null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Consumer(
            builder: (context, ref, _) {
              return CircleAvatar(
                backgroundColor: AppColors.primaryBlue,
                radius: 24,
                child: ref.watch(isLoadingStateProvider)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: AppColors.white,
                          size: 20,
                        ),
                        onPressed: _sendMessage,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Format timestamp
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}

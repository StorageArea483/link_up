import 'package:appwrite/appwrite.dart';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/pages/user_chats.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'package:link_up/database/sqflite_helper.dart';
import 'package:link_up/widgets/sqflite_msgs_clear.dart';

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

  // Helper method to merge messages without losing any
  List<Message> _mergeMessages(
    List<Message> newMessages,
    List<Message> existingMessages,
  ) {
    final messageMap = <String, Message>{};

    // Add existing messages first
    for (final msg in existingMessages) {
      messageMap[msg.id] = msg;
    }

    // Add or update with new messages
    for (final msg in newMessages) {
      messageMap[msg.id] = msg;
    }

    // Convert back to list and sort by creation time (newest first)
    final mergedList = messageMap.values.toList();
    mergedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return mergedList;
  }

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
    if (!mounted) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    _currentUserId = userId;

    if (!mounted) return;
    ref.read(currentUserIdProvider.notifier).state =
        userId; // this provider indicates the current user using the app

    if (userId == null) {
      if (mounted) {
        ref.read(isLoadingStateProvider.notifier).state = false;
      }
      return;
    }

    final chatId = ChatService.generateChatId(userId, widget.contact.uid);
    _chatId = chatId;

    if (!mounted) return;
    ref.read(chatIdProvider.notifier).state =
        chatId; // the current chat id between authenticated users

    // Set current user as online
    await ChatService.updatePresence(
      userId: userId,
      online: true,
    ); // updating the current users presence to online and firing the _subscribeToPresence method

    // IMPORTANT: Load messages first to ensure UI displays them
    await _loadMessages();

    // Set up subscriptions
    _subscribeToMessages();
    _subscribeToTyping();
    _subscribeToPresence();

    // Check contact's presence after setting up subscriptions
    await _checkUserPresence();

    // IMPORTANT: Add a small delay to ensure UI has rendered the messages
    // before marking them as delivered
    await Future.delayed(const Duration(milliseconds: 500));

    // Mark messages as delivered when user comes online and update UI
    await _markMessagesAsDeliveredAndUpdate(userId);

    // Only update loading state if widget is still mounted
    if (mounted) {
      ref.read(isLoadingStateProvider.notifier).state = false;
    }
  }

  Future<void> _markMessagesAsDeliveredAndUpdate(String userId) async {
    // update the message status because receiver has come online
    if (_chatId == null || !mounted) return;

    try {
      final updatedMessages = await ChatService.markMessagesAsDelivered(
        chatId: _chatId!,
        receiverId: userId, // receive messages meant for this user
      );

      if (updatedMessages.isNotEmpty && mounted) {
        // Get current messages from the UI
        final currentMessages = ref.read(messagesProvider);
        final updatedMessagesList = [...currentMessages];

        // Process each updated message
        for (final updatedMessage in updatedMessages) {
          final updatedMsg = Message.fromJson(updatedMessage.data);

          // Find and update the message in the current list
          final index = updatedMessagesList.indexWhere(
            (msg) => msg.id == updatedMsg.id,
          );

          if (index != -1) {
            // Update existing message
            updatedMessagesList[index] = updatedMsg;
          } else {
            // If message not found in current list, add it at the beginning
            updatedMessagesList.insert(0, updatedMsg);
          }

          // Save to SQLite and delete from Appwrite
          final savedSuccessfully = await SqfliteHelper.insertDeliveredMessage(
            updatedMsg,
          );

          if (savedSuccessfully && mounted) {
            ref.invalidate(unreadCountProvider(widget.contact.uid));
            ref.invalidate(lastMessageProvider(widget.contact.uid));
            await ChatService.deleteMessageFromAppwrite(updatedMsg.id);
          }
        }

        // Sort by creation time (newest first) to maintain order
        updatedMessagesList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Update the UI with the new message list
        if (!mounted) return;
        ref.read(messagesProvider.notifier).state = updatedMessagesList;
      } else if (mounted) {
        // No new delivered messages, but ensure we have offline messages loaded
        final currentMessages = ref.read(messagesProvider);
        if (currentMessages.isEmpty) {
          final offlineMessages = await SqfliteHelper.getDeliveredMessages(
            _chatId!,
          );
          if (!mounted) return;
          ref.read(messagesProvider.notifier).state = offlineMessages;
        }
      }
    } catch (e) {
      // On error, ensure we still have offline messages if current list is empty
      if (mounted) {
        final currentMessages = ref.read(messagesProvider);
        if (currentMessages.isEmpty) {
          final offlineMessages = await SqfliteHelper.getDeliveredMessages(
            _chatId!,
          );
          if (!mounted) return;
          ref.read(messagesProvider.notifier).state = offlineMessages;
        }
      }
    }
  }

  Future<bool> _loadMessages() async {
    if (!mounted) return false;

    try {
      final chatId = ref.read(
        chatIdProvider,
      ); // indicating current chat between users
      if (chatId == null) return false;

      // Always try to load from SQLite first to get delivered messages
      final offlineMessages = await SqfliteHelper.getDeliveredMessages(chatId);

      // Try to load from Appwrite for sent status messages
      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final sentMessages = docs.documents
            .map((doc) => Message.fromJson(doc.data))
            .toList(); // sent status messages list

        // Merge offline and online messages using helper method
        final allMessages = _mergeMessages(sentMessages, offlineMessages);

        if (!mounted) return false;

        // Update the provider with all messages
        ref.read(messagesProvider.notifier).state = allMessages;
      }
    } catch (e) {
      // On error, load from SQLite only
      if (!mounted) return false;
      final chatId = ref.read(chatIdProvider);
      if (chatId != null && mounted) {
        final offlineMessages = await SqfliteHelper.getDeliveredMessages(
          chatId,
        );
        if (!mounted) return false;
        ref.read(messagesProvider.notifier).state = offlineMessages;
      }
      return false;
    }
    return true;
  }

  void _subscribeToMessages() {
    if (!mounted) return;

    final chatId = ref.read(
      chatIdProvider,
    ); // current chat id between the two users
    if (chatId == null) return;

    try {
      messageSubscription = ChatService.subscribeToMessages(chatId, (response) {
        if (!mounted) return;
        try {
          final newMessage = Message.fromJson(
            response.payload,
          ); // sent status message

          if (!mounted) return;
          final currentMessages = ref.read(messagesProvider);

          // Check if this is an update to an existing message or a new message
          final existingIndex = currentMessages.indexWhere(
            (msg) =>
                msg.id == newMessage.id, // if newMessage has status delivered
          );

          if (existingIndex != -1) {
            final updatedMessages = [...currentMessages];
            updatedMessages[existingIndex] = newMessage;
            if (!mounted) return;
            ref.read(messagesProvider.notifier).state = updatedMessages;

            if (newMessage.status == 'delivered') {
              _handleDeliveredMessage(newMessage);
            }
          } else {
            // New message received
            if (!mounted) return;
            ref.read(messagesProvider.notifier).state = [
              newMessage,
              ...currentMessages,
            ]; // if sent status message simply add it in the UI

            // IMPORTANT: Auto-mark as delivered if receiver is online and in chat
            if (newMessage.status == 'sent' &&
                newMessage.receiverId == _currentUserId &&
                mounted) {
              // Mark this specific message as delivered
              _markSingleMessageAsDelivered(newMessage.id);
            }

            if (newMessage.status == 'delivered') {
              _handleDeliveredMessage(newMessage);
            }
          }
        } catch (e) {}
      });
    } catch (e) {}
  }

  Future<void> _handleDeliveredMessage(Message message) async {
    final savedSuccessfully = await SqfliteHelper.insertDeliveredMessage(
      message,
    );

    if (savedSuccessfully) {
      await ChatService.deleteMessageFromAppwrite(message.id);
    }
  }

  // Mark a single specific message as delivered (for real-time auto-delivery)
  Future<void> _markSingleMessageAsDelivered(String messageId) async {
    if (_chatId == null || _currentUserId == null || !mounted) return;

    try {
      // Update the specific message status to 'delivered'
      final updatedMessage = await ChatService.updateMessageStatus(
        messageId,
        'delivered',
      );

      if (updatedMessage != null && mounted) {
        // Update the UI immediately
        final currentMessages = ref.read(messagesProvider);
        final updatedMessagesList = [...currentMessages];

        final updatedMsg = Message.fromJson(updatedMessage.data);
        final index = updatedMessagesList.indexWhere(
          (msg) => msg.id == updatedMsg.id,
        );

        if (index != -1) {
          updatedMessagesList[index] = updatedMsg;
          if (!mounted) return;
          ref.read(messagesProvider.notifier).state = updatedMessagesList;

          // Handle the delivered message (save to SQLite and delete from Appwrite)
          await _handleDeliveredMessage(updatedMsg);
        }
      }
    } catch (e) {}
  }

  void _subscribeToTyping() {
    if (!mounted) return;

    final chatId = ref.read(chatIdProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (chatId == null) return;

    try {
      typingSubscription = ChatService.subscribeToTyping(chatId, (response) {
        if (!mounted) return;
        try {
          if (response.payload['userId'] != currentUserId) {
            if (!mounted) return;
            ref.read(isTypingProvider.notifier).state =
                response.payload['isTyping'] ?? false;
          }
        } catch (e) {}
      });
    } catch (e) {}
  }

  void _subscribeToPresence() {
    if (!mounted) return;

    try {
      presenceSubscription = ChatService.subscribeToPresence(widget.contact.uid, (
        response,
      ) {
        if (!mounted) return;
        try {
          final isOnline =
              response.payload['online'] ??
              false; // checking the receiver status

          // IMPORTANT: Read the OLD status BEFORE updating it
          // This allows us to detect the transition from offline → online
          if (!mounted) return;
          final wasOnlineBefore = ref.read(isOnlineProvider);

          // Now update the provider with the NEW status
          if (!mounted) return;
          ref.read(isOnlineProvider.notifier).state =
              isOnline; // provider for updating the receiver online/offline status

          // Detect transition: Contact just came online (was offline, now online)
          // This is when we mark messages as delivered
          if (isOnline &&
              !wasOnlineBefore && // Was offline before, now online = transition detected!
              _currentUserId != null &&
              _chatId != null) {
            // Contact just came online, mark their messages as delivered
            _markMessagesAsDeliveredAndUpdate(widget.contact.uid);
          }
        } catch (e) {}
      });
    } catch (e) {}
  }

  Future<void> _checkUserPresence() async {
    try {
      final presence = await ChatService.getUserPresence(widget.contact.uid);
      // checking the presence of the receiver
      if (mounted) {
        // If no presence record exists, assume user is offline
        final isOnline = presence?.data['online'] ?? false;

        ref.read(isOnlineProvider.notifier).state =
            isOnline; // provider for updating the online/offline status of the other user
      }
    } catch (e) {
      // On error, assume user is offline
      if (mounted) {
        ref.read(isOnlineProvider.notifier).state = false;
      }
    }
  }

  Future<void> _sendMessage() async {
    if (!mounted) return;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send - No internet connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: widget.contact.uid,
        text: messageText,
      );

      // Immediately add the message to the UI
      if (messageDoc != null && mounted) {
        final newMessage = Message.fromJson(
          messageDoc.data,
        ); // message with status sent gets added in appwrite db
        final currentMessages = ref.read(messagesProvider);
        if (!mounted) return;
        ref.read(messagesProvider.notifier).state = [
          newMessage,
          ...currentMessages,
        ];
        // Import the providers and invalidate them for this contact
        // This ensures the sender's chat list updates immediately

        try {
          if (!mounted) return;
          ref.invalidate(lastMessageProvider(widget.contact.uid));
        } catch (e) {}
      }

      await ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: false,
      );
    } catch (e) {}
  }

  void _onTypingChanged(String text) {
    if (!mounted) return;

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
    // Listen to network connectivity changes - this is the correct place for ref.listen
    // registers only one listener and replaces the current listener with new one with rebuilds
    ref.listen<AsyncValue<bool>>(networkConnectivityProvider, (previous, next) {
      if (!mounted) return;

      next.whenData((isOnline) {
        if (isOnline != _wasOnline) {
          _wasOnline = isOnline;
          _handleConnectivityChange(isOnline);
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
    if (_currentUserId == null || !mounted) return;

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

      // Only reload messages if we don't have any messages currently
      if (!mounted) return;
      final currentMessages = ref.read(messagesProvider);
      if (currentMessages.isEmpty) {
        _reloadMessagesAfterReconnection();
      }

      _checkUserPresence();
    } else {
      messageSubscription?.pause();
      typingSubscription?.pause();
      presenceSubscription?.pause();

      if (mounted) {
        ref.read(isOnlineProvider.notifier).state =
            false; // update the receiver online status to offline
      }
    }
  }

  Future<void> _reloadMessagesAfterReconnection() async {
    if (!mounted) return;

    try {
      final chatId = ref.read(chatIdProvider);
      if (chatId == null) return;

      // Get current messages to preserve them
      if (!mounted) return;
      final currentMessages = ref.read(messagesProvider);

      // Step 1: Fetch latest messages from Appwrite
      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final newMessagesList = docs.documents
            .map((doc) => Message.fromJson(doc.data))
            .toList();

        // Step 2: Merge messages intelligently using helper method
        if (newMessagesList.isNotEmpty) {
          // Merge new messages with existing ones
          final mergedMessages = _mergeMessages(
            newMessagesList,
            currentMessages,
          );

          // Process delivered messages
          for (final newMsg in newMessagesList) {
            if (newMsg.status == 'delivered') {
              final savedSuccessfully =
                  await SqfliteHelper.insertDeliveredMessage(newMsg);
              if (savedSuccessfully) {
                await ChatService.deleteMessageFromAppwrite(newMsg.id);
              }
            }
          }

          if (mounted) {
            ref.read(messagesProvider.notifier).state = mergedMessages;
          }
        } else {
          // No new messages from Appwrite, but don't clear existing messages
          // Only load from SQLite if we have no messages at all
          if (currentMessages.isEmpty && mounted) {
            final offlineMessages = await SqfliteHelper.getDeliveredMessages(
              chatId,
            );
            if (!mounted) return;
            ref.read(messagesProvider.notifier).state = offlineMessages;
          }
          // If we have existing messages, keep them as they are
        }
      }
    } catch (e) {
      // On error, don't clear existing messages
      // Only load from SQLite if we have no messages at all
      if (!mounted) return;
      final chatId = ref.read(chatIdProvider);
      final currentMessages = ref.read(messagesProvider);

      if (chatId != null && currentMessages.isEmpty && mounted) {
        final offlineMessages = await SqfliteHelper.getDeliveredMessages(
          chatId,
        );
        if (!mounted) return;
        ref.read(messagesProvider.notifier).state = offlineMessages;
      }
    }
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

                        // Show only online/offline status or typing indicator
                        return Text(
                          isTyping
                              ? 'typing...'
                              : isContactOnline
                              ? 'Online'
                              : 'Offline',
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
                onPressed: () {
                  final msgsClear = SqfliteMsgsClear(
                    chatId: _chatId,
                    contactUid: widget.contact.uid,
                    ref: ref,
                    context: context,
                  );
                  msgsClear.showChatOptionsMenu();
                },
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
            if (message.imageId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: MessageImageBubble(fileId: message.imageId!),
              ),
            if (message.text.isNotEmpty &&
                (message.imageId == null || message.text != '📷 Image'))
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
            onPressed: () async {
              final imagePicker = await _pickImage(ImageSource.gallery);
              if (!imagePicker && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to upload image'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: () async {
              final imagePicker = await _pickImage(ImageSource.camera);
              if (!imagePicker && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to upload image'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
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

  Future<bool> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) return false;

    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);

    if (currentUserId == null || chatId == null || !mounted) return false;

    // Check internet connection
    final networkOnlineAsync = ref.read(networkConnectivityProvider);
    final hasInternet = networkOnlineAsync.value ?? true;
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    try {
      // Show uploading indicator if needed, but for now we proceed
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            backgroundColor: AppColors.primaryBlue,
          ),
        ),
      );
      final file = await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: image.path),
      );

      // Send message with imageId
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: widget.contact.uid,
        text: 'Image',
        imageId: file.$id,
      );

      if (messageDoc != null && mounted) {
        final newMessage = Message.fromJson(messageDoc.data);
        final currentMessages = ref.read(messagesProvider);

        if (!mounted) return true;
        if (mounted) {
          ref.read(messagesProvider.notifier).state = [
            newMessage,
            ...currentMessages,
          ];
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image uploaded successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }

        try {
          if (mounted) ref.invalidate(lastMessageProvider(widget.contact.uid));
        } catch (e) {}
      } else {
        // If message creation failed (messageDoc is null), we must still pop the dialog!
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send image message'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      return true;
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      debugPrint('Error uploading image: $e');
      return false;
    }
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

class MessageImageBubble extends ConsumerWidget {
  final String fileId;

  const MessageImageBubble({super.key, required this.fileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(imagePreviewProvider(fileId));

    return imageAsync.when(
      data: (data) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            Uint8List.fromList(data),
            width: 250,
            fit: BoxFit.cover,
          ),
        );
      },
      loading: () => Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
      error: (error, stack) => Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.error, color: Colors.grey)),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/pages/user_chats.dart';

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

  String? _currentUserId;
  String? _chatId;
  bool _wasOnline = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _initializeChat());
  }

  @override
  void dispose() {
    _messageController.dispose();
    messageSubscription?.cancel();
    typingSubscription?.cancel();

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
    ref.read(currentUserIdProvider.notifier).state = userId;

    if (userId == null) {
      ref.read(isLoadingStateProvider.notifier).state = false;
      return;
    }

    final chatId = ChatService.generateChatId(userId, widget.contact.uid);
    _chatId = chatId;
    ref.read(chatIdProvider.notifier).state = chatId;

    await _loadMessages();
    _subscribeToMessages();
    _subscribeToTyping();
    _checkUserPresence();
    _markMessagesAsRead();

    ref.read(isLoadingStateProvider.notifier).state = false;
  }

  // Load existing messages from database
  Future<bool> _loadMessages() async {
    try {
      final chatId = ref.read(chatIdProvider);
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
    final chatId = ref.read(chatIdProvider);
    if (chatId == null) return;

    try {
      messageSubscription = ChatService.subscribeToMessages(chatId, (response) {
        if (!mounted) return;
        try {
          final messageData = response.payload;
          final updatedMessage = Message.fromJson(messageData);
          final currentMessages = ref.read(messagesProvider);

          final existingIndex = currentMessages.indexWhere(
            (msg) => msg.id == updatedMessage.id,
          );

          if (existingIndex != -1) {
            final updatedMessages = [...currentMessages];
            updatedMessages[existingIndex] = updatedMessage;
            ref.read(messagesProvider.notifier).state = updatedMessages;
          } else {
            ref.read(messagesProvider.notifier).state = [
              updatedMessage,
              ...currentMessages,
            ];

            if (updatedMessage.receiverId == _currentUserId &&
                updatedMessage.status != 'read') {
              Future.delayed(const Duration(milliseconds: 100), () {
                ChatService.updateMessageStatus(updatedMessage.id, 'read');
              });
            }
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

  Future<void> _checkUserPresence() async {
    try {
      final presence = await ChatService.getUserPresence(widget.contact.uid);
      if (presence != null && mounted) {
        ref.read(isOnlineProvider.notifier).state =
            presence.data['online'] ?? false;
      }
    } catch (e) {}
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final messages = ref.read(messagesProvider);
      final currentUserId = ref.read(currentUserIdProvider);

      if (currentUserId == null) return;

      for (final message in messages) {
        if (message.receiverId == currentUserId && message.status != 'read') {
          await ChatService.updateMessageStatus(message.id, 'read');
        }
      }
    } catch (e) {}
  }

  Future<void> _sendMessage() async {
    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);

    if (_messageController.text.trim().isEmpty ||
        currentUserId == null ||
        chatId == null) {
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final sentMessage = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: widget.contact.uid,
        text: messageText,
      );

      if (sentMessage != null) {
        await ChatService.updateMessageStatus(sentMessage.$id, 'delivered');
      }

      await ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: false,
      );
    } catch (e) {}
  }

  void _onTypingChanged(String text) async {
    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);

    if (currentUserId == null || chatId == null) return;

    if (text.isNotEmpty) {
      await ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: true,
      );
    } else {
      await ChatService.setTyping(
        chatId: chatId,
        userId: currentUserId,
        isTyping: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to connectivity changes and pause/resume subscriptions
    final isOnlineAsync = ref.watch(networkConnectivityProvider); // true

    isOnlineAsync.whenData((isOnline) {
      if (isOnline != _wasOnline) {
        // false != true
        _wasOnline = isOnline; // false
        _handleConnectivityChange(isOnline);
      }
    });

    return Scaffold(
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
    );
  }

  void _handleConnectivityChange(bool isOnline) {
    if (isOnline) {
      messageSubscription?.resume();
      typingSubscription?.resume();
    } else {
      messageSubscription?.pause();
      typingSubscription?.pause();
    }
  }

  // Build header with contact info
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.1)),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
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
                    final networkOnlineAsync = ref.watch(
                      networkConnectivityProvider,
                    );
                    final networkOnline = networkOnlineAsync.value ?? true;

                    return Text(
                      !networkOnline
                          ? 'Waiting for network...'
                          : isTyping
                          ? 'typing...'
                          : isContactOnline
                          ? 'Online'
                          : 'Offline',
                      style: TextStyle(
                        color: !networkOnline
                            ? Colors.orange
                            : isTyping
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

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

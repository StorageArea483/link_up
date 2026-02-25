import 'dart:async';
import 'dart:developer';
import 'dart:io' as io;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/pages/user_chats.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'package:link_up/database/sqflite_helper.dart';
import 'package:link_up/widgets/images_storage/image_bubble.dart';
import 'package:link_up/widgets/audio_storage/audio_bubble.dart';
import 'package:link_up/database/sqflite_msgs_clear.dart';
import 'package:link_up/widgets/audio_storage/audio_messages.dart';
import 'package:link_up/widgets/images_storage/images_messages.dart';
import 'package:record/record.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/services/notification_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final UserContacts contact;
  const ChatScreen({super.key, required this.contact});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();

  StreamSubscription? messageSubscription;
  StreamSubscription? typingSubscription;
  StreamSubscription? presenceSubscription;

  String? _currentUserId;
  String? _chatId;
  late final AudioRecorder _record;
  final player = AudioPlayer();
  late final AudioMessagesHandler _audioHandler;

  bool _isTearingDown = false;

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

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    // Initialize audio components immediately (synchronously)
    _record = AudioRecorder();
    _audioHandler = AudioMessagesHandler(
      ref: ref,
      context: context,
      record: _record,
      player: player,
      contact: widget.contact,
    );

    // Set up audio player listeners
    player.positionStream.listen((p) {
      if (mounted) {
        if (!_audioHandler.shouldBlockUpdates) {
          ref.read(positionProvider.notifier).state = p;
        }
      }
    });
    player.durationStream.listen((d) {
      if (mounted && d != null) {
        if (!_audioHandler.shouldBlockUpdates) {
          ref.read(durationProvider.notifier).state = d;
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _isTearingDown = true;

    _messageController.dispose();
    messageSubscription?.cancel();
    typingSubscription?.cancel();
    presenceSubscription?.cancel();

    try {
      if (_currentUserId != null && _chatId != null) {
        ChatService.setTyping(
          chatId: _chatId!,
          userId: _currentUserId!,
          isTyping: false,
        );
      }
    } catch (e) {
      // Silent cleanup failure - disposal should not be prevented
    }

    try {
      _record.dispose();
      _audioHandler.dispose();
    } catch (e) {
      // Silent cleanup failure - disposal should not be prevented
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
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
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
      messageSubscription?.cancel();
      typingSubscription?.cancel();
      presenceSubscription?.cancel();

      // Set subscriptions to null so they can be re-established if needed
      messageSubscription = null;
      typingSubscription = null;
      presenceSubscription = null;
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._handleAppDetached: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _handleAppResumed() async {
    try {
      if (!mounted || _currentUserId == null || _chatId == null) return;
      // Re-establish or resume each subscription
      if (messageSubscription == null) {
        _subscribeToMessages();
      } else if (messageSubscription!.isPaused) {
        messageSubscription!.resume();
      }

      if (typingSubscription == null) {
        _subscribeToTyping();
      } else if (typingSubscription!.isPaused) {
        typingSubscription!.resume();
      }

      if (presenceSubscription == null) {
        _subscribeToPresence();
      } else if (presenceSubscription!.isPaused) {
        presenceSubscription!.resume();
      }

      // Refresh provider state by invalidating relevant providers
      if (mounted) {
        ref.invalidate(unreadCountProvider(widget.contact.uid));
        ref.invalidate(lastMessageProvider(widget.contact.uid));
      }

      // Check for new messages and update providers
      await _markMessagesAsDeliveredAndUpdate(_currentUserId!);

      // Check contact's current presence
      await _checkUserPresence();
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._handleAppResumed: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to restore chat connections. Please restart the app.',
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
      messageSubscription?.pause();
      typingSubscription?.pause();
      presenceSubscription?.pause();
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._handleAppPaused: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _initializeChat() async {
    try {
      if (mounted) {
        ref.read(navigationProvider.notifier).state = 'chat';
      }
      if (!mounted) return;
      final userId = FirebaseAuth.instance.currentUser?.uid;
      _currentUserId = userId;

      if (!mounted) return;
      ref.read(currentUserIdProvider.notifier).state = userId;

      if (userId == null) {
        if (mounted) {
          ref.read(isLoadingChatScreenProvider.notifier).state = false;
        }
        return;
      }

      final chatId = ChatService.generateChatId(userId, widget.contact.uid);
      _chatId = chatId;

      if (!mounted) return;
      ref.read(chatIdProvider.notifier).state = chatId;

      // Check if we already have messages for this chat
      final cachedMessages = ref.read(messagesProvider(chatId));
      // Only show loading if we don't have cached messages
      if (cachedMessages.isEmpty && mounted) {
        ref.read(isLoadingChatScreenProvider.notifier).state = true;
      } else {
        if (!mounted) return;
        ref.read(isLoadingChatScreenProvider.notifier).state = false;
      }

      // Set current user as online
      try {
        await ChatService.updatePresence(userId: userId, online: true);
      } catch (e) {
        // Continue initialization even if presence update fails
      }

      // Load messages (will update cache if needed)
      await _loadMessages();

      // Set up subscriptions
      _subscribeToMessages();
      _subscribeToTyping();
      _subscribeToPresence();

      // Check contact's presence
      await _checkUserPresence();

      // Mark messages as delivered
      await _markMessagesAsDeliveredAndUpdate(userId);
    } catch (e) {
      if (mounted) {
        ref.read(isLoadingChatScreenProvider.notifier).state = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to initialize chat. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markMessagesAsDeliveredAndUpdate(String userId) async {
    try {
      // update the message status because receiver has come online
      if (!mounted) return;
      final chatId = ref.read(chatIdProvider);
      if (chatId == null || !mounted) return;
      if (!mounted) return;
      ref.invalidate(unreadCountProvider(widget.contact.uid));
      if (!mounted) return;
      ref.invalidate(lastMessageProvider(widget.contact.uid));

      final updatedMessages = await ChatService.markMessagesAsDelivered(
        chatId: chatId,
        receiverId: userId, // receive messages meant for this user
      );

      if (updatedMessages.isNotEmpty && mounted) {
        // Get current messages from the UI
        if (!mounted) return;
        final currentMessages = ref.read(messagesProvider(chatId));
        final updatedMessagesList = [...currentMessages];

        // Process each updated message
        for (final updatedMessage in updatedMessages) {
          final fullData = {'\$id': updatedMessage.$id, ...updatedMessage.data};
          final updatedMsg = Message.fromJson(fullData);

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

          // Handle the delivered message (save locally, download if image, delete from cloud)
          await _handleDeliveredMessage(updatedMsg);
        }

        // Sort by creation time (newest first) to maintain order
        updatedMessagesList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Update the UI with the new message list
        if (!mounted) return;
        ref.read(messagesProvider(chatId).notifier).state = updatedMessagesList;
      } else if (mounted) {
        // No new delivered messages, but ensure we have offline messages loaded
        final currentMessages = ref.read(messagesProvider(chatId));
        if (currentMessages.isEmpty) {
          try {
            final offlineMessages = await SqfliteHelper.getDeliveredMessages(
              chatId,
            );
            if (!mounted) return;
            ref.read(messagesProvider(chatId).notifier).state = offlineMessages;
          } catch (e) {
            // Silent failure - offline messages will be loaded on demand
          }
        }
      }
    } catch (e) {
      // On error, ensure we still have offline messages if current list is empty
      if (mounted) {
        final chatId = ref.read(chatIdProvider);
        if (chatId != null) {
          final currentMessages = ref.read(messagesProvider(chatId));
          if (currentMessages.isEmpty) {
            try {
              final offlineMessages = await SqfliteHelper.getDeliveredMessages(
                chatId,
              );
              if (!mounted) return;
              ref.read(messagesProvider(chatId).notifier).state =
                  offlineMessages;
            } catch (e) {
              // Silent fallback failure
            }
          }
        }
      }
    }
  }

  Future<bool> _loadMessages() async {
    try {
      if (!mounted) return false;
      final chatId = ref.read(chatIdProvider);
      if (chatId == null) return false;

      // Check if we already have messages for this chat
      if (!mounted) return false;
      final currentMessages = ref.read(messagesProvider(chatId));

      // If messagesProvider already has messages, we're good
      if (currentMessages.isNotEmpty) {
        // Still fetch from database in background to update if needed
        final offlineMessages = await SqfliteHelper.getDeliveredMessages(
          chatId,
        );
        final isOnline = await ref.watch(networkConnectivityProvider.future);

        if (isOnline) {
          final docs = await ChatService.getMessages(chatId);
          final sentMessages = docs.documents
              .map((doc) => Message.fromJson({'\$id': doc.$id, ...doc.data}))
              .toList();

          // Merge and update
          final allMessages = _mergeMessages(sentMessages, offlineMessages);
          if (mounted) {
            ref.read(messagesProvider(chatId).notifier).state = allMessages;
            ref.read(isLoadingChatScreenProvider.notifier).state = false;
          }
        }
        return true;
      }

      // No messages in provider, load from SQLite first
      final offlineMessages = await SqfliteHelper.getDeliveredMessages(chatId);
      final isOnline = await ref.watch(networkConnectivityProvider.future);
      if (!mounted) return false;

      if (!isOnline && offlineMessages.isEmpty) {
        // No messages anywhere
        if (mounted) {
          ref.read(messagesProvider(chatId).notifier).state = [];
          ref.read(isLoadingChatScreenProvider.notifier).state = false;
        }
        return false;
      }

      if (!isOnline && offlineMessages.isNotEmpty) {
        // Offline but has SQLite messages
        if (mounted) {
          ref.read(messagesProvider(chatId).notifier).state = offlineMessages;
          ref.read(isLoadingChatScreenProvider.notifier).state = false;
        }
        return true;
      }
      // Online - fetch from Appwrite
      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final sentMessages = docs.documents
            .map((doc) => Message.fromJson(doc.data))
            .toList();

        final allMessages = _mergeMessages(sentMessages, offlineMessages);

        // Save all fetched messages to SQLite for persistence
        for (final msg in sentMessages) {
          try {
            await SqfliteHelper.insertMessage(msg);
          } catch (e) {
            // Continue with other messages even if one fails
          }
        }
        if (mounted) {
          ref.read(messagesProvider(chatId).notifier).state = allMessages;
          ref.read(isLoadingChatScreenProvider.notifier).state = false;
        }
        return true;
      }
    } catch (e) {
      if (!mounted) return false;
      final chatId = ref.read(chatIdProvider);
      if (chatId == null) return false;
      // Load from SQLite as fallback
      if (mounted) {
        try {
          final offlineMessages = await SqfliteHelper.getDeliveredMessages(
            chatId,
          );
          if (mounted) {
            ref.read(messagesProvider(chatId).notifier).state = offlineMessages;
            ref.read(isLoadingChatScreenProvider.notifier).state = false;
          }
        } catch (e) {
          if (mounted) {
            ref.read(isLoadingChatScreenProvider.notifier).state = false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to load messages. Please check your connection.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
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
      messageSubscription?.cancel();

      messageSubscription = ChatService.subscribeToMessages(chatId, (response) {
        if (_isTearingDown || !mounted) return;
        try {
          final newMessage = Message.fromJson(response.payload);

          if (_isTearingDown || !mounted) return;
          final currentMessages = ref.read(messagesProvider(chatId));

          // Check if this is an update to an existing message or a new message
          final existingIndex = currentMessages.indexWhere(
            (msg) => msg.id == newMessage.id,
          );

          if (existingIndex != -1) {
            final updatedMessages = [...currentMessages];
            updatedMessages[existingIndex] = newMessage;
            if (_isTearingDown || !mounted) return;
            ref.read(messagesProvider(chatId).notifier).state = updatedMessages;

            if (newMessage.status == 'delivered') {
              _handleDeliveredMessage(newMessage);
            }
          } else {
            // New message received
            if (_isTearingDown || !mounted) return;
            ref.read(messagesProvider(chatId).notifier).state = [
              newMessage,
              ...currentMessages,
            ];

            // IMPORTANT: Auto-mark as delivered if receiver is online and in chat
            if (newMessage.status == 'sent' &&
                newMessage.receiverId == _currentUserId &&
                mounted) {
              // Mark this specific message as delivered
              try {
                _markSingleMessageAsDelivered(newMessage.id);
              } catch (e, stack) {
                log(
                  'ERROR in _ChatScreenState._subscribeToMessages markSingleMessageAsDelivered: $e\nSTACK: $stack',
                  name: 'DEBUG_SUBSCRIPTION',
                  error: e,
                  stackTrace: stack,
                );
              }
            }

            if (newMessage.status == 'delivered') {
              _handleDeliveredMessage(newMessage);
            }
          }
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._subscribeToMessages callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._subscribeToMessages: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
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

  Future<void> _handleDeliveredMessage(Message message) async {
    try {
      // 1. ALWAYS save to SQLite for BOTH sender and receiver when a message is delivered
      // This is crucial because images/audio are deleted from Appwrite after delivery
      if (message.status == 'delivered') {
        try {
          await SqfliteHelper.insertMessage(message);
        } catch (e) {
          // Silent failure - message saving is not critical for UI functionality
        }
      }

      // 2. Only the receiver handles downloading files and deleting from cloud
      if (message.receiverId == _currentUserId) {
        // Handle image messages
        if (message.imageId != null) {
          await _handleImageDelivery(message);
        }

        // Handle audio messages
        if (message.audioId != null) {
          await _handleAudioDelivery(message);
        }
      }
    } catch (e) {
      // Silent failure - message delivery handling is not critical for UI
    }
  }

  Future<void> _handleImageDelivery(Message message) async {
    try {
      // 1. Get document directory
      final dir = await getApplicationDocumentsDirectory();

      // 2. Create the custom directory structure: LinkUp storage/Images
      final storageDir = io.Directory('${dir.path}/LinkUp storage/Images');
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      final savePath = '${storageDir.path}/${message.imageId}.jpg';
      final localImageFile = io.File(savePath);

      // Check if image already exists locally
      if (await localImageFile.exists()) {
        // Image already exists, update provider and cleanup cloud storage
        if (mounted) {
          ref
                  .read(localFileProvider((message.imageId!, _chatId)).notifier)
                  .state =
              localImageFile;
          ref
                  .read(
                    imageLoadingStateProvider((
                      message.imageId!,
                      _chatId,
                    )).notifier,
                  )
                  .state =
              false;
        }

        try {
          // Delete image from Appwrite Storage
          await storage.deleteFile(
            bucketId: bucketId,
            fileId: message.imageId!,
          );
          // Delete message document from Appwrite Database
          await ChatService.deleteMessageFromAppwrite(message.id);
        } catch (e) {
          // Silent cleanup failure - not critical for user experience
        }
        return;
      }

      final imageUrl =
          'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/${message.imageId}/view?project=697035fd003aa22ae623';

      // 3. Download the image (only if it doesn't exist)
      try {
        await Dio().download(imageUrl, savePath);
      } catch (e) {
        // Set loading to false on download error
        if (mounted) {
          ref
                  .read(
                    imageLoadingStateProvider((
                      message.imageId!,
                      _chatId,
                    )).notifier,
                  )
                  .state =
              false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to download image. Please check your connection.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 4. CRITICAL: Update provider after successful download
      if (mounted) {
        ref
                .read(localFileProvider((message.imageId!, _chatId)).notifier)
                .state =
            localImageFile;
        ref
                .read(
                  imageLoadingStateProvider((
                    message.imageId!,
                    _chatId,
                  )).notifier,
                )
                .state =
            false;
      }

      // 5. Save downloaded image to device gallery (only once)
      try {
        await Gal.putImage(savePath, album: 'LinkUp');

        // Delete image from Appwrite Storage
        await storage.deleteFile(bucketId: bucketId, fileId: message.imageId!);
        // Delete message document from Appwrite Database
        await ChatService.deleteMessageFromAppwrite(message.id);
      } catch (e) {
        // Silent cleanup failure - not critical for user experience
      }
    } catch (e) {
      // Set loading to false even on error
      if (mounted) {
        ref
                .read(
                  imageLoadingStateProvider((
                    message.imageId!,
                    _chatId,
                  )).notifier,
                )
                .state =
            false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to process image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleAudioDelivery(Message message) async {
    try {
      // 1. Get document directory
      final dir = await getApplicationDocumentsDirectory();

      // 2. Create the custom directory structure: LinkUp storage/Audio
      final storageDir = io.Directory('${dir.path}/LinkUp storage/Audio');
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      final savePath = '${storageDir.path}/${message.audioId}.m4a';

      // Check if audio already exists locally
      if (await io.File(savePath).exists()) {
        // Audio already exists, update provider and cleanup cloud storage
        if (mounted) {
          final audioFile = io.File(savePath);
          ref
                  .read(
                    localAudioFileProvider((
                      message.audioId!,
                      _chatId,
                    )).notifier,
                  )
                  .state =
              audioFile;
          ref
                  .read(
                    audioLoadingStateProvider((
                      message.audioId!,
                      _chatId,
                    )).notifier,
                  )
                  .state =
              false;
          // Reset error state
          ref
                  .read(
                    audioErrorProvider((message.audioId!, _chatId)).notifier,
                  )
                  .state =
              false;
        }

        try {
          // Delete audio from Appwrite Storage
          await storage.deleteFile(
            bucketId: bucketId,
            fileId: message.audioId!,
          );

          // Delete message document from Appwrite Database
          await ChatService.deleteMessageFromAppwrite(message.id);
        } catch (e) {
          // Silent cleanup failure - not critical for user experience
        }
        return;
      }

      final audioUrl =
          'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/${message.audioId}/view?project=697035fd003aa22ae623';

      // 3. Download the audio (only if it doesn't exist)
      try {
        await Dio().download(audioUrl, savePath);
      } catch (e) {
        // Set loading to false and error to true on download failure
        if (mounted) {
          ref
                  .read(
                    audioLoadingStateProvider((
                      message.audioId!,
                      _chatId,
                    )).notifier,
                  )
                  .state =
              false;
          ref
                  .read(
                    audioErrorProvider((message.audioId!, _chatId)).notifier,
                  )
                  .state =
              true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to download audio. Please check your connection.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 4. CRITICAL: Update provider after successful download
      if (mounted) {
        final audioFile = io.File(savePath);
        ref
                .read(
                  localAudioFileProvider((message.audioId!, _chatId)).notifier,
                )
                .state =
            audioFile;
        ref
                .read(
                  audioLoadingStateProvider((
                    message.audioId!,
                    _chatId,
                  )).notifier,
                )
                .state =
            false;
        // Reset error state on successful download
        ref
                .read(audioErrorProvider((message.audioId!, _chatId)).notifier)
                .state =
            false;
      }

      // 5. Cleanup cloud storage after successful download
      try {
        // Delete audio from Appwrite Storage
        await storage.deleteFile(bucketId: bucketId, fileId: message.audioId!);

        // Delete message document from Appwrite Database
        await ChatService.deleteMessageFromAppwrite(message.id);
      } catch (e) {
        // Silent cleanup failure - not critical for user experience
      }
    } catch (e) {
      // Set loading to false and error to true on failure
      if (mounted) {
        ref
                .read(
                  audioLoadingStateProvider((
                    message.audioId!,
                    _chatId,
                  )).notifier,
                )
                .state =
            false;
        ref
                .read(audioErrorProvider((message.audioId!, _chatId)).notifier)
                .state =
            true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to process audio. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Mark a single specific message as delivered (for real-time auto-delivery)
  Future<void> _markSingleMessageAsDelivered(String messageId) async {
    try {
      if (!mounted) return;
      final chatId = ref.read(chatIdProvider);
      if (chatId == null || _currentUserId == null || !mounted) return;

      // Update the specific message status to 'delivered'
      final updatedMessage = await ChatService.updateMessageStatus(
        messageId,
        'delivered',
      );

      if (updatedMessage != null && mounted) {
        // Update the UI immediately
        if (!mounted) return;
        final fullData = {'\$id': updatedMessage.$id, ...updatedMessage.data};
        final currentMessages = ref.read(messagesProvider(chatId));
        final updatedMessagesList = [...currentMessages];

        final updatedMsg = Message.fromJson(fullData);
        final index = updatedMessagesList.indexWhere(
          (msg) => msg.id == updatedMsg.id,
        );

        if (index != -1) {
          updatedMessagesList[index] = updatedMsg;
          if (!mounted) return;
          ref.read(messagesProvider(chatId).notifier).state =
              updatedMessagesList;

          // Handle the delivered message (save to SQLite and delete from Appwrite)
          await _handleDeliveredMessage(updatedMsg);
        }
      }
    } catch (e) {
      // Silent failure - message delivery status update is not critical for UI
    }
  }

  void _subscribeToTyping() {
    try {
      if (!mounted) return;

      final chatId = ref.read(chatIdProvider);
      final currentUserId = ref.read(currentUserIdProvider);
      if (chatId == null) return;
      typingSubscription?.cancel();

      typingSubscription = ChatService.subscribeToTyping(chatId, (response) {
        if (!mounted) return;
        try {
          if (response.payload['userId'] != currentUserId) {
            if (!mounted) return;
            ref.read(isTypingProvider(chatId).notifier).state =
                response.payload['isTyping'] ?? false;
          }
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._subscribeToTyping callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._subscribeToTyping: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _subscribeToPresence() {
    try {
      if (!mounted) return;
      presenceSubscription?.cancel();

      presenceSubscription = ChatService.subscribeToPresence(widget.contact.uid, (
        response,
      ) {
        if (!mounted) return;
        try {
          final isOnline =
              response.payload['online'] ??
              false; // checking the receiver status
          if (!mounted) return;
          final wasOnlineBefore = ref.read(isOnlineProvider(_chatId!));

          // Now update the provider with the NEW status
          if (!mounted) return;
          ref.read(isOnlineProvider(_chatId!).notifier).state =
              isOnline; // provider for updating the receiver online/offline status

          // Detect transition: Contact just came online (was offline, now online)
          // This is when we mark messages as delivered
          if (isOnline &&
              !wasOnlineBefore && // Was offline before, now online = transition detected!
              _currentUserId != null &&
              _chatId != null) {
            // Contact just came online, mark their messages as delivered
            try {
              _markMessagesAsDeliveredAndUpdate(widget.contact.uid);
            } catch (e, stack) {
              log(
                'ERROR in _ChatScreenState._subscribeToPresence markMessagesAsDeliveredAndUpdate: $e\nSTACK: $stack',
                name: 'DEBUG_SUBSCRIPTION',
                error: e,
                stackTrace: stack,
              );
            }
          }
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._subscribeToPresence callback: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      });
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._subscribeToPresence: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _checkUserPresence() async {
    try {
      final presence = await ChatService.getUserPresence(widget.contact.uid);
      // checking the presence of the receiver
      if (mounted) {
        // If no presence record exists, assume user is offline
        final isOnline = presence?.data['online'] ?? false;

        ref.read(isOnlineProvider(_chatId!).notifier).state =
            isOnline; // provider for updating the online/offline status of the other user
      }
    } catch (e) {
      // On error, assume user is offline
      if (mounted) {
        ref.read(isOnlineProvider(_chatId!).notifier).state = false;
      }
    }
  }

  Future<void> _sendMessage() async {
    try {
      if (!mounted) return;

      final currentUserId = ref.read(currentUserIdProvider);
      final chatId = ref.read(chatIdProvider);
      final networkOnlineAsync = ref.read(networkConnectivityProvider);
      final hasInternet = networkOnlineAsync.value ?? true;
      final recordingPath = ref.read(recordingPathProvider);

      // Check if there's an audio recording to send
      if (recordingPath != null) {
        // Send audio message
        try {
          await _audioHandler.sendAudioMessage();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to send audio message. Please try again.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        return;
      }

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
              content: Text(
                'Unable to send message. Please check your internet connection and try again.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final messageText = _messageController.text.trim();
      _messageController.clear();

      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: widget.contact.uid,
        text: messageText,
      );

      // Immediately add the message to the UI
      if (messageDoc != null && mounted) {
        final fullData = {
          '\$id': messageDoc.$id, // ← inject $id manually
          ...messageDoc.data, // ← spread the rest of the fields
        };
        final newMessage = Message.fromJson(
          fullData,
        ); // message with status sent gets added in appwrite db
        final currentMessages = ref.read(messagesProvider(chatId));
        if (!mounted) return;
        ref.read(messagesProvider(chatId).notifier).state = [
          newMessage,
          ...currentMessages,
        ];

        // NEW: Save the sent message to SQLite immediately
        try {
          await SqfliteHelper.insertMessage(newMessage);
        } catch (e) {
          // Silent failure - message saving is not critical for UI functionality
        }

        // Send push notification when message status is "sent"
        if (newMessage.status == 'sent') {
          try {
            _sendPushNotificationToReceiver(newMessage);
          } catch (e) {
            // Silent failure - push notification failure is not critical for message sending
          }
        }

        try {
          if (!mounted) return;
          ref.invalidate(lastMessageProvider(widget.contact.uid));
        } catch (e) {
          // Silent failure - provider invalidation is not critical
        }
      } else if (mounted) {
        // Message failed to send
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      try {
        await ChatService.setTyping(
          chatId: chatId,
          userId: currentUserId,
          isTyping: false,
        );
      } catch (e) {
        // Silent failure - typing status cleanup is not critical
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to send message. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Send push notification to receiver when message is sent
  Future<void> _sendPushNotificationToReceiver(Message message) async {
    try {
      final receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.contact.uid)
          .get();

      if (!receiverDoc.exists) {
        return;
      }

      final receiverData = receiverDoc.data();
      final receiverToken = receiverData?['fcmToken'] as String?;

      if (receiverToken == null || receiverToken.isEmpty) {
        return;
      }
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!senderDoc.exists) {
        return;
      }

      final senderName = widget.contact.name;
      final notificationService = NotificationService();

      // Determine the message body based on message type
      String notificationBody;
      if (message.imageId != null) {
        notificationBody = '📷 Photo';
      } else if (message.audioId != null) {
        notificationBody = '🎵 Voice message';
      } else if (message.text.isNotEmpty) {
        notificationBody = message.text;
      } else {
        notificationBody = 'Sent a message';
      }
      if (message.status == 'delivered') {
        return;
      }
      await notificationService.sendPushNotification(
        deviceToken: receiverToken,
        title: senderName,
        body: notificationBody,
        messageStatus: message.status,
      );
    } catch (e) {
      // Silent failure - push notification failure is not critical for message sending
    }
  }

  void _onTypingChanged(String text) {
    try {
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
    } catch (e) {
      // Silent failure - typing status update is not critical
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // Listen to network connectivity changes only when necessary
        ref.listen<AsyncValue<bool>>(networkConnectivityProvider, (
          previous,
          next,
        ) {
          if (!mounted) return;

          // Only handle connectivity changes if both previous and next have values
          if (previous?.hasValue == true && next.hasValue) {
            final wasOnline = previous!.value!;
            final isOnline = next.value!;

            // Only trigger connectivity change if there's an actual change
            if (wasOnline != isOnline) {
              _handleConnectivityChange(isOnline);
            }
          }
        });

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const CheckConnection(
                  child: CheckConnection(child: LandingPage()),
                ),
              ),
            );
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildMessagesList()),
                  _buildInputSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleConnectivityChange(bool isOnline) async {
    try {
      if (_currentUserId == null || !mounted) return;

      if (isOnline) {
        // Only try to resume if subscriptions exist and are paused
        if (messageSubscription != null) {
          try {
            messageSubscription?.resume();
          } catch (e, stack) {
            log(
              'ERROR in _ChatScreenState._handleConnectivityChange messageSubscription resume: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
            // If resume fails, re-establish
            _subscribeToMessages();
          }
        } else {
          _subscribeToMessages();
        }

        if (typingSubscription != null) {
          try {
            typingSubscription?.resume();
          } catch (e, stack) {
            log(
              'ERROR in _ChatScreenState._handleConnectivityChange typingSubscription resume: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
            // If resume fails, re-establish
            _subscribeToTyping();
          }
        } else {
          _subscribeToTyping();
        }

        if (presenceSubscription != null) {
          try {
            presenceSubscription?.resume();
          } catch (e, stack) {
            log(
              'ERROR in _ChatScreenState._handleConnectivityChange presenceSubscription resume: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
            // If resume fails, re-establish
            _subscribeToPresence();
          }
        } else {
          _subscribeToPresence();
        }

        // Update presence to online and mark messages as delivered with UI update
        try {
          ChatService.updatePresence(userId: _currentUserId!, online: true);
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._handleConnectivityChange updatePresence: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }

        if (!mounted) return;
        ref.read(isOnlineProvider(_chatId!).notifier).state = true;
        final chatId = ref.read(chatIdProvider);
        if (chatId != null) {
          try {
            _markMessagesAsDeliveredAndUpdate(_currentUserId!);
          } catch (e, stack) {
            log(
              'ERROR in _ChatScreenState._handleConnectivityChange markMessagesAsDeliveredAndUpdate: $e\nSTACK: $stack',
              name: 'DEBUG_SUBSCRIPTION',
              error: e,
              stackTrace: stack,
            );
          }
        }

        // Restore messages first if provider is empty
        if (!mounted) return;
        if (chatId != null) {
          final currentMessages = ref.read(messagesProvider(chatId));
          if (currentMessages.isEmpty && mounted) {
            // Load from SQLite as fallback
            try {
              final offlineMessages = await SqfliteHelper.getDeliveredMessages(
                chatId,
              );
              if (mounted) {
                ref.read(messagesProvider(chatId).notifier).state =
                    offlineMessages;
              }
            } catch (e, stack) {
              log(
                'ERROR in _ChatScreenState._handleConnectivityChange getDeliveredMessages: $e\nSTACK: $stack',
                name: 'DEBUG_SUBSCRIPTION',
                error: e,
                stackTrace: stack,
              );
            }
          }
        }

        // Then reload to get latest messages from server
        try {
          _reloadMessagesAfterReconnection();
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._handleConnectivityChange reloadMessagesAfterReconnection: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }

        try {
          _checkUserPresence();
        } catch (e, stack) {
          log(
            'ERROR in _ChatScreenState._handleConnectivityChange checkUserPresence: $e\nSTACK: $stack',
            name: 'DEBUG_SUBSCRIPTION',
            error: e,
            stackTrace: stack,
          );
        }
      } else {
        // Going offline - pause subscriptions to save resources
        messageSubscription?.pause();
        typingSubscription?.pause();
        presenceSubscription?.pause();

        if (mounted) {
          ref.read(isOnlineProvider(_chatId!).notifier).state =
              false; // update the receiver online status to offline
        }
      }
    } catch (e, stack) {
      log(
        'ERROR in _ChatScreenState._handleConnectivityChange: $e\nSTACK: $stack',
        name: 'DEBUG_SUBSCRIPTION',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connection issue detected. Some features may be limited.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _reloadMessagesAfterReconnection() async {
    try {
      if (!mounted) return;

      final chatId = ref.read(chatIdProvider);
      if (chatId == null) return;

      // Get current messages to preserve them
      if (!mounted) return;
      final currentMessages = ref.read(messagesProvider(chatId));

      // Step 1: Fetch latest messages from Appwrite
      final docs = await ChatService.getMessages(chatId);
      if (mounted) {
        final newMessagesList = docs.documents
            .map((doc) => Message.fromJson({'\$id': doc.$id, ...doc.data}))
            .toList();

        // Step 2: Merge messages intelligently using helper method
        if (newMessagesList.isNotEmpty) {
          // Merge new messages with existing ones
          final mergedMessages = _mergeMessages(
            newMessagesList,
            currentMessages,
          );

          // Process messages from Appwrite
          for (final newMsg in newMessagesList) {
            // Save to SQLite for local persistence
            try {
              await SqfliteHelper.insertMessage(newMsg);
            } catch (e) {
              log(
                'Failed to save message to SQLite during reload: $e',
                name: 'ChatScreen',
              );
            }

            // If it's a delivered message, clean up from Appwrite
            if (newMsg.status == 'delivered') {
              try {
                await ChatService.deleteMessageFromAppwrite(newMsg.id);
              } catch (e) {
                log(
                  'Failed to delete delivered message from Appwrite: $e',
                  name: 'ChatScreen',
                );
              }
            }
          }

          if (mounted) {
            ref.read(messagesProvider(chatId).notifier).state = mergedMessages;
          }
        } else {
          // No new messages from Appwrite, but don't clear existing messages
          // Only load from SQLite if we have no messages at all
          if (currentMessages.isEmpty && mounted) {
            try {
              final offlineMessages = await SqfliteHelper.getDeliveredMessages(
                chatId,
              );
              if (!mounted) return;
              ref.read(messagesProvider(chatId).notifier).state =
                  offlineMessages;
            } catch (e) {
              log(
                'Failed to load offline messages during reload: $e',
                name: 'ChatScreen',
              );
            }
          }
          // If we have existing messages, keep them as they are
        }
      }
    } catch (e) {
      log(
        'Failed to reload messages after reconnection: $e',
        name: 'ChatScreen',
      );
      // On error, don't clear existing messages
      // Only load from SQLite if we have no messages at all
      if (!mounted) return;
      final chatId = ref.read(chatIdProvider);
      final currentMessages = ref.read(messagesProvider(chatId ?? ''));

      if (chatId != null && currentMessages.isEmpty && mounted) {
        try {
          final offlineMessages = await SqfliteHelper.getDeliveredMessages(
            chatId,
          );
          if (!mounted) return;
          ref.read(messagesProvider(chatId).notifier).state = offlineMessages;
        } catch (e) {
          log(
            'Failed to load offline messages as fallback during reload: $e',
            name: 'ChatScreen',
          );
        }
      }
    }
  }

  // Build header with contact info
  Widget _buildHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                  MaterialPageRoute(
                    builder: (context) =>
                        const CheckConnection(child: UserChats()),
                  ),
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contact.name,
                      style: AppTextStyles.button.copyWith(fontSize: 16),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final chatId = ref.watch(chatIdProvider) ?? _chatId;
                        if (chatId == null) {
                          return const SizedBox.shrink();
                        }

                        final isTyping = ref.watch(isTypingProvider(chatId));
                        final isContactOnline = ref.watch(
                          isOnlineProvider(chatId),
                        );

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
                  final chatId = ref.read(chatIdProvider);
                  final msgsClear = SqfliteMsgsClear(
                    chatId: chatId,
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
    final isLoading = ref.watch(isLoadingChatScreenProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final chatId = ref.watch(chatIdProvider);

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    if (currentUserId == null || chatId == null) {
      return const Center(
        child: Text('Unable to load messages', style: AppTextStyles.footer),
      );
    }

    final messages = ref.watch(messagesProvider(chatId));
    final networkOnlineAsync = ref.watch(networkConnectivityProvider);
    final isOnline = networkOnlineAsync.value ?? true;

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnline
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 64,
              color: AppColors.textFooter,
            ),
            const SizedBox(height: 16),
            Text(
              isOnline ? 'No messages yet' : 'No internet connection',
              style: AppTextStyles.footer,
            ),
            const SizedBox(height: 8),
            Text(
              isOnline
                  ? 'Send a message to start chatting'
                  : 'Connect to the internet to load messages',
              style: const TextStyle(fontSize: 12, color: AppColors.textFooter),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isSentByMe = message.isSentByMe(currentUserId);
        return _buildMessageBubble(message, isSentByMe);
      },
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ImageBubble(
                  imageId: message.imageId!,
                  chatId:
                      _chatId ??
                      (_currentUserId != null
                          ? ChatService.generateChatId(
                              _currentUserId!,
                              widget.contact.uid,
                            )
                          : null),
                ),
              )
            else if (message.audioId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: AudioBubble(
                  audioId: message.audioId!,
                  isSentByMe: isSentByMe,
                  chatId:
                      _chatId ??
                      (_currentUserId != null
                          ? ChatService.generateChatId(
                              _currentUserId!,
                              widget.contact.uid,
                            )
                          : null),
                ),
              ),
            if (message.text.isNotEmpty &&
                (message.imageId == null || message.text != 'Image') &&
                (message.audioId == null || message.text != 'Audio'))
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Audio preview widget
          AudioPreviewWidget(handler: _audioHandler),
          // Input Row
          Row(
            children: [
              // Image input buttons
              ImageInputButtons(contact: widget.contact),
              // Audio recording button
              AudioRecordingButton(
                currentUserId: _currentUserId,
                handler: _audioHandler,
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
                  child: Consumer(
                    builder: (context, ref, _) {
                      final toggleRecording = ref.watch(
                        toggleRecordingProvider,
                      );
                      final recordingPath = ref.watch(recordingPathProvider);
                      return TextField(
                        controller: _messageController,
                        onChanged: _onTypingChanged,
                        decoration: InputDecoration(
                          hintText: toggleRecording
                              ? 'Recording...'
                              : recordingPath != null
                              ? 'Voice message ready'
                              : 'Type a message...',
                          border: InputBorder.none,
                          hintStyle: AppTextStyles.footer,
                        ),
                        maxLines: null,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Consumer(
                builder: (context, ref, _) {
                  return CircleAvatar(
                    backgroundColor: AppColors.primaryBlue,
                    radius: 24,
                    child: ref.watch(isLoadingChatScreenProvider)
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

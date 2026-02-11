import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/database/sqflite_helper.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/services/chat_service.dart';

// Loading state provider
final isLoadingStateProvider = StateProvider<bool>((ref) => true);

final isLoadingChatScreenProvider = StateProvider<bool>((ref) => true);

// Messages list provider
final messagesProvider = StateProvider.family<List<Message>, String>(
  (ref, chatId) => [],
);

// Typing indicator provider
final isTypingProvider = StateProvider<bool>((ref) => false);

// Online status provider
final isOnlineProvider = StateProvider<bool>((ref) => false);

// Current user ID provider
final currentUserIdProvider = StateProvider<String?>((ref) => null);

// Chat ID provider
final chatIdProvider = StateProvider<String?>((ref) => null);

// Local File provider (Family: imageId) - Each image has its own file state
// Using keepAlive to prevent state from being disposed when widget is removed
final localFileProvider = StateProvider.family<File?, (String, String?)>(
  (ref, params) => null,
);

// Loading state provider (Family: imageId) - Each image has its own loading state
final imageLoadingStateProvider = StateProvider.family<bool, (String, String?)>(
  (ref, params) => true,
);

// Local Audio File provider (Family: audioId) - Each audio has its own file state
final localAudioFileProvider = StateProvider.family<File?, (String, String?)>(
  (ref, params) => null,
);

// Audio Loading state provider (Family: audioId) - Each audio has its own loading state
final audioLoadingStateProvider = StateProvider.family<bool, (String, String?)>(
  (ref, params) => true,
);

final toggleRecordingProvider = StateProvider<bool>((ref) => false);

final recordingPathProvider = StateProvider<String?>((ref) => null);

// Voice preview playback state
final isPlayingPreviewProvider = StateProvider<bool>((ref) => false);

final positionProvider = StateProvider<Duration>((ref) => Duration.zero);

final durationProvider = StateProvider<Duration>((ref) => Duration.zero);

// Image preview provider (Family: fileId)
final imagePreviewProvider = FutureProvider.family<List<int>, String>((
  ref,
  fileId,
) async {
  return await storage.getFilePreview(bucketId: bucketId, fileId: fileId);
});

// Unread count provider (Family: contactId)
final unreadCountProvider = FutureProvider.family<int, String>((
  ref,
  contactId,
) async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return 0;

  final chatId = ChatService.generateChatId(currentUserId, contactId);
  return ChatService.getUnreadCount(
    chatId: chatId,
    receiverId:
        currentUserId, // Current user is the receiver for unread messages
  );
});

final lastMessageProvider = FutureProvider.family<String, String>((
  ref,
  contactId,
) async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return '';

  final chatId = ChatService.generateChatId(currentUserId, contactId);

  try {
    // Fetch from both sources
    final sentMessageResult = await ChatService.getLastMessage(chatId);
    final deliveredMessages = await SqfliteHelper.getLastMessage(chatId);

    Message? latestMessage;
    DateTime? latestTimestamp;

    // Check Appwrite message (sent status)
    if (sentMessageResult.documents.isNotEmpty) {
      final sentMessageData = sentMessageResult.documents.first.data;
      final sentTimestamp = DateTime.parse(
        sentMessageData['createdAt'] ?? DateTime.now().toIso8601String(),
      );

      latestTimestamp = sentTimestamp;
      latestMessage = Message(
        id: sentMessageResult.documents.first.$id,
        chatId: sentMessageData['chatId'] ?? chatId,
        senderId: sentMessageData['senderId'] ?? '',
        receiverId: sentMessageData['receiverId'] ?? '',
        text: sentMessageData['text'] ?? '',
        imageId: sentMessageData['imageId'],
        audioId: sentMessageData['audioId'],
        status: sentMessageData['status'] ?? 'sent',
        createdAt: sentTimestamp,
      );
    }

    // Check SQLite message (delivered status) and compare timestamps
    if (deliveredMessages.isNotEmpty) {
      final deliveredMessage = deliveredMessages.first;
      final deliveredTimestamp = deliveredMessage.createdAt;

      if (latestTimestamp == null ||
          deliveredTimestamp.isAfter(latestTimestamp)) {
        latestMessage = deliveredMessage;
      }
    }

    // Return the text of the latest message
    if (latestMessage != null) {
      return latestMessage.text;
    }

    return '';
  } catch (e) {
    // On error, try to get at least the SQLite message as fallback
    try {
      final deliveredMessages = await SqfliteHelper.getLastMessage(chatId);
      if (deliveredMessages.isNotEmpty) {
        return deliveredMessages.first.text;
      }
    } catch (e) {
      // If both fail, return empty string
    }
    return '';
  }
});

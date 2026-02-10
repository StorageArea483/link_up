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

// Image loading states - tracks which images are still loading
final imageLoadingStatesProvider = StateProvider<Map<String, bool>>((ref) => {});

// Combined loading state that considers both messages and images
final isChatFullyLoadedProvider = Provider<bool>((ref) {
  final isLoadingChat = ref.watch(isLoadingChatScreenProvider);
  final imageLoadingStates = ref.watch(imageLoadingStatesProvider);
  
  // If chat is still loading, return false
  if (isLoadingChat) return false;
  
  // If any images are still loading, return false
  final hasLoadingImages = imageLoadingStates.values.any((isLoading) => isLoading);
  return !hasLoadingImages;
});

// Messages list provider
final messagesProvider = StateProvider<List<Message>>((ref) => []);

// Typing indicator provider
final isTypingProvider = StateProvider<bool>((ref) => false);

// Online status provider
final isOnlineProvider = StateProvider<bool>((ref) => false);

// Current user ID provider
final currentUserIdProvider = StateProvider<String?>((ref) => null);

// Chat ID provider
final chatIdProvider = StateProvider<String?>((ref) => null);

// Local File provider
final localFileProvider = StateProvider<File?>((ref) => null);

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

// Cached messages provider (Family: chatId) - Stores messages in memory per chat
final cachedMessagesProvider = StateProvider.family<List<Message>, String>(
  (ref, chatId) => [],
);

// Last message provider (Family: contactId) - Fetches from SQLite
final lastMessageProvider = FutureProvider.family<String, String>((
  ref,
  contactId,
) async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return '';

  final chatId = ChatService.generateChatId(currentUserId, contactId);
  final sentMessage = await ChatService.getLastMessage(chatId);
  final messages = await SqfliteHelper.getLastMessage(chatId);

  if (sentMessage.documents.isNotEmpty) {
    return sentMessage.documents.first.data['text'];
  } else if (messages.isNotEmpty) {
    return messages.first.text;
  }
  return '';
});

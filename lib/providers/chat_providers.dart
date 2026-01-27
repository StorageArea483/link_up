import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/services/chat_service.dart';

// Loading state provider
final isLoadingStateProvider = StateProvider<bool>((ref) => true);

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

// Last seen provider
final lastSeenProvider = StateProvider<String>((ref) => '');

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
        currentUserId, // Based on user's last edit: receiver is the contact
  );
});

// Last message provider (Family: contactId)
final lastMessageProvider = FutureProvider.family<String, String>((
  ref,
  contactId,
) async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return '';

  final chatId = ChatService.generateChatId(currentUserId, contactId);
  final docs = await ChatService.getLastMessage(chatId);

  if (docs.documents.isNotEmpty) {
    return docs.documents.first.data['text'] ?? '';
  }
  return '';
});

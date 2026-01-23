import 'package:flutter_riverpod/legacy.dart';
import 'package:link_up/models/message.dart';

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
final lastSeenProvider = StateProvider<DateTime?>((ref) => null);

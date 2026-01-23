import 'package:flutter_riverpod/legacy.dart';
import 'package:link_up/models/message.dart';

final isLoadingStateProvider = StateProvider<bool>((ref) => true);

final messagesProvider = StateProvider<List<Message>>((ref) => []);

final isTypingProvider = StateProvider<bool>((ref) => false);

final isOnlineProvider = StateProvider<bool>((ref) => false);

final currentUserIdProvider = StateProvider<String?>((ref) => null);

final chatIdProvider = StateProvider<String?>((ref) => null);

// Last seen provider
final lastSeenProvider = StateProvider<DateTime?>((ref) => null);

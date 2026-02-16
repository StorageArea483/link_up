import 'dart:developer';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:link_up/config/appwrite_client.dart';

class ChatService {
  static const String databaseId = 'linkup_db';
  static const String messagesCollectionId = 'messages';
  static const String typingCollectionId = 'typing';
  static const String presenceCollectionId = 'presence';

  static String generateChatId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  static Future<Document?> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String text,
    String? imageId,
    String? audioId,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'chatId': chatId,
        'senderId': senderId,
        'receiverId': receiverId,
        'text': text,
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
      };

      if (imageId != null) {
        data['imageId'] = imageId;
      }

      if (audioId != null) {
        data['audioId'] = audioId;
      }

      return await databases.createDocument(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in sendMessage: ${e.message}',
          name: 'ChatService',
        );
      }
      return null;
    }
  }

  static Future<DocumentList> getLastMessage(String chatId) async {
    try {
      final result = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.orderDesc('createdAt'),
          Query.limit(1),
        ],
      );
      return result;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in getLastMessage: ${e.message}',
          name: 'ChatService',
        );
      }
      return DocumentList(total: 0, documents: []);
    }
  }

  static Future<DocumentList> getMessages(String chatId) async {
    try {
      final result = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      return result;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in getMessages: ${e.message}',
          name: 'ChatService',
        );
      }
      return DocumentList(total: 0, documents: []);
    }
  }

  static subscribeToMessages(
    String chatId,
    Function(RealtimeMessage) callback,
  ) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$messagesCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                if (response.payload['chatId'] == chatId) {
                  callback(response);
                }
              } catch (e) {
                // Silently handle payload parsing errors to prevent stream interruption
              }
            },
            onError: (error) {
              // Only log critical connection errors for debugging
              log('Message subscription error: $error', name: 'ChatService');
            },
            cancelOnError: false,
          );
    } catch (e) {
      // Only log critical subscription setup errors for debugging
      log('Failed to setup message subscription: $e', name: 'ChatService');
      return null;
    }
  }

  static subscribeToPresence(
    String userId,
    Function(RealtimeMessage) callback,
  ) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$presenceCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                if (response.payload['userId'] == userId) {
                  // checking presence for reciever
                  callback(response);
                }
              } catch (e) {
                // Silently handle payload parsing errors to prevent stream interruption
              }
            },
            onError: (error) {
              // Only log critical connection errors for debugging
              log('Presence subscription error: $error', name: 'ChatService');
            },
            cancelOnError: false,
          );
    } catch (e) {
      // Only log critical subscription setup errors for debugging
      log('Failed to setup presence subscription: $e', name: 'ChatService');
      return null;
    }
  }

  static subscribeToRealtimeMessages(Function(RealtimeMessage) callback) {
    try {
      // Subscribe to all document changes in the messages collection
      // Only listen for 'sent' status messages (delivered messages are handled locally)
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$messagesCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                // Only process messages with 'sent' status
                // Delivered messages are deleted from Appwrite and stored locally
                if (response.payload['status'] == 'sent') {
                  callback(response);
                }
              } catch (e) {
                // Silently handle payload parsing errors to prevent stream interruption
              }
            },
            onError: (error) {
              // Only log critical connection errors for debugging
              log(
                'Realtime messages subscription error: $error',
                name: 'ChatService',
              );
            },
            cancelOnError: false,
          );
    } catch (e) {
      // Only log critical subscription setup errors for debugging
      log(
        'Failed to setup realtime messages subscription: $e',
        name: 'ChatService',
      );
      return null;
    }
  }

  static Future<List<Document>> markMessagesAsDelivered({
    required String chatId,
    required String receiverId,
  }) async {
    try {
      // Step 1: Get all undelivered messages for this receiver
      // Only fetch messages with status 'sent' that are meant for this receiver
      final messages = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.equal('receiverId', receiverId),
          Query.equal('status', 'sent'),
        ],
      );

      final updatedMessages = <Document>[];

      // Step 2: Update each message to 'delivered' status
      // This indicates the receiver has opened the chat and received the message
      for (final message in messages.documents) {
        final updatedMessage = await databases.updateDocument(
          databaseId: databaseId,
          collectionId: messagesCollectionId,
          documentId: message.$id,
          data: {'status': 'delivered'},
        );
        updatedMessages.add(updatedMessage);
      }

      return updatedMessages;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in markMessagesAsDelivered: ${e.message}',
          name: 'ChatService',
        );
      }
      return [];
    }
  }

  static Future<bool> deleteMessageFromAppwrite(String messageId) async {
    try {
      await databases.deleteDocument(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        documentId: messageId,
      );
      return true;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in deleteMessageFromAppwrite: ${e.message}',
          name: 'ChatService',
        );
      }
      return false;
    }
  }

  static Future<Document?> updateMessageStatus(
    String messageId,
    String status,
  ) async {
    try {
      return await databases.updateDocument(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        documentId: messageId,
        data: {'status': status},
      );
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in updateMessageStatus: ${e.message}',
          name: 'ChatService',
        );
      }
      return null;
    }
  }

  static Future<bool> setTyping({
    required String chatId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      final existingDocs = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: typingCollectionId,
        queries: [Query.equal('chatId', chatId), Query.equal('userId', userId)],
      );

      if (existingDocs.documents.isEmpty) {
        await databases.createDocument(
          databaseId: databaseId,
          collectionId: typingCollectionId,
          documentId: ID.unique(),
          data: {'chatId': chatId, 'userId': userId, 'isTyping': isTyping},
        );
      } else {
        await databases.updateDocument(
          databaseId: databaseId,
          collectionId: typingCollectionId,
          documentId: existingDocs.documents.first.$id,
          data: {'isTyping': isTyping},
        );
      }
      return true;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in setTyping: ${e.message}',
          name: 'ChatService',
        );
      }
      return false;
    }
  }

  static subscribeToTyping(String chatId, Function(RealtimeMessage) callback) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$typingCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                if (response.payload['chatId'] == chatId) {
                  callback(response);
                }
              } catch (e) {
                // Silently handle payload parsing errors to prevent stream interruption
              }
            },
            onError: (error) {
              // Only log critical connection errors for debugging
              log('Typing subscription error: $error', name: 'ChatService');
            },
            cancelOnError: false,
          );
    } catch (e) {
      // Only log critical subscription setup errors for debugging
      log('Failed to setup typing subscription: $e', name: 'ChatService');
      return null;
    }
  }

  static Future<bool> updatePresence({
    required String userId, // current persons using the app userId
    required bool online, // true if online false if offline
  }) async {
    try {
      final existingDocs = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: presenceCollectionId,
        queries: [
          Query.equal('userId', userId),
        ], // checking is user exists or not
      );

      if (existingDocs.documents.isEmpty) {
        await databases.createDocument(
          databaseId: databaseId,
          collectionId: presenceCollectionId,
          documentId: ID.unique(),
          data: {'userId': userId, 'online': online},
        ); // a new doc will get created with the respected status
      } else {
        await databases.updateDocument(
          databaseId: databaseId,
          collectionId: presenceCollectionId,
          documentId: existingDocs.documents.first.$id,
          data: {'online': online},
        );
      }
      return true;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in updatePresence: ${e.message}',
          name: 'ChatService',
        );
      }
      return false;
    }
  }

  static Future<Document?> getUserPresence(String userId) async {
    try {
      final docs = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: presenceCollectionId,
        queries: [Query.equal('userId', userId)],
      );
      return docs.documents.isNotEmpty ? docs.documents.first : null;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in getUserPresence: ${e.message}',
          name: 'ChatService',
        );
      }
      return null;
    }
  }

  static Future<int> getUnreadCount({
    required String chatId,
    required String receiverId,
  }) async {
    try {
      final result = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        queries: [
          Query.equal('chatId', chatId),
          Query.equal('receiverId', receiverId),
          Query.equal('status', 'sent'),
        ],
      );
      if (result.documents.isEmpty) {
        return 0;
      }
      return result.total;
    } catch (e) {
      // Only log critical server errors for debugging
      if (e is AppwriteException && (e.code != null && e.code! >= 500)) {
        log(
          'Critical database error in getUnreadCount: ${e.message}',
          name: 'ChatService',
        );
      }
      return 0;
    }
  }
}

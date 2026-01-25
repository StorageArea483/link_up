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
    required bool receiverOnline,
  }) async {
    try {
      // Set status based on receiver's online status
      final status = receiverOnline ? 'delivered' : 'sent';

      return await databases.createDocument(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'chatId': chatId,
          'senderId': senderId,
          'receiverId': receiverId,
          'text': text,
          'status': status,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
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
              } catch (e) {}
            },
            onError: (error) {},
            cancelOnError: false,
          );
    } catch (e) {
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
                  callback(response);
                }
              } catch (e) {}
            },
            onError: (error) {},
            cancelOnError: false,
          );
    } catch (e) {
      return null;
    }
  }

  static Future<List<Document>> markMessagesAsDelivered({
    required String chatId,
    required String receiverId,
  }) async {
    try {
      // Get all undelivered messages for this receiver
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

      // Update each message to delivered status
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
      return [];
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
              } catch (e) {}
            },
            onError: (error) {},
            cancelOnError: false,
          );
    } catch (e) {
      return null;
    }
  }

  static Future<bool> updatePresence({
    required String userId,
    required bool online,
  }) async {
    try {
      final existingDocs = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: presenceCollectionId,
        queries: [Query.equal('userId', userId)],
      );

      if (existingDocs.documents.isEmpty) {
        await databases.createDocument(
          databaseId: databaseId,
          collectionId: presenceCollectionId,
          documentId: ID.unique(),
          data: {
            'userId': userId,
            'online': online,
            'lastSeen': DateTime.now().toIso8601String(),
          },
        );
      } else {
        await databases.updateDocument(
          databaseId: databaseId,
          collectionId: presenceCollectionId,
          documentId: existingDocs.documents.first.$id,
          data: {
            'online': online,
            'lastSeen': DateTime.now().toIso8601String(),
          },
        );
      }
      return true;
    } catch (e) {
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
      return null;
    }
  }
}

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
  }) async {
    try {
      return await databases.createDocument(
        databaseId: databaseId,
        collectionId: messagesCollectionId,
        documentId: ID.unique(),
        data: {
          'chatId': chatId,
          'senderId': senderId,
          'receiverId': receiverId,
          'text': text,
          'status': 'sent',
          'createdAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      return null;
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

  static Future<bool> setUserPresence({
    required String userId,
    required bool isOnline,
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
            'online': isOnline,
            'lastSeen': DateTime.now().toIso8601String(),
          },
        );
      } else {
        await databases.updateDocument(
          databaseId: databaseId,
          collectionId: presenceCollectionId,
          documentId: existingDocs.documents.first.$id,
          data: {
            'online': isOnline,
            'lastSeen': DateTime.now().toIso8601String(),
          },
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setTyping({
    required String chatId,
    required String userId,
    required bool isTyping, // null
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

  static subscribeToPresence(Function(RealtimeMessage) callback) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$presenceCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              callback(response);
            },
            onError: (error) {},
            cancelOnError: false,
          );
    } catch (e) {
      return null;
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

import 'dart:async';
import 'dart:developer';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:link_up/config/appwrite_client.dart';

class CallService {
  static const String databaseId = 'linkup_db';
  static const String callsCollectionId = 'calls';
  static const String iceCandidatesCollectionId = 'ice_candidates';

  static Future<Document?> createCall({
    required String callerId,
    required String callerName,
    required String calleeId,
    required String offer, // JSON-encoded SDP offer
    required bool isVideo, // true = video call, false = audio-only
  }) async {
    try {
      return await databases.createDocument(
        databaseId: databaseId,
        collectionId: callsCollectionId,
        documentId: ID.unique(),
        data: {
          'callerId': callerId,
          'callerName': callerName,
          'calleeId': calleeId,
          'offer': offer,
          'answer': '', // empty until callee answers
          'status': 'ringing', // ringing → answered → ended
          'isVideo': isVideo,
        },
      );
    } catch (e) {
      log('Error creating call: $e', name: 'CallService');
      return null;
    }
  }

  static Future<Document?> answerCall({
    required String callId,
    required String answer, // JSON-encoded SDP answer
  }) async {
    try {
      return await databases.updateDocument(
        databaseId: databaseId,
        collectionId: callsCollectionId,
        documentId: callId,
        data: {'answer': answer, 'status': 'answered'},
      );
    } catch (e) {
      log('Error answering call: $e', name: 'CallService');
      return null;
    }
  }

  static Future<void> endCall(String callId) async {
    try {
      await databases.updateDocument(
        databaseId: databaseId,
        collectionId: callsCollectionId,
        documentId: callId,
        data: {'status': 'ended'},
      );
    } catch (e) {
      log('Error ending call: $e', name: 'CallService');
    }
  }

  static Future<void> addIceCandidate({
    required String callId,
    required String senderId,
    required String candidate, // JSON-encoded ICE candidate
  }) async {
    try {
      await databases.createDocument(
        databaseId: databaseId,
        collectionId: iceCandidatesCollectionId,
        documentId: ID.unique(),
        data: {'callId': callId, 'senderId': senderId, 'candidate': candidate},
      );
    } catch (e) {
      log('Error adding ICE candidate: $e', name: 'CallService');
    }
  }

  static StreamSubscription? subscribeToCallChanges(
    String callId,
    Function(RealtimeMessage) callback,
  ) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$callsCollectionId.documents.$callId',
          ])
          .stream
          .listen(
            (response) {
              callback(response);
            },
            onError: (error) {
              log('Call subscription error: $error', name: 'CallService');
            },
            cancelOnError: false,
          );
    } catch (e) {
      log('Failed to subscribe to call changes: $e', name: 'CallService');
      return null;
    }
  }

  static StreamSubscription? subscribeToIncomingCalls(
    String currentUserId,
    Function(RealtimeMessage) callback,
  ) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$callsCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                // Only handle newly created documents (incoming calls)
                final events = response.events;
                final isCreate = events.any((e) => e.contains('.create'));
                if (isCreate && response.payload['calleeId'] == currentUserId) {
                  callback(response);
                }
              } catch (e) {
                // Silently handle parse errors
              }
            },
            onError: (error) {
              log(
                'Incoming call subscription error: $error',
                name: 'CallService',
              );
            },
            cancelOnError: false,
          );
    } catch (e) {
      log('Failed to subscribe to incoming calls: $e', name: 'CallService');
      return null;
    }
  }

  static StreamSubscription? subscribeToIceCandidates(
    String callId,
    String currentUserId,
    Function(RealtimeMessage) callback,
  ) {
    try {
      return realtime
          .subscribe([
            'databases.$databaseId.collections.$iceCandidatesCollectionId.documents',
          ])
          .stream
          .listen(
            (response) {
              try {
                // Only process candidates for this call, from the OTHER user
                if (response.payload['callId'] == callId &&
                    response.payload['senderId'] != currentUserId) {
                  callback(response);
                }
              } catch (e) {
                // Silently handle parse errors
              }
            },
            onError: (error) {
              log(
                'ICE candidate subscription error: $error',
                name: 'CallService',
              );
            },
            cancelOnError: false,
          );
    } catch (e) {
      log('Failed to subscribe to ICE candidates: $e', name: 'CallService');
      return null;
    }
  }

  static Future<void> cleanupCall(String callId) async {
    try {
      // Delete ICE candidates for this call
      final iceDocs = await databases.listDocuments(
        databaseId: databaseId,
        collectionId: iceCandidatesCollectionId,
        queries: [Query.equal('callId', callId), Query.limit(100)],
      );
      for (final doc in iceDocs.documents) {
        await databases.deleteDocument(
          databaseId: databaseId,
          collectionId: iceCandidatesCollectionId,
          documentId: doc.$id,
        );
      }

      // Delete the call document itself
      await databases.deleteDocument(
        databaseId: databaseId,
        collectionId: callsCollectionId,
        documentId: callId,
      );
    } catch (e) {
      log('Error cleaning up call: $e', name: 'CallService');
    }
  }
}

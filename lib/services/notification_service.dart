import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis_auth/auth_io.dart';

class NotificationService {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Save FCM token to Firestore for a specific user
  Future<void> saveTokenToDatabase(String userId) async {
    try {
      // Request permission first and check the result
      await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: true,
        criticalAlert: true,
        provisional: true,
        sound: true,
      );

      String? token = await messaging.getToken();

      if (token != null) {
        // Save token to user's document in Firestore
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'fcmToken': token},
        );

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          if (message.notification?.title == 'user') {}
        });

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          // Handle foreground messages
        });
      } else {
        throw Exception('Failed to fetch token please restart the app');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<AccessCredentials> _getAccessToken() async {
    final serviceAccountPath = dotenv.env['PATH_TO_SECRET'];

    String serviceAccountJson = await rootBundle.loadString(
      serviceAccountPath!,
    );

    final serviceAccount = ServiceAccountCredentials.fromJson(
      serviceAccountJson,
    );

    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    final client = await clientViaServiceAccount(serviceAccount, scopes);
    return client.credentials;
  }

  Future<void> sendPushNotification({
    required String deviceToken, // receiver device token
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (deviceToken.isEmpty) return;

    try {
      final credentials = await _getAccessToken();
      final accessToken = credentials.accessToken.data;
      final projectId = dotenv.env['PROJECT_ID'];

      if (projectId == null || projectId.isEmpty) {
        throw Exception('PROJECT_ID not found in environment variables');
      }

      final Dio dio = Dio();

      // Prepare the FCM message payload
      final message = {
        'message': {
          'token': deviceToken,
          'notification': {'title': title, 'body': body},
          'data': data ?? {},
        },
      };

      final fcmUrl =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final response = await dio.post(
        fcmUrl,
        data: jsonEncode(message),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send notification: ${response.data}');
      }
    } catch (e) {
      rethrow;
    }
  }
}

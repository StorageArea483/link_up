import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis_auth/auth_io.dart';

class NotificationService {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  // Global navigator key for navigation from background
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Initialize the service and ensure dotenv is loaded
  static Future<void> initialize() async {
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }

      // Verify required environment variables
      final pathToSecret = dotenv.env['PATH_TO_SECRET'];
      final projectId = dotenv.env['PROJECT_ID'];

      if (pathToSecret == null || pathToSecret.isEmpty) {
        throw Exception('PATH_TO_SECRET not found in .env file');
      }

      if (projectId == null || projectId.isEmpty) {
        throw Exception('PROJECT_ID not found in .env file');
      }
    } catch (e) {
      rethrow;
    }
  }

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
      } else {
        throw Exception('Failed to fetch token please restart the app');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<AccessCredentials> _getAccessToken() async {
    try {
      // Ensure dotenv is initialized
      await _ensureDotenvInitialized();

      final serviceAccountPath = dotenv.env['PATH_TO_SECRET'];

      if (serviceAccountPath == null || serviceAccountPath.isEmpty) {
        throw Exception('PATH_TO_SECRET not found in environment variables');
      }

      String serviceAccountJson;
      try {
        serviceAccountJson = await rootBundle.loadString(serviceAccountPath);
      } catch (e) {
        throw Exception(
          'Failed to load service account file: $serviceAccountPath',
        );
      }

      Map<String, dynamic> serviceAccountMap;
      try {
        serviceAccountMap = jsonDecode(serviceAccountJson);
      } catch (e) {
        throw Exception('Invalid service account JSON format');
      }

      ServiceAccountCredentials serviceAccount;
      try {
        serviceAccount = ServiceAccountCredentials.fromJson(serviceAccountMap);
      } catch (e) {
        throw Exception('Failed to create service account credentials: $e');
      }

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client = await clientViaServiceAccount(serviceAccount, scopes);

      return client.credentials;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendPushNotification({
    required String deviceToken, // receiver device token
    required String title,
    required String body,
  }) async {
    if (deviceToken.isEmpty) return;

    try {
      final credentials = await _getAccessToken();
      final accessToken = credentials.accessToken.data;

      // Ensure dotenv is initialized for PROJECT_ID
      await _ensureDotenvInitialized();

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
          'data': {'navigate': 'landing'},
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

  // Helper method to ensure dotenv is initialized
  Future<void> _ensureDotenvInitialized() async {
    if (!dotenv.isInitialized) {
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        throw Exception('Failed to load .env file: $e');
      }
    }
  }
}

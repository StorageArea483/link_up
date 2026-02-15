import 'dart:convert';
import 'dart:developer' as developer;

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
      developer.log(
        '🔔 [NotificationService] Initializing NotificationService...',
      );

      if (!dotenv.isInitialized) {
        developer.log('🔔 [NotificationService] Loading .env file...');
        await dotenv.load(fileName: ".env");
        developer.log('🔔 [NotificationService] .env file loaded successfully');
      }

      // Verify required environment variables
      final pathToSecret = dotenv.env['PATH_TO_SECRET'];
      final projectId = dotenv.env['PROJECT_ID'];

      developer.log(
        '🔔 [NotificationService] PATH_TO_SECRET: ${pathToSecret != null ? 'Found' : 'Missing'}',
      );
      developer.log(
        '🔔 [NotificationService] PROJECT_ID: ${projectId != null ? 'Found' : 'Missing'}',
      );

      if (pathToSecret == null || pathToSecret.isEmpty) {
        throw Exception('PATH_TO_SECRET not found in .env file');
      }

      if (projectId == null || projectId.isEmpty) {
        throw Exception('PROJECT_ID not found in .env file');
      }

      developer.log(
        '🔔 [NotificationService] NotificationService initialized successfully',
      );
    } catch (e) {
      developer.log(
        '🔔 [NotificationService] ERROR initializing NotificationService: $e',
      );
      rethrow;
    }
  }

  // Save FCM token to Firestore for a specific user
  Future<void> saveTokenToDatabase(String userId) async {
    try {
      developer.log(
        '🔔 [NotificationService] Starting saveTokenToDatabase for userId: $userId',
      );

      // Request permission first and check the result
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: true,
        criticalAlert: true,
        provisional: true,
        sound: true,
      );

      developer.log(
        '🔔 [NotificationService] Permission status: ${settings.authorizationStatus}',
      );

      String? token = await messaging.getToken();
      developer.log(
        '🔔 [NotificationService] FCM Token retrieved: ${token?.substring(0, 20)}...',
      );

      if (token != null) {
        // Save token to user's document in Firestore
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'fcmToken': token},
        );
        developer.log(
          '🔔 [NotificationService] Token saved to Firestore successfully for userId: $userId',
        );
      } else {
        developer.log(
          '🔔 [NotificationService] ERROR: Failed to fetch FCM token',
        );
        throw Exception('Failed to fetch token please restart the app');
      }
    } catch (e) {
      developer.log(
        '🔔 [NotificationService] ERROR in saveTokenToDatabase: $e',
      );
      rethrow;
    }
  }

  Future<AccessCredentials> _getAccessToken() async {
    try {
      developer.log('🔔 [NotificationService] Getting access token...');

      // Ensure dotenv is initialized
      await _ensureDotenvInitialized();

      final serviceAccountPath = dotenv.env['PATH_TO_SECRET'];
      developer.log(
        '🔔 [NotificationService] Service account path: $serviceAccountPath',
      );

      if (serviceAccountPath == null || serviceAccountPath.isEmpty) {
        developer.log(
          '🔔 [NotificationService] ERROR: PATH_TO_SECRET not found in .env file',
        );
        developer.log(
          '🔔 [NotificationService] Available env keys: ${dotenv.env.keys.toList()}',
        );
        throw Exception('PATH_TO_SECRET not found in environment variables');
      }

      developer.log(
        '🔔 [NotificationService] Loading service account JSON from: $serviceAccountPath',
      );
      String serviceAccountJson;
      try {
        serviceAccountJson = await rootBundle.loadString(serviceAccountPath);
        developer.log(
          '🔔 [NotificationService] Service account JSON loaded successfully (${serviceAccountJson.length} characters)',
        );
      } catch (e) {
        developer.log(
          '🔔 [NotificationService] ERROR loading service account JSON: $e',
        );
        throw Exception(
          'Failed to load service account file: $serviceAccountPath',
        );
      }

      Map<String, dynamic> serviceAccountMap;
      try {
        serviceAccountMap = jsonDecode(serviceAccountJson);
        developer.log(
          '🔔 [NotificationService] Service account JSON parsed successfully',
        );
      } catch (e) {
        developer.log(
          '🔔 [NotificationService] ERROR parsing service account JSON: $e',
        );
        throw Exception('Invalid service account JSON format');
      }

      final serviceAccount = ServiceAccountCredentials.fromJson(
        serviceAccountMap,
      );
      developer.log(
        '🔔 [NotificationService] Service account credentials created',
      );

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      developer.log('🔔 [NotificationService] Requesting OAuth client...');
      final client = await clientViaServiceAccount(serviceAccount, scopes);
      developer.log(
        '🔔 [NotificationService] Access token obtained successfully',
      );

      return client.credentials;
    } catch (e) {
      developer.log('🔔 [NotificationService] ERROR in _getAccessToken: $e');
      developer.log('🔔 [NotificationService] Error details: ${e.toString()}');
      rethrow;
    }
  }

  // Helper method to ensure dotenv is initialized
  Future<void> _ensureDotenvInitialized() async {
    if (!dotenv.isInitialized) {
      developer.log(
        '🔔 [NotificationService] dotenv not initialized, loading .env file...',
      );
      try {
        await dotenv.load(fileName: ".env");
        developer.log('🔔 [NotificationService] dotenv loaded successfully');
      } catch (e) {
        developer.log('🔔 [NotificationService] ERROR loading .env file: $e');
        throw Exception('Failed to load .env file: $e');
      }
    } else {
      developer.log('🔔 [NotificationService] dotenv already initialized');
    }
  }

  // Test method to verify the service is working
  static Future<bool> testConfiguration() async {
    try {
      developer.log(
        '🔔 [NotificationService] ========== TESTING CONFIGURATION ==========',
      );

      final service = NotificationService();

      // Test dotenv initialization
      await service._ensureDotenvInitialized();

      // Test environment variables
      final pathToSecret = dotenv.env['PATH_TO_SECRET'];
      final projectId = dotenv.env['PROJECT_ID'];

      developer.log('🔔 [NotificationService] PATH_TO_SECRET: $pathToSecret');
      developer.log('🔔 [NotificationService] PROJECT_ID: $projectId');

      if (pathToSecret == null || projectId == null) {
        developer.log(
          '🔔 [NotificationService] ERROR: Missing environment variables',
        );
        return false;
      }

      // Test service account file loading
      try {
        final serviceAccountJson = await rootBundle.loadString(pathToSecret);
        final serviceAccountMap = jsonDecode(serviceAccountJson);
        developer.log(
          '🔔 [NotificationService] Service account file loaded and parsed successfully',
        );
        developer.log(
          '🔔 [NotificationService] Service account project_id: ${serviceAccountMap['project_id']}',
        );
      } catch (e) {
        developer.log(
          '🔔 [NotificationService] ERROR loading service account: $e',
        );
        return false;
      }

      // Test access token generation
      try {
        await service._getAccessToken();
        developer.log(
          '🔔 [NotificationService] ✅ Access token generation successful',
        );
        return true;
      } catch (e) {
        developer.log(
          '🔔 [NotificationService] ERROR generating access token: $e',
        );
        return false;
      }
    } catch (e) {
      developer.log('🔔 [NotificationService] ERROR in testConfiguration: $e');
      return false;
    }
  }

  Future<void> sendPushNotification({
    required String deviceToken, // receiver device token
    required String title,
    required String body,
  }) async {
    developer.log(
      '🔔 [NotificationService] ========== STARTING PUSH NOTIFICATION ==========',
    );
    developer.log(
      '🔔 [NotificationService] Device token: ${deviceToken.substring(0, 20)}...',
    );
    developer.log('🔔 [NotificationService] Title: $title');
    developer.log('🔔 [NotificationService] Body: $body');

    if (deviceToken.isEmpty) {
      developer.log(
        '🔔 [NotificationService] ERROR: Device token is empty, aborting notification',
      );
      return;
    }

    try {
      developer.log('🔔 [NotificationService] Step 1: Getting access token...');
      final credentials = await _getAccessToken();
      final accessToken = credentials.accessToken.data;
      developer.log(
        '🔔 [NotificationService] Step 1: Access token obtained: ${accessToken.substring(0, 20)}...',
      );

      // Ensure dotenv is initialized for PROJECT_ID
      await _ensureDotenvInitialized();

      final projectId = dotenv.env['PROJECT_ID'];
      developer.log('🔔 [NotificationService] Step 2: Project ID: $projectId');

      if (projectId == null || projectId.isEmpty) {
        developer.log(
          '🔔 [NotificationService] ERROR: PROJECT_ID not found in environment variables',
        );
        throw Exception('PROJECT_ID not found in environment variables');
      }

      final Dio dio = Dio();

      // Prepare the FCM message payload
      final message = {
        'message': {
          'token': deviceToken,
          'notification': {'title': title, 'body': body},
          'data': {'navigate': 'landing-page'},
        },
      };

      developer.log(
        '🔔 [NotificationService] Step 3: Message payload prepared: ${jsonEncode(message)}',
      );

      final fcmUrl =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
      developer.log('🔔 [NotificationService] Step 4: FCM URL: $fcmUrl');

      developer.log('🔔 [NotificationService] Step 5: Sending HTTP request...');
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

      developer.log(
        '🔔 [NotificationService] Step 6: Response status code: ${response.statusCode}',
      );
      developer.log(
        '🔔 [NotificationService] Step 6: Response data: ${response.data}',
      );

      if (response.statusCode != 200) {
        developer.log(
          '🔔 [NotificationService] ERROR: Failed to send notification - Status: ${response.statusCode}, Data: ${response.data}',
        );
        throw Exception('Failed to send notification: ${response.data}');
      }

      developer.log(
        '🔔 [NotificationService] ✅ SUCCESS: Push notification sent successfully!',
      );
    } catch (e) {
      developer.log(
        '🔔 [NotificationService] ❌ ERROR in sendPushNotification: $e',
      );
      developer.log('🔔 [NotificationService] Error type: ${e.runtimeType}');
      if (e is DioException) {
        developer.log(
          '🔔 [NotificationService] Dio error response: ${e.response?.data}',
        );
        developer.log(
          '🔔 [NotificationService] Dio error status: ${e.response?.statusCode}',
        );
      }
      rethrow;
    }
  }
}

import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/services/notification_service.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'firebase_options.dart';

// Global navigator key for navigation from background
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler must be annotated and top-level
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  // Handle navigation when app is opened from background notification
  if (message.data['navigate'] == 'landing') {
    navigatorKey.currentState?.pushReplacementNamed('/landing');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase initialization failure is critical - log for debugging
    log('Firebase initialization failed: $e', name: 'Main');
  }

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize NotificationService
  try {
    await NotificationService.initialize();
  } catch (e) {
    // Notification service failure is critical - log for debugging
    log('Notification service initialization failed: $e', name: 'Main');
  }

  FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: const CheckConnection(child: LandingPage()),
      routes: {
        '/landing': (context) => const CheckConnection(child: LandingPage()),
      },
    );
  }
}

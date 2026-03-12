import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/services/notification_service.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'firebase_options.dart';

final NotificationService notificationService = NotificationService();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase initialization failure is critical - lo g for debugging
    log('Firebase initialization failed: $e', name: 'Main');
  }

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Create a ProviderContainer to access providers in main()
  final container = ProviderContainer();

  // Initialize NotificationService
  try {
    await notificationService.initialize();
    notificationService.listenToForegroundMessages(container);
  } catch (e) {
    // Notification service failure is critical - log for debugging
    log('Notification service initialization failed: $e', name: 'Main');
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CheckConnection(child: LandingPage()));
  }
}

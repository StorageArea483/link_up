import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:link_up/pages/google_signup.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'dart:developer';

class CheckConnection extends StatefulWidget {
  final Widget child;
  const CheckConnection({super.key, required this.child});

  @override
  State<CheckConnection> createState() => _CheckConnectionState();
}

class _CheckConnectionState extends State<CheckConnection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log(
      'LIFECYCLE didChangeAppLifecycleState triggered | mounted: $mounted | '
      'state: $state',
      name: 'DEBUG_SUBSCRIPTION',
    );

    super.didChangeAppLifecycleState(state);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      ChatService.updatePresence(userId: user.uid, online: true);
    } else {
      ChatService.updatePresence(userId: user.uid, online: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            ),
          );
        }
        if (snapshot.hasData) {
          final user = snapshot.data!;
          ChatService.updatePresence(userId: user.uid, online: true);
          return widget.child;
        } else {
          return const GoogleSignup();
        }
      },
    );
  }
}

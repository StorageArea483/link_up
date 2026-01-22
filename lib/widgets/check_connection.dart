import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:link_up/pages/google_signup.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/styles/styles.dart';

class CheckConnection extends StatelessWidget {
  const CheckConnection({super.key});

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
          return const LandingPage();
        } else {
          return const GoogleSignup();
        }
      },
    );
  }
}

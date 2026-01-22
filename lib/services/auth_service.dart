import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

// Google Sign-In Service Class
class GoogleSignInService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    // Disable serverClientId to avoid People API requirement
  );

  // Sign in with Google
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // For web, use Firebase Auth popup directly
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.setCustomParameters({'prompt': 'select_account'});

        final UserCredential userCredential = await _auth.signInWithPopup(
          googleProvider,
        );
        final User? user = userCredential.user;

        if (user != null) {
          final userDoc = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          final docSnapshot = await userDoc.get();
          if (!docSnapshot.exists) {
            await userDoc.set({
              'uid': user.uid,
              'name': user.displayName ?? '',
              'email': user.email ?? '',
              'photoURL': user.photoURL ?? '',
              'provider': 'google',
            });
          }
        }
        return userCredential;
      } else {
        // For mobile platforms, use google_sign_in package
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          // User cancelled the sign-in
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(
          credential,
        );
        final User? user = userCredential.user;

        if (user != null) {
          final userDoc = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          final docSnapshot = await userDoc.get();
          if (!docSnapshot.exists) {
            await userDoc.set({
              'uid': user.uid,
              'name': user.displayName ?? '',
              'email': user.email ?? '',
              'photoURL': user.photoURL ?? '',
              'provider': 'google',
            });
          }
        }
        return userCredential;
      }
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  static Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      await _auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Get current user
  static User? getCurrentUser() {
    return _auth.currentUser;
  }
}

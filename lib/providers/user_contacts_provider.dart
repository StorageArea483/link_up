import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/models/user_contacts.dart';

final userContactProvider = FutureProvider<List<UserContacts>>((ref) async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return [];
    }

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('contacts')
        .get();

    return querySnapshot.docs.map((doc) {
      final data = doc.data();
      return UserContacts(
        uid: data['uid'] ?? doc.id,
        name: data['contact name'] ?? 'Unknown',
        phoneNumber: data['phone number'] ?? '',
        profilePicture: data['photoURL'] ?? '',
      );
    }).toList();
  } catch (e) {
    // Return empty list on error to prevent app crashes
    return [];
  }
});

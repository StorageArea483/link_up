import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userPhoneNumberProvider = FutureProvider<String>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return '---------';

  final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final doc = await docRef.get();

  if (doc.exists &&
      doc.data() != null &&
      doc.data()!.containsKey('user phone number')) {
    return doc.get('user phone number') as String;
  } else {
    // Generate new number if it doesn't exist
    final newNumber = (100000000 + Random().nextInt(900000000)).toString();
    await docRef.set({'user phone number': newNumber}, SetOptions(merge: true));
    return newNumber;
  }
});

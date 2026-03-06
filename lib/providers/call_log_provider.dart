import 'package:appwrite/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/services/call_service.dart';

final callLogProvider = FutureProvider<List<Document>>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final result = await CallService.getUserCallLogs(user.uid);
  if (result == null) return [];

  return result.documents;
});

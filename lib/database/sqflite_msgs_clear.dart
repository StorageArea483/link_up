import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/database/sqflite_helper.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/chat_providers.dart';

class SqfliteMsgsClear {
  final String? chatId;
  final String? contactUid;
  final WidgetRef ref;
  final BuildContext context;

  const SqfliteMsgsClear({
    required this.chatId,
    required this.contactUid,
    required this.ref,
    required this.context,
  });

  // Helper method to check if context is still mounted
  bool get _isMounted => context.mounted;

  // Show chat options dropdown menu
  void showChatOptionsMenu() {
    if (!_isMounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Clear all messages option
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.red,
                  size: 24,
                ),
                title: const Text(
                  'Clear all messages',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  if (!_isMounted) return;
                  Navigator.pop(context); // Close the bottom sheet
                  _clearAllMessages();
                },
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // Clear all messages from both local and remote storage
  Future<void> _clearAllMessages() async {
    if (chatId == null || !_isMounted) return;

    try {
      // Show loading indicator only if context is still mounted
      if (!_isMounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Clearing messages...'),
            ],
          ),
          backgroundColor: AppColors.primaryBlue,
          duration: Duration(seconds: 2),
        ),
      );

      // Clear messages from local SQLite database
      await SqfliteHelper.clearChatMessages(chatId!);
      // Clear messages from Appwrite (sent status messages)
      final sentMessages = await ChatService.getMessages(chatId!);
      for (final doc in sentMessages.documents) {
        await ChatService.deleteMessageFromAppwrite(doc.$id);
      }
      // Only update UI if context is still mounted
      if (!_isMounted) return;
      // Clear the UI immediately
      ref.read(messagesProvider.notifier).state = [];

      // Also invalidate the last message provider for this contact
      if (contactUid != null) {
        if (!_isMounted) return;
        ref.invalidate(lastMessageProvider(contactUid!));
      }

      // Show success message only if context is still mounted
      if (!_isMounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All messages cleared successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error message only if context is still mounted
      if (!_isMounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear messages. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

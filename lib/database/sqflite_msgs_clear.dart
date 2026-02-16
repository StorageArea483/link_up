import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/database/sqflite_helper.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:path_provider/path_provider.dart';

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

  void _showUploadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          backgroundColor: AppColors.primaryBlue,
        ),
      ),
    );
  }

  // Clear all messages from both local and remote storage
  Future<void> _clearAllMessages() async {
    if (chatId == null || !_isMounted) return;

    try {
      // Show loading indicator only if context is still mounted
      if (!_isMounted) return;

      if (context.mounted) {
        _showUploadingDialog();
      }

      // 1. Get all messages to extract media IDs before deletion
      final localMessages = await SqfliteHelper.getDeliveredMessages(chatId!);
      final sentMessages = await ChatService.getMessages(chatId!);

      // 2. Delete local media files (images and audio) FIRST
      await _deleteLocalMediaFiles(localMessages, sentMessages);

      // 3. Clear messages from Appwrite (sent status messages) BEFORE SQLite
      for (final doc in sentMessages.documents) {
        try {
          await ChatService.deleteMessageFromAppwrite(doc.$id);
        } catch (e) {
          // Continue with other messages even if one fails
        }
      }

      // 4. Clear messages from local SQLite database
      await SqfliteHelper.clearChatMessages(chatId!);

      // 5. ONLY NOW clear UI after all backend operations are complete
      if (!_isMounted) return;
      ref.read(messagesProvider(chatId!).notifier).state = [];
      Navigator.pop(context);

      // 6. Invalidate the last message provider for this contact
      if (contactUid != null) {
        if (!_isMounted) return;
        ref.invalidate(lastMessageProvider(contactUid!));
      }
      // 8. Show success message only if context is still mounted
      if (!_isMounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('All messages and media cleared successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error message only if context is still mounted
      if (!_isMounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text('Unable to clear messages. Please try again.'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Delete all local media files (images and audio) for this chat
  Future<void> _deleteLocalMediaFiles(
    List<Message> localMessages,
    dynamic sentMessages,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final storageBasePath = '${dir.path}/LinkUp storage';

      // Collect all media IDs from messages
      final Set<String> imageIds = {};
      final Set<String> audioIds = {};

      // Extract IDs from local messages
      for (Message message in localMessages) {
        if (message.imageId != null) {
          imageIds.add(message.imageId!);
        }
        if (message.audioId != null) {
          audioIds.add(message.audioId!);
        }
      }

      // Extract IDs from sent messages
      for (final doc in sentMessages.documents) {
        final data = doc.data;
        if (data['imageId'] != null) {
          imageIds.add(data['imageId']);
        }
        if (data['audioId'] != null) {
          audioIds.add(data['audioId']);
        }
      }

      // Delete image files
      for (String imageId in imageIds) {
        try {
          final imagePath = '$storageBasePath/Images/$imageId.jpg';
          final imageFile = File(imagePath);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        } catch (e) {
          // Continue with other files even if one fails
        }
      }

      // Delete audio files
      for (final audioId in audioIds) {
        try {
          final audioPath = '$storageBasePath/Audio/$audioId.m4a';
          final audioFile = File(audioPath);
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        } catch (e) {
          // Continue with other files even if one fails
        }
      }
    } catch (e) {
      // Media deletion errors don't prevent message clearing
    }
  }
}

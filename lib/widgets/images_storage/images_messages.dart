import 'dart:io' as io;
import 'package:appwrite/appwrite.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/database/sqflite_helper.dart';

class ImageMessagesHandler {
  final WidgetRef ref;
  final BuildContext context;
  final UserContacts contact;

  ImageMessagesHandler({
    required this.ref,
    required this.context,
    required this.contact,
  });

  Future<bool> pickAndSendImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) {
      return false;
    }

    if (!context.mounted) return false;
    final currentUserId = ref.read(currentUserIdProvider);
    if (!context.mounted) return false;
    final chatId = ref.read(chatIdProvider);

    if (currentUserId == null || chatId == null) {
      return false;
    }

    // Check internet connection
    if (!context.mounted) return false;
    final networkOnlineAsync = ref.read(networkConnectivityProvider);
    final hasInternet = networkOnlineAsync.value ?? true;
    if (!hasInternet) {
      if (context.mounted) {
        _showSnackBar('No internet connection', Colors.red);
      }
      return false;
    }

    try {
      // Show uploading indicator
      if (context.mounted) {
        _showUploadingDialog();
      }

      final file = await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: image.path),
      );

      // Save locally for the sender as well
      try {
        final dir = await getApplicationDocumentsDirectory();
        final storageDir = io.Directory('${dir.path}/LinkUp storage/Images');
        if (!await storageDir.exists()) {
          await storageDir.create(recursive: true);
        }
        final savePath = '${storageDir.path}/${file.$id}.jpg';

        // Only save if file doesn't already exist
        if (!await io.File(savePath).exists()) {
          await io.File(image.path).copy(savePath);

          // Also save to gallery for sender (only if newly saved)
          try {
            await Gal.putImage(savePath, album: 'LinkUp');
          } catch (e) {
            // Ignore gallery save error
          }
        }
      } catch (e) {
        // Ignore local save error
      }

      // Send message with imageId only (no imagePath since it's temporary)
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: contact.uid,
        text: 'Image',
        imageId: file.$id,
      );

      if (messageDoc != null) {
        final newMessage = Message.fromJson(messageDoc.data);
        if (!context.mounted) return false;
        final currentMessages = ref.read(messagesProvider(chatId));

        if (!context.mounted) return false;
        ref.read(messagesProvider(chatId).notifier).state = [
          newMessage,
          ...currentMessages,
        ];

        // NEW: Save the sent message to SQLite immediately
        await SqfliteHelper.insertMessage(newMessage);

        if (context.mounted) {
          Navigator.pop(context); // Close uploading dialog
          _showSnackBar('Image uploaded successfully', Colors.green);
        }

        try {
          if (context.mounted) {
            ref.invalidate(lastMessageProvider(contact.uid));
          }
        } catch (e) {
          // Handle invalidation error silently
        }
      } else {
        if (context.mounted) {
          Navigator.pop(context);
          _showSnackBar('Failed to send image message', Colors.red);
        }
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
      }
      return false;
    }
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

  void _showSnackBar(String message, Color backgroundColor) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
    }
  }
}

class ImageInputButtons extends ConsumerWidget {
  final UserContacts contact;

  const ImageInputButtons({super.key, required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.add_circle_outline_rounded,
            color: AppColors.primaryBlue,
            size: 28,
          ),
          onPressed: () async {
            final handler = ImageMessagesHandler(
              ref: ref,
              context: context,
              contact: contact,
            );
            final success = await handler.pickAndSendImage(ImageSource.gallery);
            if (!success) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to upload image'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.camera_alt_outlined,
            color: AppColors.textSecondary,
          ),
          onPressed: () async {
            final handler = ImageMessagesHandler(
              ref: ref,
              context: context,
              contact: contact,
            );
            final success = await handler.pickAndSendImage(ImageSource.camera);
            if (!success) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to upload image'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

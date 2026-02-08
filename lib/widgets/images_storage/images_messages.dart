import 'package:appwrite/appwrite.dart';
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
    if (image == null) return false;

    final currentUserId = ref.read(currentUserIdProvider);
    final chatId = ref.read(chatIdProvider);

    if (currentUserId == null || chatId == null) return false;

    // Check internet connection
    final networkOnlineAsync = ref.read(networkConnectivityProvider);
    final hasInternet = networkOnlineAsync.value ?? true;
    if (!hasInternet) {
      _showSnackBar('No internet connection', Colors.red);
      return false;
    }

    try {
      // Show uploading indicator
      _showUploadingDialog();

      final file = await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: image.path),
      );

      // Send message with imageId and imagePath
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: contact.uid,
        text: 'Image',
        imageId: file.$id,
        imagePath: image.path,
      );

      if (messageDoc != null) {
        final newMessage = Message.fromJson(messageDoc.data);
        final currentMessages = ref.read(messagesProvider);

        ref.read(messagesProvider.notifier).state = [
          newMessage,
          ...currentMessages,
        ];

        Navigator.pop(context); // Close uploading dialog
        _showSnackBar('Image uploaded successfully', Colors.green);

        try {
          ref.invalidate(lastMessageProvider(contact.uid));
        } catch (e) {
          // Handle invalidation error silently
        }
      } else {
        Navigator.pop(context);
        _showSnackBar('Failed to send image message', Colors.red);
      }

      return true;
    } catch (e) {
      Navigator.pop(context);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to upload image'),
                  backgroundColor: Colors.red,
                ),
              );
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to upload image'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

import 'dart:developer';
import 'dart:io' as io;
import 'package:appwrite/appwrite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/services/notification_service.dart';
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
    XFile? compressedImage;

    try {
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
          _showSnackBar(
            'Unable to upload. Please check your internet connection and try again.',
            Colors.red,
          );
        }
        return false;
      }

      if (context.mounted) {
        _showUploadingDialog();
      }

      // Create temporary compressed image path
      final tempDir = await getTemporaryDirectory();
      final compressedImagePath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      compressedImage = await FlutterImageCompress.compressAndGetFile(
        image.path,
        compressedImagePath,
        quality: 70,
        minWidth: 1024,
        minHeight: 1024,
      );

      if (compressedImage == null) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
          _showSnackBar(
            'Unable to process image. Please try again.',
            Colors.red,
          );
        }
        return false;
      }

      final file = await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: compressedImage.path),
      );

      try {
        final appDir = await getApplicationDocumentsDirectory();
        final storageDir = io.Directory('${appDir.path}/LinkUp storage/Images');

        if (!await storageDir.exists()) {
          await storageDir.create(recursive: true);
        }

        final savePath = '${storageDir.path}/${file.$id}.jpg';

        if (!await io.File(savePath).exists()) {
          await io.File(compressedImage.path).copy(savePath);

          // Update providers with the local io.File
          final localImageFile = io.File(savePath);
          ref.read(localFileProvider((file.$id, chatId)).notifier).state =
              localImageFile;
          ref
                  .read(imageLoadingStateProvider((file.$id, chatId)).notifier)
                  .state =
              false;
          try {
            await Gal.putImage(savePath, album: 'LinkUp');
          } catch (e) {
            // Log gallery save errors but don't fail the operation
            log(
              'Failed to save image to gallery: $e',
              name: 'ImageMessagesHandler',
            );
          }
        }
      } catch (e) {
        // Silent failure - local save errors don't prevent message sending
      }

      // 🔥 Send message
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

        ref.read(messagesProvider(chatId).notifier).state = [
          newMessage,
          ...currentMessages,
        ];

        await SqfliteHelper.insertMessage(newMessage);

        // Send push notification when image message status is "sent"
        if (newMessage.status == 'sent') {
          _sendPushNotificationToReceiver(newMessage);
        }

        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
          _showSnackBar('Image sent successfully', Colors.green);
        }

        if (context.mounted) {
          ref.invalidate(lastMessageProvider(contact.uid));
        }

        return true;
      } else {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
          _showSnackBar('Unable to send image. Please try again.', Colors.red);
        }
        return false;
      }
    } catch (e) {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context);
        _showSnackBar(
          'Unable to upload image. Please check your connection and try again.',
          Colors.red,
        );
      }
      return false;
    } finally {
      // 🔥 Guaranteed cleanup
      if (compressedImage != null) {
        try {
          await io.File(compressedImage.path).delete();
        } catch (e) {
          log(
            'Failed to cleanup temporary file: $e',
            name: 'ImageMessagesHandler',
          );
        }
      }
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

  // Send push notification to receiver when image message is sent
  Future<void> _sendPushNotificationToReceiver(Message message) async {
    try {
      // Get receiver's FCM token from Firestore
      final receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(contact.uid)
          .get();

      if (!receiverDoc.exists) return;

      final receiverData = receiverDoc.data();
      final receiverToken = receiverData?['fcmToken'] as String?;

      if (receiverToken == null || receiverToken.isEmpty) return;

      // Get sender's name from Firestore
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!senderDoc.exists) return;

      final senderData = senderDoc.data();
      final senderName = senderData?['name'] as String? ?? 'Someone';
      if (message.status == 'delivered') {
        return;
      }
      // Send push notification
      final notificationService = NotificationService();
      await notificationService.sendPushNotification(
        deviceToken: receiverToken,
        title: senderName,
        body: '📷 Photo',
        messageStatus: message.status,
      );
    } catch (e) {
      // Silent failure - push notification failure is not critical for image sending
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
                    content: Text('Unable to upload image. Please try again.'),
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

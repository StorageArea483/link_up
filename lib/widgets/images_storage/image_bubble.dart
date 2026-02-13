import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/styles/styles.dart';
import 'package:path_provider/path_provider.dart';

class ImageBubble extends ConsumerStatefulWidget {
  final String imageId;
  final String? chatId;

  const ImageBubble({super.key, required this.imageId, required this.chatId});

  @override
  ConsumerState<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends ConsumerState<ImageBubble> {
  @override
  void initState() {
    super.initState();
    // Delay the provider modification until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocalFile();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkLocalFile() async {
    // Early return if chatId is null
    if (widget.chatId == null) {
      if (mounted) {
        ref
                .read(
                  imageLoadingStateProvider((
                    widget.imageId,
                    widget.chatId,
                  )).notifier,
                )
                .state =
            false;
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}/LinkUp storage/Images/${widget.imageId}.jpg';

      final file = File(filePath);
      final exists = await file.exists();

      // Check once - if file exists, update provider
      if (exists) {
        if (mounted) {
          ref
                  .read(
                    localFileProvider((
                      widget.imageId,
                      widget.chatId!,
                    )).notifier,
                  )
                  .state =
              file;

          ref
                  .read(
                    imageLoadingStateProvider((
                      widget.imageId,
                      widget.chatId,
                    )).notifier,
                  )
                  .state =
              false;
        }
      }
      // If file doesn't exist, keep loading state true
      // _handleImageDelivery will update providers when download completes
    } catch (e) {
      // On error, stop loading
      if (mounted) {
        ref
                .read(
                  imageLoadingStateProvider((
                    widget.imageId,
                    widget.chatId,
                  )).notifier,
                )
                .state =
            false;
      }
    }
  }

  String get _imageUrl =>
      'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/${widget.imageId}/view?project=697035fd003aa22ae623';

  @override
  Widget build(BuildContext context) {
    // Early return if chatId is null
    if (widget.chatId == null) {
      return Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
        ),
      );
    }

    final isLoading = ref.watch(
      imageLoadingStateProvider((widget.imageId, widget.chatId)),
    );
    final localFile = ref.watch(
      localFileProvider((widget.imageId, widget.chatId!)),
    );
    if (isLoading) {
      return Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryBlue,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: localFile != null
          ? Image.file(
              localFile,
              width: 250,
              fit: BoxFit.cover,
              cacheWidth: 500,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget();
              },
            )
          : Image.network(
              _imageUrl,
              width: 250,
              fit: BoxFit.cover,
              cacheWidth: 500,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return Container(
                  width: 250,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget();
              },
            ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: 250,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          Text(
            'Image unavailable',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

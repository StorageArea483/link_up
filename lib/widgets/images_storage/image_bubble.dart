import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/styles/styles.dart';
import 'package:path_provider/path_provider.dart';

class ImageBubble extends ConsumerStatefulWidget {
  final String fileId;

  const ImageBubble({super.key, required this.fileId});

  @override
  ConsumerState<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends ConsumerState<ImageBubble> {
  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  Future<void> _checkLocalFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.fileId}.jpg');
      if (await file.exists()) {
        if (mounted) {
          ref.read(localFileProvider.notifier).state = file;
          ref.read(isLoadingStateProvider.notifier).state = false;
        }
      } else {
        if (mounted) {
          ref.read(isLoadingStateProvider.notifier).state = false;
        }
      }
    } catch (e) {
      if (mounted) {
        ref.read(isLoadingStateProvider.notifier).state = false;
      }
    }
  }

  String get _imageUrl =>
      'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/${widget.fileId}/view?project=697035fd003aa22ae623';

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isLoadingStateProvider)) {
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
      child: ref.watch(localFileProvider) != null
          ? Image.file(
              ref.watch(localFileProvider)!,
              width: 250,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget();
              },
            )
          : Image.network(
              _imageUrl,
              width: 250,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
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

import 'package:flutter/material.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/styles/styles.dart';

class ImageBubble extends StatelessWidget {
  final String fileId;

  const ImageBubble({super.key, required this.fileId});

  String get _imageUrl =>
      'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/$fileId/view?project=697035fd003aa22ae623';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
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
                const Icon(Icons.wifi_off, color: Colors.grey, size: 48),
                const SizedBox(height: 8),
                Text(
                  'Image unavailable offline',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

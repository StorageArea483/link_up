import 'dart:io';
import 'package:flutter/material.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/styles/styles.dart';
import 'package:path_provider/path_provider.dart';

class ImageBubble extends StatefulWidget {
  final String fileId;

  const ImageBubble({super.key, required this.fileId});

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  File? _localFile;
  bool _isLoading = true;

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
          setState(() {
            _localFile = file;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String get _imageUrl =>
      'https://fra.cloud.appwrite.io/v1/storage/buckets/$bucketId/files/${widget.fileId}/view?project=697035fd003aa22ae623';

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
      child: _localFile != null
          ? Image.file(
              _localFile!,
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

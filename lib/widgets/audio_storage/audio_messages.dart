import 'dart:io' as io;
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/models/message.dart';
import 'package:link_up/models/user_contacts.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/database/sqflite_helper.dart';

class AudioMessagesHandler {
  final WidgetRef ref;
  final BuildContext context;
  final AudioRecorder record;
  final AudioPlayer player;
  final UserContacts contact;
  bool _isAudioCompleted = false; // Flag to track if audio has completed

  AudioMessagesHandler({
    required this.ref,
    required this.context,
    required this.record,
    required this.player,
    required this.contact,
  }) {
    _initializePlayer();
  }

  void _initializePlayer() {
    // Listen to player state changes
    player.playerStateStream.listen((state) {
      try {
        if (state.processingState == ProcessingState.completed) {
          _isAudioCompleted = true;
          if (context.mounted) {
            ref.read(isPlayingPreviewProvider.notifier).state = false;
            // Reset position to beginning when audio completes
            ref.read(positionProvider.notifier).state = Duration.zero;
          }
        } else if (state.processingState == ProcessingState.ready &&
            state.playing) {
          // Reset the completed flag when audio starts playing again
          _isAudioCompleted = false;
        }
      } catch (e) {}
    });
  }

  // Getter to check if updates should be blocked
  bool get shouldBlockUpdates => _isAudioCompleted;

  Future<void> startRecording(String userId) async {
    try {
      if (await record.hasPermission()) {
        // Reset the completed flag when starting a new recording
        _isAudioCompleted = false;

        final path = await _getUniqueRecordingPath(userId: userId);

        if (path.isEmpty) {
          if (context.mounted) {
            _showSnackBar('Failed to create recording path', Colors.red);
          }
          return;
        }

        await record.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        if (context.mounted) {
          ref.read(toggleRecordingProvider.notifier).state = true;
        }
      } else {
        if (context.mounted) {
          _showSnackBar('Microphone permission denied', Colors.red);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ref.read(toggleRecordingProvider.notifier).state = false;
        _showSnackBar('Audio recording failed $e', Colors.red);
      }
    }
  }

  Future<void> stopRecording() async {
    try {
      if (!context.mounted) {
        return;
      }

      final currentUserId = ref.read(currentUserIdProvider);

      if (!context.mounted) return;
      final chatId = ref.read(chatIdProvider);

      final recordedPath = await record.stop();

      if (!context.mounted) return;
      ref.read(toggleRecordingProvider.notifier).state = false;

      if (chatId == null || currentUserId == null) {
        return;
      }

      if (recordedPath != null) {
        // Verify the file exists and has content
        final file = io.File(recordedPath);
        final exists = await file.exists();

        if (exists) {
          final fileSize = await file.length();

          if (fileSize > 1000) {
            // At least 1KB for a meaningful recording
            if (context.mounted) {
              ref.read(recordingPathProvider.notifier).state = recordedPath;
            }
          } else {
            if (context.mounted) {
              _showSnackBar('Recording is too short or empty', Colors.orange);
              // Still save it for testing purposes
              ref.read(recordingPathProvider.notifier).state = recordedPath;
            }
          }
        } else {
          if (context.mounted) {
            _showSnackBar('Recording file not found', Colors.red);
          }
        }
      } else {
        if (context.mounted) {
          _showSnackBar('Recording failed to save', Colors.red);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ref.read(toggleRecordingProvider.notifier).state = false;
        _showSnackBar('Audio recording failed', Colors.red);
      }
    }
  }

  Future<bool> sendAudioMessage() async {
    if (!context.mounted) {
      return false;
    }

    final recordingPath = ref.read(recordingPathProvider);

    if (recordingPath == null) {
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

      // Verify file exists before upload
      final recordingFile = io.File(recordingPath);
      if (!await recordingFile.exists()) {
        if (context.mounted) {
          Navigator.pop(context);
          _showSnackBar('Recording file not found', Colors.red);
        }
        return false;
      }

      final fileSize = await recordingFile.length();

      if (fileSize == 0) {
        if (context.mounted) {
          Navigator.pop(context);
          _showSnackBar('Recording file is empty', Colors.red);
        }
        return false;
      }

      final file = await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromPath(path: recordingPath),
      );

      // Save locally for the sender as well
      try {
        final dir = await getApplicationDocumentsDirectory();
        final storageDir = io.Directory('${dir.path}/LinkUp storage/Audio');
        if (!await storageDir.exists()) {
          await storageDir.create(recursive: true);
        }
        final savePath = '${storageDir.path}/${file.$id}.m4a';

        // Only save if file doesn't already exist
        if (!await io.File(savePath).exists()) {
          await io.File(recordingPath).copy(savePath);
        }
      } catch (e) {
        // Ignore local save error, upload succeeded
      }

      // Send message with audioId only
      final messageDoc = await ChatService.sendMessage(
        chatId: chatId,
        senderId: currentUserId,
        receiverId: contact.uid,
        text: 'Audio',
        audioId: file.$id,
      );

      if (messageDoc != null) {
        final newMessage = Message.fromJson(messageDoc.data);
        if (!context.mounted) {
          return false;
        }

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
          _showSnackBar('Audio sent successfully', Colors.green);
        }

        // Clean up the recording
        await deleteRecording();

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
          _showSnackBar('Failed to send audio message', Colors.red);
        }
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showSnackBar('Failed to send audio', Colors.red);
      }
      return false;
    }
  }

  Future<void> handlePlayPause() async {
    if (!context.mounted) return;
    final recordingPath = ref.read(recordingPathProvider);
    if (recordingPath == null) return;

    try {
      if (player.playing) {
        if (context.mounted) {
          ref.read(isPlayingPreviewProvider.notifier).state = false;
        }
        await player.pause();
      } else {
        // Verify file exists before trying to play
        final file = io.File(recordingPath);
        if (!await file.exists()) {
          if (context.mounted) {
            _showSnackBar('Audio file not found', Colors.red);
          }
          return;
        }

        // Check file size to ensure it has content
        final fileSize = await file.length();
        if (fileSize == 0) {
          if (context.mounted) {
            _showSnackBar('Audio file is empty', Colors.red);
          }
          return;
        }

        // Set the audio source
        try {
          await player.setFilePath(recordingPath);
        } catch (e) {
          if (context.mounted) {
            _showSnackBar('Failed to load audio file', Colors.red);
          }
          return;
        }
        // Reset the completed flag when starting playback
        _isAudioCompleted = false;
        if (context.mounted) {
          ref.read(isPlayingPreviewProvider.notifier).state = true;
        }
        await player.play();
      }
    } catch (e) {
      if (context.mounted) {
        ref.read(isPlayingPreviewProvider.notifier).state = false;
        _showSnackBar('Failed to play audio', Colors.red);
      }
    }
  }

  Future<void> handleSeek(double value) async {
    try {
      // Reset the completed flag when user manually seeks
      _isAudioCompleted = false;
      await player.seek(Duration(seconds: value.toInt()));
    } catch (e) {
      if (context.mounted) {
        _showSnackBar('Failed to seek audio', Colors.red);
      }
    }
  }

  Future<void> deleteRecording() async {
    if (!context.mounted) return;
    final path = ref.read(recordingPathProvider);
    if (path != null) {
      try {
        // Stop and clear the player first
        if (player.playing) {
          await player.stop();
        }

        // Clear the audio source safely
        try {
          await player.setUrl(''); // Clear with empty URL instead of empty path
        } catch (e) {}

        final file = io.File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}
    }

    // Reset all states
    _isAudioCompleted = false; // Reset the completed flag
    if (context.mounted) {
      ref.read(recordingPathProvider.notifier).state = null;
      ref.read(isPlayingPreviewProvider.notifier).state = false;
      ref.read(positionProvider.notifier).state = Duration.zero;
      ref.read(durationProvider.notifier).state = Duration.zero;
    }
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
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

  Future<String> _getUniqueRecordingPath({required String userId}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final voiceDir = io.Directory('${dir.path}/LinkUp storage/Audios');
      if (!await voiceDir.exists()) {
        await voiceDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${voiceDir.path}/voice_${userId}_$timestamp.m4a';
      return path;
    } catch (e) {
      return '';
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
    }
  }

  // Method to dispose resources
  Future<void> dispose() async {
    try {
      if (player.playing) {
        await player.stop();
      }
      // Reset providers to safe values before disposing
      if (context.mounted) {
        ref.read(recordingPathProvider.notifier).state = null;
        ref.read(isPlayingPreviewProvider.notifier).state = false;
        ref.read(positionProvider.notifier).state = Duration.zero;
        ref.read(durationProvider.notifier).state = Duration.zero;
      }

      await player.dispose();
    } catch (e) {}
  }
}

class AudioRecordingButton extends ConsumerWidget {
  final String? currentUserId;
  final AudioMessagesHandler handler;

  const AudioRecordingButton({
    super.key,
    required this.currentUserId,
    required this.handler,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toggleRecording = ref.watch(toggleRecordingProvider);
    final recordingPath = ref.watch(recordingPathProvider);

    if (recordingPath != null) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: toggleRecording
          ? const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 28)
          : const Icon(Icons.mic_none_rounded, color: AppColors.textSecondary),
      onPressed: () async {
        if (currentUserId == null) return;

        final isRecording = ref.read(toggleRecordingProvider);
        if (!isRecording) {
          await handler.startRecording(currentUserId!);
        } else {
          await handler.stopRecording();
        }
      },
    );
  }
}

class AudioPreviewWidget extends ConsumerWidget {
  final AudioMessagesHandler handler;

  const AudioPreviewWidget({super.key, required this.handler});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingPath = ref.watch(recordingPathProvider);
    final isPlayingPreview = ref.watch(isPlayingPreviewProvider);

    if (recordingPath == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Play/Pause Button
          IconButton(
            icon: Icon(
              isPlayingPreview
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: AppColors.primaryBlue,
              size: 32,
            ),
            onPressed: handler.handlePlayPause,
          ),
          const SizedBox(width: 8),
          // Audio controls
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final position = ref.watch(positionProvider);
                final duration = ref.watch(durationProvider);
                final maxDuration = duration.inSeconds > 0
                    ? duration.inSeconds.toDouble()
                    : 1.0;
                final currentPosition = position.inSeconds.toDouble().clamp(
                  0.0,
                  maxDuration,
                );

                return Column(
                  children: [
                    Text(handler.formatDuration(position)),
                    Slider(
                      min: 0.0,
                      max: maxDuration,
                      value: currentPosition,
                      onChanged: duration.inSeconds > 0
                          ? (value) => handler.handleSeek(value)
                          : null,
                    ),
                    Text(handler.formatDuration(duration)),
                  ],
                );
              },
            ),
          ),
          // Delete Button
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            onPressed: handler.deleteRecording,
          ),
        ],
      ),
    );
  }
}

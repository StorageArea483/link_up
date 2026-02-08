import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/styles/styles.dart';

class AudioMessagesHandler {
  final WidgetRef ref;
  final BuildContext context;
  final AudioRecorder record;
  final AudioPlayer player;
  bool _isAudioCompleted = false; // Flag to track if audio has completed

  AudioMessagesHandler({
    required this.ref,
    required this.context,
    required this.record,
    required this.player,
  }) {
    _initializePlayer();
  }

  void _initializePlayer() {
    // Listen to player state changes
    player.playerStateStream.listen((state) {
      try {
        if (state.processingState == ProcessingState.completed) {
          _isAudioCompleted = true;
          ref.read(isPlayingPreviewProvider.notifier).state = false;
          // Reset position to beginning when audio completes
          ref.read(positionProvider.notifier).state = Duration.zero;
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
          _showSnackBar('Failed to create recording path', Colors.red);
          return;
        }

        await record.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        ref.read(toggleRecordingProvider.notifier).state = true;
      } else {
        _showSnackBar('Microphone permission denied', Colors.red);
      }
    } catch (e) {
      ref.read(toggleRecordingProvider.notifier).state = false;
      _showSnackBar('Audio recording failed: ${e.toString()}', Colors.red);
    }
  }

  Future<void> stopRecording() async {
    try {
      final recordedPath = await record.stop();
      ref.read(toggleRecordingProvider.notifier).state = false;

      if (recordedPath != null) {
        // Verify the file exists and has content
        final file = io.File(recordedPath);
        if (await file.exists()) {
          final fileSize = await file.length();

          if (fileSize > 1000) {
            // At least 1KB for a meaningful recording
            ref.read(recordingPathProvider.notifier).state = recordedPath;
          } else {
            _showSnackBar('Recording is too short or empty', Colors.orange);
            // Still save it for testing purposes
            ref.read(recordingPathProvider.notifier).state = recordedPath;
          }
        } else {
          _showSnackBar('Recording file not found', Colors.red);
        }
      } else {
        _showSnackBar('Recording failed to save', Colors.red);
      }
    } catch (e) {
      ref.read(toggleRecordingProvider.notifier).state = false;
      _showSnackBar('Audio recording failed', Colors.red);
    }
  }

  Future<void> handlePlayPause() async {
    final recordingPath = ref.read(recordingPathProvider);
    if (recordingPath == null) return;

    try {
      if (player.playing) {
        ref.read(isPlayingPreviewProvider.notifier).state = false;
        await player.pause();
      } else {
        // Verify file exists before trying to play
        final file = io.File(recordingPath);
        if (!await file.exists()) {
          _showSnackBar('Audio file not found', Colors.red);
          return;
        }

        // Check file size to ensure it has content
        final fileSize = await file.length();
        if (fileSize == 0) {
          _showSnackBar('Audio file is empty', Colors.red);
          return;
        }

        // Set the audio source
        try {
          await player.setFilePath(recordingPath);
        } catch (e) {
          _showSnackBar('Failed to load audio file', Colors.red);
          return;
        }
        // Reset the completed flag when starting playback
        _isAudioCompleted = false;
        ref.read(isPlayingPreviewProvider.notifier).state = true;
        await player.play();
      }
    } catch (e) {
      ref.read(isPlayingPreviewProvider.notifier).state = false;
      _showSnackBar('Failed to play audio', Colors.red);
    }
  }

  Future<void> handleSeek(double value) async {
    try {
      // Reset the completed flag when user manually seeks
      _isAudioCompleted = false;
      await player.seek(Duration(seconds: value.toInt()));
    } catch (e) {
      _showSnackBar('Failed to seek audio', Colors.red);
    }
  }

  Future<void> deleteRecording() async {
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
    ref.read(recordingPathProvider.notifier).state = null;
    ref.read(isPlayingPreviewProvider.notifier).state = false;
    ref.read(positionProvider.notifier).state = Duration.zero;
    ref.read(durationProvider.notifier).state = Duration.zero;
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  Future<String> _getUniqueRecordingPath({required String userId}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final voiceDir = io.Directory('${dir.path}/voice_messages');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  // Method to dispose resources
  Future<void> dispose() async {
    try {
      if (player.playing) {
        await player.stop();
      }
      // Reset providers to safe values before disposing
      ref.read(recordingPathProvider.notifier).state = null;
      ref.read(isPlayingPreviewProvider.notifier).state = false;
      ref.read(positionProvider.notifier).state = Duration.zero;
      ref.read(durationProvider.notifier).state = Duration.zero;

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

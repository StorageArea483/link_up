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

  AudioMessagesHandler({
    required this.ref,
    required this.context,
    required this.record,
    required this.player,
  });

  Future<void> startRecording(String userId) async {
    try {
      if (await record.hasPermission()) {
        final path = await _getUniqueRecordingPath(userId: userId);
        if (path.isEmpty) return;

        await record.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        ref.read(toggleRecordingProvider.notifier).state = true;
      }
    } catch (e) {
      ref.read(toggleRecordingProvider.notifier).state = false;
      _showSnackBar('Audio recording failed', Colors.red);
    }
  }

  Future<void> stopRecording() async {
    try {
      final recordedPath = await record.stop();
      ref.read(toggleRecordingProvider.notifier).state = false;

      if (recordedPath != null) {
        ref.read(recordingPathProvider.notifier).state = recordedPath;
      }
    } catch (e) {
      ref.read(toggleRecordingProvider.notifier).state = false;
      _showSnackBar('Audio recording failed', Colors.red);
    }
  }

  void handlePlayPause() {
    if (player.playing) {
      ref.read(isPlayingPreviewProvider.notifier).state = false;
      player.pause();
    } else {
      ref.read(isPlayingPreviewProvider.notifier).state = true;
      player.play();
    }
  }

  void handleSeek(double value) {
    player.seek(Duration(seconds: value.toInt()));
  }

  void deleteRecording() async {
    final path = ref.read(recordingPathProvider);
    if (path != null) {
      try {
        final file = io.File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Handle deletion error silently
      }
    }
    ref.read(recordingPathProvider.notifier).state = null;
    ref.read(isPlayingPreviewProvider.notifier).state = false;
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
      return '${voiceDir.path}/voice_${userId}_$timestamp.m4a';
    } catch (e) {
      return '';
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
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
                return Column(
                  children: [
                    Text(handler.formatDuration(position)),
                    Slider(
                      min: 0.0,
                      max: duration.inSeconds.toDouble(),
                      value: position.inSeconds.toDouble(),
                      onChanged: handler.handleSeek,
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

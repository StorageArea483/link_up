import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/providers/chat_providers.dart';
import 'package:link_up/styles/styles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voice_message_package/voice_message_package.dart';

class AudioBubble extends ConsumerStatefulWidget {
  final String audioId;
  final bool isSentByMe;
  final String? chatId;

  const AudioBubble({
    super.key,
    required this.audioId,
    required this.isSentByMe,
    required this.chatId,
  });

  @override
  ConsumerState<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends ConsumerState<AudioBubble> {
  @override
  void initState() {
    super.initState();
    // Delay the provider modification until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocalFile();
    });
  }

  Future<void> _checkLocalFile() async {
    // Early return if chatId is null
    if (widget.chatId == null) {
      if (mounted) {
        ref
                .read(
                  imageLoadingStateProvider((
                    widget.audioId,
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
      final file = File(
        '${dir.path}/LinkUp storage/Audio/${widget.audioId}.m4a',
      );
      if (await file.exists()) {
        if (mounted) {
          ref
                  .read(
                    localAudioFileProvider((
                      widget.audioId,
                      widget.chatId,
                    )).notifier,
                  )
                  .state =
              file;
          ref
                  .read(
                    audioLoadingStateProvider((
                      widget.audioId,
                      widget.chatId,
                    )).notifier,
                  )
                  .state =
              false;
        }
      } else {
        if (mounted) {
          ref
                  .read(
                    audioLoadingStateProvider((
                      widget.audioId,
                      widget.chatId,
                    )).notifier,
                  )
                  .state =
              false;
        }
      }
    } catch (e) {
      if (mounted) {
        ref
                .read(
                  audioLoadingStateProvider((
                    widget.audioId,
                    widget.chatId,
                  )).notifier,
                )
                .state =
            false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      audioLoadingStateProvider((widget.audioId, widget.chatId)),
    );
    final localFile = ref.watch(
      localAudioFileProvider((widget.audioId, widget.chatId)),
    );

    if (isLoading) {
      return Container(
        width: 250,
        height: 60,
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

    if (localFile != null && localFile.existsSync()) {
      return VoiceMessageView(
        controller: VoiceController(
          audioSrc: localFile.path,
          maxDuration: const Duration(minutes: 10),
          isFile: true,
          onComplete: () {},
          onPause: () {},
          onPlaying: () {},
        ),
        innerPadding: 8,
        cornerRadius: 8,
        backgroundColor: widget.isSentByMe
            ? AppColors.primaryBlue.withOpacity(0.2)
            : Colors.grey[200]!,
        activeSliderColor: widget.isSentByMe
            ? AppColors.primaryBlue
            : AppColors.primaryBlue.withOpacity(0.7),
        notActiveSliderColor: Colors.grey[400]!,
        circlesColor: widget.isSentByMe ? AppColors.primaryBlue : Colors.grey,
        size: 35,
      );
    }
    return const SizedBox.shrink();
  }
}

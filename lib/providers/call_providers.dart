import 'package:flutter_riverpod/legacy.dart';

class Notifier extends StateNotifier<AppState> {
  Notifier()
    : super(
        AppState(
          isConnected: false,
          isMuted: false,
          isSpeaker: false,
          isCameraOff: false,
        ),
      );

  set isConnected(bool value) {
    state = state.copyWith(isConnected: value);
  }

  set isMuted(bool value) {
    state = state.copyWith(isMuted: value);
  }

  set isSpeaker(bool value) {
    state = state.copyWith(isSpeaker: value);
  }

  set isCameraOff(bool value) {
    state = state.copyWith(isCameraOff: value);
  }
}

class AppState {
  final bool isConnected;
  final bool isMuted;
  final bool isSpeaker;
  final bool isCameraOff;

  AppState({
    required this.isConnected,
    required this.isMuted,
    required this.isSpeaker,
    required this.isCameraOff,
  });

  AppState copyWith({
    bool? isConnected,
    bool? isMuted,
    bool? isSpeaker,
    bool? isCameraOff,
  }) {
    return AppState(
      isConnected: isConnected ?? this.isConnected,
      isMuted: isMuted ?? this.isMuted,
      isSpeaker: isSpeaker ?? this.isSpeaker,
      isCameraOff: isCameraOff ?? this.isCameraOff,
    );
  }
}

final callProvider = StateNotifierProvider.autoDispose<Notifier, AppState>(
  (ref) => Notifier(),
);

final loadingProvider = StateProvider.autoDispose<bool>((ref) => false);

final callDurationProvider = StateProvider.autoDispose<int>((ref) => 0);

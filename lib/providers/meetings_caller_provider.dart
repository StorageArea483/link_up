import 'package:flutter_riverpod/legacy.dart';

class Notifier extends StateNotifier<AppState> {
  Notifier() : super(AppState(value: '', isChanged: false));
  
  void search(String newValue) {
    state = state.copyWith(value: newValue);
  }

  void toggleChanged() {
    state = state.copyWith(isChanged: !state.isChanged);
  }
  
}

class AppState {
  final String value;
  final bool isChanged;

  AppState({required this.value, required this.isChanged});

  AppState copyWith({String? value, bool? isChanged}) {
    return AppState(
      value: value ?? this.value,
      isChanged: isChanged ?? this.isChanged,
    );
  }
}

final meetingsProvider = StateNotifierProvider<Notifier, AppState>((ref) => Notifier());

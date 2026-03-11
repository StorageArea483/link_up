import 'package:flutter_riverpod/legacy.dart';

final editingContactProvider = StateProvider.autoDispose<bool>((ref) => false);
final deletingContactProvider = StateProvider.autoDispose<bool>((ref) => false);

final isLoadingProvider = StateProvider.autoDispose<bool>((ref) => false);

import 'package:flutter_riverpod/legacy.dart';

final isLoadingProvider = StateProvider.autoDispose<bool>((ref) => false);

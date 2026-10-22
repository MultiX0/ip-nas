import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/wiring_chat.dart';
import 'features/wiring_intelligence.dart';
import 'features/wiring_voice_nas.dart';

void main() {
  runApp(ProviderScope(
    overrides: [
      ...chatOverrides(),
      ...intelligenceOverrides(),
      ...voiceNasOverrides(),
    ],
    child: const NurApp(),
  ));
}

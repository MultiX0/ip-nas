// Puts the chat engine behind the core chatEngineProvider (see main.dart).
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/providers.dart';
import 'chat/engine/chat_engine_provider.dart';

List<Override> chatOverrides() => [
      chatEngineProvider.overrideWith((ref) => ref.watch(chatEngineImplProvider)),
    ];

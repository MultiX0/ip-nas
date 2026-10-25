import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_engine_impl.dart';

/// Concrete engine (the UI needs regenerate/edit/branch APIs beyond the ChatEngine contract).
final chatEngineImplProvider = Provider<ChatEngineImpl>((ref) => ChatEngineImpl(ref));

// App-wide providers. The contract providers below are overridden in lib/features/wiring_*.dart.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/db/app_db.dart';
import 'contracts/chat_engine.dart';
import 'contracts/intelligence.dart';
import 'contracts/nas.dart';

final dbProvider = Provider<AppDb>((ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return db;
});

final secureStoreProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// Overridden by features/context (intelligence wiring).
final contextAssemblerProvider = Provider<ContextAssembler>((ref) => throw UnimplementedError('contextAssembler not wired'));

/// Overridden by features/tools (intelligence wiring).
final toolRuntimeProvider = Provider<ToolRuntime>((ref) => throw UnimplementedError('toolRuntime not wired'));

/// Overridden by features/chat (chat wiring).
final chatEngineProvider = Provider<ChatEngine>((ref) => throw UnimplementedError('chatEngine not wired'));

/// Overridden by features/nas (nas wiring). Null when no NAS is paired.
final nasHubProvider = Provider<NasHubClient?>((ref) => null);

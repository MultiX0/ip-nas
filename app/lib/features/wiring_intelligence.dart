// Puts the context assembler and the tool runtime behind the core providers (see main.dart).
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/providers.dart';
import 'context/context_assembler_impl.dart';
import 'tools/tool_runtime_impl.dart';

List<Override> intelligenceOverrides() => [
      contextAssemblerProvider.overrideWith((ref) => ref.watch(nurContextAssemblerProvider)),
      toolRuntimeProvider.overrideWith((ref) => ref.watch(nurToolRuntimeProvider)),
    ];

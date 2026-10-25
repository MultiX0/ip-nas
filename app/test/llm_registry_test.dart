import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/data/db/app_db.dart';
import 'package:nur/features/providers/adapters/openai_compat_client.dart';
import 'package:nur/features/providers/llm_registry.dart';

import 'helpers/chat_fakes.dart';

void main() {
  test('a NAS provider without its own key uses the hub token of its device', () async {
    final db = AppDb(NativeDatabase.memory());
    final secure = MemorySecureStorage();
    await secure.write(key: 'nas_token_abc', value: 'hub-token');
    await db.into(db.llmProviders).insert(LlmProvidersCompanion.insert(
          id: 'nas_abc',
          kind: 'nas_hub',
          name: 'NAS',
          baseUrl: 'http://192.168.1.50:8770/llm/v1',
          preset: const Value('llamacpp'),
          extraJson: Value(jsonEncode({'nas_device_id': 'abc'})),
        ));
    final reg = LlmRegistry(db, secure);
    await reg.ready;
    final client = reg.clientFor('nas_abc');
    expect(client, isA<OpenAiCompatClient>());
    expect((client! as OpenAiCompatClient).apiKey, 'hub-token');
    expect(reg.hasKey('nas_abc'), isTrue);
    reg.dispose();
    await db.close();
  });
}

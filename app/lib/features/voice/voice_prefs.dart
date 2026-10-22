// Voice settings (Settings table + secure storage) and the Fish Audio client provider.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'fish_audio.dart';

// Public ids of the Drama 3 sample voices from the Fish Audio docs.
const deliaVoiceId = 'c70cfb98867a4bfb9ae20d2401257b92';
const adrianVoiceId = 'bf322df2096a46f18c579d0baa36f41d';
const sheilaVoiceId = 'f3a2b90078d54a65af4b95f63bc7798e';

const drama3Voices = [
  FishVoice(id: deliaVoiceId, title: 'Delia', languages: ['en'], description: 'Warm, expressive (EN-US, female)'),
  FishVoice(id: adrianVoiceId, title: 'Adrian', languages: ['en'], description: 'Calm, grounded (EN-US, male)'),
  FishVoice(id: sheilaVoiceId, title: 'Sheila', languages: ['en'], description: 'Bright, theatrical (EN-US, female)'),
];

class VoicePrefs {
  const VoicePrefs({
    this.apiKey,
    this.voiceId = deliaVoiceId,
    this.voiceName = 'Delia',
    this.model = 'drama-3',
    this.latency = 'balanced',
    this.speed = 1.0,
    this.sttModel = 'transcribe-1-pro',
    this.sttLanguage = 'auto',
    this.direction = true,
  });
  final String? apiKey;
  final String voiceId;
  final String voiceName;
  final String model;
  final String latency;
  final double speed;
  final String sttModel;
  final String sttLanguage; // auto, ar or en

  /// Let the model add Drama 3 performance tags (`[warmly]`, `<whisper>`) to spoken replies.
  final bool direction;
  bool get hasKey => apiKey != null && apiKey!.trim().isNotEmpty;
}

class VoicePrefsNotifier extends AsyncNotifier<VoicePrefs> {
  @override
  Future<VoicePrefs> build() async {
    final db = ref.watch(dbProvider);
    final key = await ref.read(secureStoreProvider).read(key: 'fish_api_key');
    Future<String?> g(String k) => db.getSetting(k);
    final r = await Future.wait([
      g('voice_id'),
      g('voice_name'),
      g('voice_model'),
      g('voice_latency'),
      g('voice_speed'),
      g('stt_model'),
      g('stt_language'),
      g('voice_direction'),
    ]);
    const d = VoicePrefs();
    return VoicePrefs(
      apiKey: key,
      voiceId: (r[0]?.isNotEmpty ?? false) ? r[0]! : d.voiceId,
      voiceName: (r[1]?.isNotEmpty ?? false) ? r[1]! : (r[0] == null ? d.voiceName : 'Custom voice'),
      model: (r[2]?.isNotEmpty ?? false) ? r[2]! : d.model,
      latency: (r[3]?.isNotEmpty ?? false) ? r[3]! : d.latency,
      speed: double.tryParse(r[4] ?? '') ?? d.speed,
      sttModel: (r[5]?.isNotEmpty ?? false) ? r[5]! : d.sttModel,
      sttLanguage: (r[6]?.isNotEmpty ?? false) ? r[6]! : d.sttLanguage,
      direction: r[7] != 'false', // on by default
    );
  }

  Future<void> setSetting(String key, String value) async {
    await ref.read(dbProvider).setSetting(key, value);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setVoice(FishVoice v) async {
    final db = ref.read(dbProvider);
    await db.setSetting('voice_id', v.id);
    await db.setSetting('voice_name', v.title);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setApiKey(String? key) async {
    final store = ref.read(secureStoreProvider);
    if (key == null || key.trim().isEmpty) {
      await store.delete(key: 'fish_api_key');
    } else {
      await store.write(key: 'fish_api_key', value: key.trim());
    }
    ref.invalidateSelf();
    await future;
  }
}

final voicePrefsProvider = AsyncNotifierProvider<VoicePrefsNotifier, VoicePrefs>(VoicePrefsNotifier.new);

/// Fish Audio client for the saved key (null when no key is set).
final fishAudioProvider = Provider<FishAudio?>((ref) {
  final key = ref.watch(voicePrefsProvider.select((p) => p.value?.apiKey));
  if (key == null || key.trim().isEmpty) return null;
  final c = FishAudio(key.trim());
  ref.onDispose(c.close);
  return c;
});

const missingKeyMessage = 'Add your Fish Audio API key in the voice settings to use voice features.';

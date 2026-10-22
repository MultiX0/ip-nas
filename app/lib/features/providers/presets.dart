// One-tap provider presets.
class ProviderPreset {
  final String id;
  final String name;
  final String kind; // openai_compat | ollama | anthropic
  final String baseUrl;
  final bool needsKey;
  final bool local;
  final String? keyUrl;
  final String subtitle;
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.needsKey = true,
    this.local = false,
    this.keyUrl,
    required this.subtitle,
  });
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(id: 'llamacpp', name: 'llama.cpp', kind: 'openai_compat', baseUrl: 'http://192.168.1.50:8080/v1', needsKey: false, local: true, subtitle: 'llama-server on your NAS or PC'),
  ProviderPreset(id: 'ollama', name: 'Ollama', kind: 'ollama', baseUrl: 'http://192.168.1.50:11434', needsKey: false, local: true, subtitle: 'Local models with Ollama'),
  ProviderPreset(id: 'lmstudio', name: 'LM Studio', kind: 'openai_compat', baseUrl: 'http://192.168.1.50:1234/v1', needsKey: false, local: true, subtitle: 'LM Studio local server'),
  ProviderPreset(id: 'vllm', name: 'vLLM', kind: 'openai_compat', baseUrl: 'http://192.168.1.50:8000/v1', needsKey: false, local: true, subtitle: 'vLLM OpenAI server'),
  ProviderPreset(id: 'openai', name: 'OpenAI', kind: 'openai_compat', baseUrl: 'https://api.openai.com/v1', keyUrl: 'https://platform.openai.com/api-keys', subtitle: 'GPT-5, GPT-4.1, o-series'),
  ProviderPreset(id: 'anthropic', name: 'Anthropic', kind: 'anthropic', baseUrl: 'https://api.anthropic.com', keyUrl: 'https://console.anthropic.com/settings/keys', subtitle: 'Claude models'),
  ProviderPreset(id: 'gemini', name: 'Google Gemini', kind: 'openai_compat', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai', keyUrl: 'https://aistudio.google.com/apikey', subtitle: 'Gemini via the OpenAI endpoint'),
  ProviderPreset(id: 'openrouter', name: 'OpenRouter', kind: 'openai_compat', baseUrl: 'https://openrouter.ai/api/v1', keyUrl: 'https://openrouter.ai/keys', subtitle: 'Hundreds of models, one key'),
  ProviderPreset(id: 'groq', name: 'Groq', kind: 'openai_compat', baseUrl: 'https://api.groq.com/openai/v1', keyUrl: 'https://console.groq.com/keys', subtitle: 'Very fast open models'),
  ProviderPreset(id: 'deepseek', name: 'DeepSeek', kind: 'openai_compat', baseUrl: 'https://api.deepseek.com/v1', keyUrl: 'https://platform.deepseek.com/api_keys', subtitle: 'DeepSeek chat and reasoner'),
  ProviderPreset(id: 'mistral', name: 'Mistral', kind: 'openai_compat', baseUrl: 'https://api.mistral.ai/v1', keyUrl: 'https://console.mistral.ai/api-keys', subtitle: 'Mistral and Magistral'),
  ProviderPreset(id: 'xai', name: 'xAI', kind: 'openai_compat', baseUrl: 'https://api.x.ai/v1', keyUrl: 'https://console.x.ai', subtitle: 'Grok models'),
  ProviderPreset(id: 'together', name: 'Together AI', kind: 'openai_compat', baseUrl: 'https://api.together.xyz/v1', keyUrl: 'https://api.together.ai/settings/api-keys', subtitle: 'Open models in the cloud'),
  ProviderPreset(id: 'custom', name: 'Custom (OpenAI-compatible)', kind: 'openai_compat', baseUrl: 'http://', needsKey: false, subtitle: 'Any /v1/chat/completions server'),
];

ProviderPreset? presetById(String? id) {
  for (final p in providerPresets) {
    if (p.id == id) return p;
  }
  return null;
}

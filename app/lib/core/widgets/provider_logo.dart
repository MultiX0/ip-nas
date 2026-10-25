// Brand logos for providers and model families (Lobe Icons, MIT, see assets/logos/LICENSE-lobe-icons.txt).
// Mono logos follow the text colour (light/dark); "-color" logos keep their brand colours.
// Fish Audio is the exception: its official logo files, never recoloured ([FishAudioLogo], assets/logos/NOTICE-fish-audio.txt).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'nur_logo.dart';

const _presetLogo = <String, String>{
  'openai': 'openai',
  'anthropic': 'claude-color',
  'gemini': 'gemini-color',
  'google': 'gemini-color',
  'openrouter': 'openrouter',
  'groq': 'groq',
  'deepseek': 'deepseek-color',
  'mistral': 'mistral-color',
  'xai': 'xai',
  'together': 'together-color',
  'lmstudio': 'lmstudio',
  'vllm': 'vllm-color',
  'perplexity': 'perplexity-color',
  'fireworks': 'fireworks-color',
  'azure': 'azure-color',
  'nvidia': 'nvidia-color',
  'cohere': 'cohere-color',
  'huggingface': 'huggingface-color',
  'moonshot': 'moonshot',
  'kimi': 'kimi-color',
  'zai': 'zai',
  'fishaudio': 'fishaudio',
  'mcp': 'mcp',
  'searxng': 'searxng-color',
};

/// Model family by id (checked in order; first match wins).
const _familyLogo = <(String, String)>[
  ('qwen', 'qwen-color'),
  ('qwq', 'qwen-color'),
  ('gemma', 'gemma-color'),
  ('gemini', 'gemini-color'),
  ('claude', 'claude-color'),
  ('gpt', 'openai'),
  ('o1', 'openai'),
  ('o3', 'openai'),
  ('o4', 'openai'),
  ('llama', 'meta-color'),
  ('mistral', 'mistral-color'),
  ('mixtral', 'mistral-color'),
  ('magistral', 'mistral-color'),
  ('devstral', 'mistral-color'),
  ('deepseek', 'deepseek-color'),
  ('phi', 'microsoft-color'),
  ('granite', 'ibm'),
  ('lfm', 'liquid'),
  ('grok', 'grok'),
  ('kimi', 'kimi-color'),
  ('glm', 'zai'),
  ('hermes', 'nousresearch'),
  ('command', 'cohere-color'),
  ('nemotron', 'nvidia-color'),
];

String? logoFileFor({String? preset, String? kind, String? modelId}) {
  final id = (modelId ?? '').toLowerCase();
  if (id.isNotEmpty) {
    for (final (k, f) in _familyLogo) {
      if (id.contains(k)) return f;
    }
  }
  if (kind == 'anthropic') return 'claude-color';
  final p = (preset ?? '').toLowerCase();
  return _presetLogo[p];
}

/// Logo for a provider (preset/kind) or a model (modelId wins when its family is known).
/// NAS providers show the Nur mark; unknown ones a neutral monogram.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo({super.key, this.preset, this.kind, this.modelId, this.name, this.size = 18});
  final String? preset;
  final String? kind;
  final String? modelId;
  final String? name; // used for the monogram fallback
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = logoFileFor(preset: preset, kind: kind, modelId: modelId);
    if (file == 'fishaudio') return FishAudioLogo(size: size); // official file, not the Lobe drawing
    final fg = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    if (file == null) {
      if (kind == 'nas_hub' || preset == 'nas') return NurLogo(size: size, color: fg);
      return _Monogram(text: name ?? modelId ?? preset ?? '?', size: size, color: fg);
    }
    final mono = !file.endsWith('-color');
    return SvgPicture.asset(
      'assets/logos/$file.svg',
      width: size,
      height: size,
      colorFilter: mono ? ColorFilter.mode(fg, BlendMode.srcIn) : null,
      placeholderBuilder: (_) => SizedBox.square(dimension: size),
    );
  }
}

/// Fish Audio's official logo (their brand files, assets/logos/NOTICE-fish-audio.txt).
/// Brand rules: never recoloured, distorted, rotated or given effects, so this picks their white file on dark
/// backgrounds and their black file on light ones instead of tinting one file.
class FishAudioLogo extends StatelessWidget {
  const FishAudioLogo({
    super.key,
    this.size = 18,
    this.wordmark = false,
    this.onDark,
    this.opacity = 1,
    this.excludeFromSemantics = false,
  });

  /// Lockup: the logo's height (its "Fish Audio" letters are ~58 % of it).
  /// Icon: the side of the square it sits in, like [Icon.size]; the 118 x 44 icon is `size` wide.
  final double size;

  /// true: the lockup (icon + "Fish Audio"), Fish Audio's preferred form.
  /// false: the icon alone, only where the lockup does not fit.
  final bool wordmark;

  /// Whether the background behind the logo is dark (white file) or light (black file).
  /// Null follows the theme's brightness.
  final bool? onDark;

  /// For a quiet attribution mark: fades the official file as a whole instead of recolouring it (see [quiet]).
  final double opacity;

  /// For spots whose parent already says "Fish Audio" to screen readers.
  final bool excludeFromSemantics;

  /// [opacity] for a quiet mark: over the call screen's pure white / black it turns the logo's black / white into
  /// about #B2B2B2 / #4D4D4D, close to Fish Audio's own secondary greys (#B1B3B4 / #4E4C4B).
  static const quiet = 0.3;

  static const lockupAspect = 323 / 44; // FishAudio-Horizontal-*.svg
  static const iconAspect = 118 / 44; // the icon's own clip area in that file

  static String assetFor({required bool wordmark, required bool onDark}) =>
      'assets/logos/fishaudio-${wordmark ? 'lockup' : 'icon'}-${onDark ? 'white' : 'black'}.svg';

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    final height = wordmark ? size : size / iconAspect;
    final width = height * (wordmark ? lockupAspect : iconAspect);
    Widget logo = SvgPicture.asset(
      assetFor(wordmark: wordmark, onDark: dark),
      width: width,
      height: height,
      semanticsLabel: 'Fish Audio',
      excludeFromSemantics: excludeFromSemantics,
      placeholderBuilder: (_) => SizedBox(width: width, height: height),
    );
    if (opacity < 1) logo = Opacity(opacity: opacity, child: logo);
    // The icon sits in a square box like [Icon], so it lines up with the other provider logos.
    return wordmark ? logo : SizedBox.square(dimension: size, child: Center(child: logo));
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.text, required this.size, required this.color});
  final String text;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    final ch = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.5), width: 1)),
      child: Text(ch, style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w700, color: color, height: 1)),
    );
  }
}

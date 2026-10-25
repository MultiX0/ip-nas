// Bottom bar of the call screen: mute, captions, voice picker and a red end button, all equal round buttons.
// Colours follow the call screen's light or dark look ([CallColors]).
import 'package:flutter/material.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import 'voice_fx.dart';
import 'voice_orb.dart';

/// Colours of the call screen: pure black or white, quiet greys for everything else.
@immutable
class CallColors {
  const CallColors._({
    required this.light,
    required this.bg,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.button,
    required this.buttonHover,
    required this.border,
    required this.chip,
  });
  final bool light;
  final Color bg;
  final Color fg;
  final Color muted;
  final Color faint;
  final Color button;
  final Color buttonHover;
  final Color border;
  final Color chip;

  static const end = Color(0xFFF0443A);

  static const dark = CallColors._(
    light: false,
    bg: Color(0xFF000000),
    fg: Color(0xFFFFFFFF),
    muted: NurColors.g500,
    faint: NurColors.g700,
    button: Color(0xFF1C1C1E),
    buttonHover: Color(0xFF2A2A2D),
    border: Color(0x14FFFFFF),
    chip: Color(0x14FFFFFF),
  );
  static const lightColors = CallColors._(
    light: true,
    bg: Color(0xFFFFFFFF),
    fg: Color(0xFF0D0D0D),
    muted: NurColors.g600,
    faint: NurColors.g400,
    button: Color(0xFFF1F1F2),
    buttonHover: Color(0xFFE6E6E8),
    border: Color(0x0F000000),
    chip: Color(0x0D000000),
  );

  static CallColors of(bool light) => light ? lightColors : dark;
}

class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.colors,
    required this.muted,
    required this.captions,
    required this.voiceName,
    required this.voiceTint,
    required this.voiceSeed,
    this.onMute,
    this.onCaptions,
    this.onVoice,
    required this.onEnd,
  });
  final CallColors colors;
  final bool muted;
  final bool captions;
  final String voiceName;
  final Color voiceTint;
  final double voiceSeed;
  final VoidCallback? onMute;
  final VoidCallback? onCaptions;
  final VoidCallback? onVoice;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final k = colors;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth < 340 ? 52.0 : 58.0;
        final icon = size * 0.40;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallButton(
                colors: k,
                tooltip: muted ? 'Turn microphone on' : 'Mute microphone',
                size: size,
                selected: muted,
                onTap: onMute == null
                    ? null
                    : () {
                        haptic(Haptic.toggle);
                        onMute!();
                      },
                child: Icon(muted ? NurIcons.micOff : NurIcons.mic, size: icon, color: muted ? k.bg : k.fg),
              ),
              CallButton(
                colors: k,
                tooltip: captions ? 'Hide captions' : 'Show captions',
                size: size,
                onTap: onCaptions == null
                    ? null
                    : () {
                        haptic(Haptic.tap);
                        onCaptions!();
                      },
                child: Icon(captions ? NurIcons.captions : NurIcons.captionsOff, size: icon, color: captions ? k.fg : k.muted),
              ),
              CallButton(
                colors: k,
                tooltip: 'Voice: $voiceName',
                size: size,
                onTap: onVoice == null
                    ? null
                    : () {
                        haptic(Haptic.tap);
                        onVoice!();
                      },
                child: VoiceOrbAvatar(tint: voiceTint, seed: voiceSeed, size: size * 0.56, well: false),
              ),
              CallButton(
                colors: k,
                tooltip: 'End call',
                size: size,
                color: CallColors.end,
                onTap: () {
                  haptic(Haptic.heavy);
                  onEnd();
                },
                child: Icon(NurIcons.close, size: icon * 1.05, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Round button with a press-scale animation and hover state.
class CallButton extends StatefulWidget {
  const CallButton({
    super.key,
    required this.colors,
    required this.tooltip,
    required this.child,
    this.onTap,
    this.size = 58,
    this.selected = false,
    this.color,
  });
  final CallColors colors;
  final String tooltip;
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final bool selected;
  final Color? color;
  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final k = widget.colors;
    final enabled = widget.onTap != null;
    final Color bg;
    if (widget.color != null) {
      bg = _hover ? Color.lerp(widget.color, Colors.white, 0.10)! : widget.color!;
    } else if (widget.selected) {
      bg = k.fg;
    } else {
      bg = _hover ? k.buttonHover : k.button;
    }
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        toggled: widget.color == null ? widget.selected : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: enabled ? 1 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: widget.size,
                  height: widget.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: widget.color == null && !widget.selected ? Border.all(color: k.border) : null,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

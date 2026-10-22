// Call status line (a quiet phase label, "Thinking" shimmer, tool chips) and optional live captions: the
// user's last words on one muted line and Nur's reply revealed word by word, at most two lines, older lines
// fading out at the top. RTL per caption (Arabic).
import 'package:flutter/material.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/utils/text_dir.dart';
import '../../core/widgets/nur_icons.dart';
import 'call_controls.dart';
import 'call_view_model.dart';
import 'voice_fx.dart';

/// One quiet line under the orb: the tool chip if a tool runs, else the phase label (shimmering while busy).
class CallStatusLine extends StatelessWidget {
  const CallStatusLine({super.key, required this.view, required this.colors, this.touch = true});
  final CallViewModel view;
  final CallColors colors;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final k = colors;
    Widget child;
    if (v.tool != null) {
      child = ToolChip(key: ValueKey('tool:${v.tool}'), label: v.tool!, kind: v.toolKind ?? ToolKind.generic, colors: k);
    } else {
      final (text, shimmer) = switch (v.phase) {
        CallPhase.connecting => ('Connecting', true),
        CallPhase.thinking => ('Thinking', true),
        CallPhase.listening => (v.muted ? 'Microphone is off' : 'Listening', false),
        CallPhase.speaking => (touch ? 'Tap the orb to interrupt' : 'Click the orb or just talk to interrupt', false),
        CallPhase.ended => ('Call ended', false),
      };
      final style = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: k.muted);
      child = shimmer
          ? ShimmerText(text, key: ValueKey(text), style: style, baseColor: k.faint, highlightColor: k.fg)
          : Text(
              text,
              key: ValueKey(text),
              style: style.copyWith(color: v.phase == CallPhase.speaking ? k.faint : k.muted),
            );
    }
    return SizedBox(
      height: 34,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
              child: c,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// "Checking the NAS..." with an icon and a shimmer.
class ToolChip extends StatelessWidget {
  const ToolChip({super.key, required this.label, required this.kind, required this.colors});
  final String label;
  final ToolKind kind;
  final CallColors colors;

  @override
  Widget build(BuildContext context) {
    final k = colors;
    final icon = switch (kind) {
      ToolKind.nas => NurIcons.nas,
      ToolKind.web => NurIcons.webSearch,
      ToolKind.memory => NurIcons.memory,
      ToolKind.generic => NurIcons.flash,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: k.chip,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: k.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingIcon(icon: icon, color: k.fg),
          const SizedBox(width: 8),
          ShimmerText(
            label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            baseColor: k.muted,
            highlightColor: k.fg,
          ),
        ],
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _a, curve: Curves.easeInOut)),
    child: Icon(widget.icon, size: 15, color: widget.color),
  );
}

/// User transcript (one muted line) and Nur's caption revealed word by word as it is spoken.
class CallCaptions extends StatelessWidget {
  const CallCaptions({super.key, required this.view, required this.revealed, required this.colors, this.maxWidth = 560, this.lines = 2});
  final CallViewModel view;
  final ValueNotifier<int> revealed;
  final CallColors colors;
  final double maxWidth;
  final int lines;

  /// Height the captions need for [lines] of Nur's text plus the user line.
  static double heightFor(int lines) => _RevealText.lineHeight * lines + _userH;
  static const _userH = 30.0;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final k = colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _userH,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: v.userCaption.isEmpty
                  ? const SizedBox.shrink(key: ValueKey('nouser'))
                  : Align(
                      key: ValueKey(v.userCaption),
                      alignment: Alignment.topCenter,
                      child: Text(
                        v.userCaption,
                        textAlign: TextAlign.center,
                        textDirection: textDirOf(v.userCaption),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: k.muted, fontSize: 14.5, height: 1.35),
                      ),
                    ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: revealed,
            builder: (c, n, _) => _RevealText(text: v.assistantCaption, revealed: n, lines: lines, color: k.fg),
          ),
        ],
      ),
    );
  }
}

class _RevealText extends StatefulWidget {
  const _RevealText({required this.text, required this.revealed, required this.lines, required this.color});
  final String text;
  final int revealed;
  final int lines;
  final Color color;

  static const fontSize = 19.0;
  static const height = 1.45;
  static const lineHeight = fontSize * height;

  @override
  State<_RevealText> createState() => _RevealTextState();
}

class _RevealTextState extends State<_RevealText> with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  }

  int _from = 0; // words before this index are fully visible
  static final _split = RegExp(r'(\s+)');

  @override
  void didUpdateWidget(_RevealText old) {
    super.didUpdateWidget(old);
    if (widget.revealed > old.revealed) {
      _from = old.revealed.clamp(0, widget.revealed);
      _fade.forward(from: 0);
    } else if (widget.revealed < old.revealed) {
      _from = widget.revealed;
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final n = widget.revealed;
    final dir = textDirOf(text);
    final box = _RevealText.lineHeight * widget.lines;
    if (text.isEmpty || n == 0) return SizedBox(height: box);
    final style = TextStyle(
      color: widget.color,
      fontSize: _RevealText.fontSize,
      height: _RevealText.height,
      fontWeight: FontWeight.w500,
      letterSpacing: dir == TextDirection.rtl ? 0 : -0.15,
    );

    // Words and their separators, so spacing (and Arabic shaping inside words) stays intact.
    final parts = <String>[];
    text.trim().splitMapJoin(
      _split,
      onMatch: (m) {
        parts.add(m[0]!);
        return '';
      },
      onNonMatch: (s) {
        if (s.isNotEmpty) parts.add(s);
        return '';
      },
    );

    final shown = StringBuffer();
    var count = 0;
    for (final p in parts) {
      if (p.trim().isNotEmpty) {
        if (count >= n) break;
        count++;
      }
      shown.write(p);
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Fade the top only when the reply no longer fits (older lines scroll away under the fade).
        final tp = TextPainter(
          text: TextSpan(text: shown.toString(), style: style),
          textDirection: dir,
          textAlign: TextAlign.center,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final overflow = tp.height > box + 1;
        tp.dispose();
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: box),
          child: ShaderMask(
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
              stops: [0.0, overflow ? 0.45 : 0.0, 1.0],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              reverse: true,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _fade,
                  builder: (c, _) {
                    final spans = <InlineSpan>[];
                    var word = 0;
                    for (final p in parts) {
                      final isSpace = p.trim().isEmpty;
                      if (!isSpace) {
                        if (word >= n) break;
                        final fresh = word >= _from;
                        final a = fresh ? Curves.easeOut.transform(_fade.value) : 1.0;
                        spans.add(
                          TextSpan(
                            text: p,
                            style: fresh ? style.copyWith(color: widget.color.withValues(alpha: a)) : null,
                          ),
                        );
                        word++;
                      } else {
                        spans.add(TextSpan(text: p));
                      }
                    }
                    return Text.rich(
                      TextSpan(style: style, children: spans),
                      textAlign: TextAlign.center,
                      textDirection: dir,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small notice at the top of the call (recoverable problems).
class CallNotice extends StatelessWidget {
  const CallNotice({super.key, required this.text, required this.colors});
  final String text;
  final CallColors colors;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: NurColors.warn.withValues(alpha: colors.light ? 0.12 : 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: NurColors.warn.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(NurIcons.info, size: 15, color: NurColors.warn),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textDirection: textDirOf(text),
            style: TextStyle(color: colors.fg.withValues(alpha: 0.8), fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

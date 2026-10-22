// Small building blocks shared by every screen (pressables, icon buttons, skeletons, empty states, toasts,
// settings rows), so hover, press and focus states, radii and motion look the same everywhere.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/desktop.dart';
import '../theme/nur_theme.dart';
import 'nur_icons.dart';

/// A tappable surface with Nur's interaction states: hover tint, press scale, focus ring (keyboard only),
/// Enter/Space activation, pointer cursor and optional tooltip.
class NurPressable extends StatefulWidget {
  const NurPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.borderRadius = const BorderRadius.all(Radius.circular(NurRadius.control)),
    this.shape = BoxShape.rectangle,
    this.color,
    this.hoverColor,
    this.selected = false,
    this.selectedColor,
    this.border,
    this.padding,
    this.tooltip,
    this.pressedScale = 0.97,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final BorderRadius borderRadius;
  final BoxShape shape;
  final Color? color;
  final Color? hoverColor;
  final bool selected;
  final Color? selectedColor;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;
  final double pressedScale;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  @override
  State<NurPressable> createState() => _NurPressableState();
}

class _NurPressableState extends State<NurPressable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  bool get _enabled => widget.enabled && (widget.onTap != null || widget.onLongPress != null || widget.onSecondaryTapUp != null);

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final fg = Theme.of(context).colorScheme.onSurface;
    final base = widget.color ?? Colors.transparent;
    final hover = widget.hoverColor ?? nur.hover;
    Color bg = base;
    if (widget.selected) bg = widget.selectedColor ?? nur.hover;
    if (_enabled && _hover && !widget.selected) bg = Color.alphaBlend(hover.withValues(alpha: hover.a * 0.85), base);
    if (_enabled && _pressed) bg = Color.alphaBlend(fg.withValues(alpha: 0.06), bg);
    final circle = widget.shape == BoxShape.circle;

    Widget body = AnimatedContainer(
      duration: NurMotion.fast,
      curve: NurMotion.curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg,
        shape: widget.shape,
        borderRadius: circle ? null : widget.borderRadius,
        border: widget.border,
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              shape: widget.shape,
              borderRadius: circle ? null : widget.borderRadius,
              border: Border.all(color: fg.withValues(alpha: 0.55), width: 2),
            )
          : null,
      child: widget.child,
    );
    if (widget.pressedScale != 1) {
      body = AnimatedScale(scale: _pressed ? widget.pressedScale : 1, duration: NurMotion.fast, curve: NurMotion.curve, child: body);
    }
    body = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled && widget.onTap != null ? (_) => _setPressed(true) : null,
        onTapUp: _enabled && widget.onTap != null ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled && widget.onTap != null ? () => _setPressed(false) : null,
        onTap: _enabled ? widget.onTap : null,
        onLongPress: _enabled ? widget.onLongPress : null,
        onSecondaryTapUp: _enabled ? widget.onSecondaryTapUp : null,
        child: body,
      ),
    );
    body = Semantics(button: true, enabled: _enabled, label: widget.semanticLabel ?? widget.tooltip, child: body);
    final tip = widget.tooltip;
    return tip == null || tip.isEmpty ? body : Tooltip(message: tip, child: body);
  }
}

/// Square, quiet icon button (ChatGPT style): muted icon, rounded hover tile, focus ring.
class NurIconButton extends StatelessWidget {
  const NurIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 20,
    this.box,
    this.color,
    this.selected = false,
    this.filled = false,
    this.circle = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  /// Hit box edge (defaults to icon size + 14).
  final double? box;
  final Color? color;
  final bool selected;

  /// Solid primary (black/white) background, e.g. the send button.
  final bool filled;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final s = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final edge = box ?? size + 14;
    final fg = filled ? s.onPrimary : (!enabled ? nur.subtle.withValues(alpha: 0.6) : (color ?? (selected ? s.onSurface : nur.muted)));
    return NurPressable(
      onTap: onTap,
      tooltip: tooltip,
      selected: selected,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: BorderRadius.circular(edge >= 36 ? NurRadius.control : NurRadius.sm),
      color: filled ? (enabled ? s.primary : s.onSurface.withValues(alpha: 0.2)) : null,
      hoverColor: filled ? s.primary.withValues(alpha: 0.85) : null,
      pressedScale: filled ? 0.92 : 0.94,
      child: SizedBox.square(dimension: edge, child: Center(child: Icon(icon, size: size, color: fg))),
    );
  }
}

/// Copy button that morphs into a check mark for a moment after copying (no snackbar needed).
class CopyButton extends StatefulWidget {
  const CopyButton({super.key, required this.text, this.size = 16, this.tooltip = 'Copy', this.box, this.color});

  /// Text to copy, read on tap (so long texts are only built when needed).
  final String Function() text;
  final double size;
  final String tooltip;
  final double? box;
  final Color? color;
  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _done = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final t = widget.text();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _done = true);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final edge = widget.box ?? widget.size + 14;
    return NurPressable(
      onTap: _copy,
      tooltip: _done ? 'Copied' : widget.tooltip,
      borderRadius: BorderRadius.circular(NurRadius.sm),
      pressedScale: 0.92,
      child: SizedBox.square(
        dimension: edge,
        child: Center(
          child: AnimatedSwitcher(
            duration: NurMotion.base,
            switchInCurve: NurMotion.emphasized,
            transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
            child: Icon(
              _done ? NurIcons.check : NurIcons.copy,
              key: ValueKey(_done),
              size: widget.size,
              color: _done ? Theme.of(context).colorScheme.onSurface : (widget.color ?? nur.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Provides one shared shimmer animation to the [NurSkeleton]s below it.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});
  final Widget child;
  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseC = dark ? NurColors.g850 : NurColors.g100;
    final hiC = dark ? NurColors.g800 : NurColors.g50;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = rtl ? 1 - _c.value : _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(-1.6 + 3.2 * t - 0.6, 0),
            end: Alignment(-1.6 + 3.2 * t + 0.6, 0),
            colors: [baseC, hiC, baseC],
            stops: const [0.1, 0.5, 0.9],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}

/// A rounded placeholder block (use inside [SkeletonShimmer]).
class NurSkeleton extends StatelessWidget {
  const NurSkeleton({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? NurColors.g850 : NurColors.g100,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder list: rows of [leading] circle/tile + two text lines, or [cards] for card lists.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.leading = true, this.cards = false, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16), this.dense = false});
  final int count;
  final bool leading;
  final bool cards;
  final bool dense;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final widths = [0.62, 0.48, 0.72, 0.55, 0.4, 0.66, 0.5, 0.58];
    final scheme = Theme.of(context).colorScheme;
    return SkeletonShimmer(
      child: LayoutBuilder(
        builder: (context, box) => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: count,
          itemBuilder: (c, i) {
            final w = (box.maxWidth.isFinite ? box.maxWidth : 320) * widths[i % widths.length];
            final row = Row(children: [
              if (leading) ...[
                NurSkeleton(height: dense ? 20 : 32, radius: NurRadius.sm),
                SizedBox(width: dense ? 10 : 14),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  NurSkeleton(width: w * (dense ? 0.9 : 0.75), height: dense ? 10 : 12),
                  if (!dense) ...[const SizedBox(height: 8), NurSkeleton(width: w * 0.5, height: 10)],
                ]),
              ),
            ]);
            if (!cards) return Padding(padding: EdgeInsets.symmetric(vertical: dense ? 9 : 12, horizontal: 4), child: row);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(NurRadius.card), border: Border.all(color: scheme.outlineVariant)),
              child: row,
            );
          },
        ),
      ),
    );
  }
}

/// Centered empty / error state with a small drawn illustration (halo rings + icon tile + sparkles).
class NurEmptyState extends StatelessWidget {
  const NurEmptyState({super.key, required this.icon, required this.title, this.body, this.action, this.secondary, this.tone, this.compact = false});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final Widget? secondary;

  /// Accent for the illustration (defaults to monochrome; use NurColors.danger for errors).
  final Color? tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 20 : 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: AppearIn(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              EmptyIllustration(icon: icon, tone: tone, size: compact ? 96 : 128),
              SizedBox(height: compact ? 12 : 18),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              if (body != null && body!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(body!, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, height: 1.45, fontSize: 14)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
              if (secondary != null) ...[const SizedBox(height: 8), secondary!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The illustration used by [NurEmptyState]: soft concentric rings, an elevated icon tile, a few sparkles.
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({super.key, required this.icon, this.tone, this.size = 128});
  final IconData icon;
  final Color? tone;
  final double size;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fg = theme.colorScheme.onSurface;
    final accent = tone ?? fg;
    final tile = size * 0.44;
    return SizedBox.square(
      dimension: size,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: CustomPaint(painter: _HaloPainter(accent, dark))),
        Container(
          width: tile,
          height: tile,
          decoration: BoxDecoration(
            color: dark ? NurColors.g850 : Colors.white,
            borderRadius: BorderRadius.circular(tile * 0.3),
            border: Border.all(color: dark ? NurColors.g700 : NurColors.g200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Icon(icon, size: tile * 0.46, color: tone ?? fg.withValues(alpha: 0.85)),
        ),
      ]),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.color, this.dark);
  final Color color;
  final bool dark;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: dark ? 0.10 : 0.06), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    ring.color = color.withValues(alpha: dark ? 0.16 : 0.10);
    canvas.drawCircle(c, r * 0.62, ring);
    ring.color = color.withValues(alpha: dark ? 0.09 : 0.06);
    canvas.drawCircle(c, r * 0.9, ring);
    // Sparkles on the rings (the "light" motif of the logo).
    final dot = Paint()..color = color.withValues(alpha: dark ? 0.55 : 0.4);
    for (final (a, rr, d) in const [(-0.8, 0.62, 2.6), (2.2, 0.9, 2.0), (0.9, 0.9, 1.6), (3.7, 0.62, 1.8)]) {
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * rr, d, dot);
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.color != color || old.dark != dark;
}

enum NurToastKind { info, success, warning, error }

/// Shows a floating toast (icon + message). Replaces the current one. Desktop: compact, bottom center.
void showNurToast(BuildContext context, String message, {NurToastKind kind = NurToastKind.info, IconData? icon, String? actionLabel, VoidCallback? onAction, Duration? duration}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final onInverse = dark ? NurColors.g900 : Colors.white;
  final (IconData ic, Color ico) = switch (kind) {
    NurToastKind.success => (NurIcons.success, dark ? const Color(0xFF0E8F6F) : const Color(0xFF34D3A6)),
    NurToastKind.warning => (NurIcons.warning, NurColors.warn),
    NurToastKind.error => (NurIcons.error, dark ? const Color(0xFFDC2626) : const Color(0xFFF87171)),
    NurToastKind.info => (NurIcons.info, onInverse.withValues(alpha: 0.7)),
  };
  final desktop = isDesktopLayout(context);
  final long = message.length > 90;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      width: desktop ? 440 : null,
      duration: duration ?? Duration(milliseconds: long || kind == NurToastKind.error ? 5200 : 3200),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
      content: Row(children: [
        Icon(icon ?? ic, size: 18, color: ico),
        const SizedBox(width: 10),
        Expanded(child: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis)),
      ]),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}

/// Guesses the toast kind from a plain message (keeps old call sites short).
NurToastKind toastKindOf(String message) {
  final m = message.toLowerCase();
  if (RegExp(r'(fail|error|could not|cannot|can.t|unable|denied|invalid|refused|timeout|timed out|not reachable)').hasMatch(m)) return NurToastKind.error;
  if (RegExp(r'^(copied|saved|connected|downloaded|deleted|exported|updated|done|installed|removed|default model set|chat exported|models updated|runtime installed)').hasMatch(m)) {
    return NurToastKind.success;
  }
  return NurToastKind.info;
}

/// Small uppercase section label above a [NurGroup].
class NurSectionLabel extends StatelessWidget {
  const NurSectionLabel(this.text, {super.key, this.padding = const EdgeInsetsDirectional.fromSTEB(6, 20, 6, 8), this.trailing});
  final String text;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 0.7, fontWeight: FontWeight.w600, color: context.nur.muted)),
          ),
          ?trailing,
        ]),
      );
}

/// A rounded container that groups rows with hairline dividers (iOS / ChatGPT settings style).
class NurGroup extends StatelessWidget {
  const NurGroup({super.key, required this.children, this.margin = const EdgeInsets.only(bottom: 8)});
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant.withValues(alpha: 0.7)));
      rows.add(children[i]);
    }
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
        borderRadius: BorderRadius.circular(NurRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(type: MaterialType.transparency, child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
    );
  }
}

/// Leading icon in a soft rounded tile (settings rows, cards).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 32, this.color, this.background});
  final IconData icon;
  final double size;
  final Color? color;
  final Color? background;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? (dark ? NurColors.g800 : NurColors.g100), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.55, color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85)),
    );
  }
}

/// Settings row: icon tile, title, subtitle, trailing (chevron when tappable and nothing else is given).
class NurTile extends StatelessWidget {
  const NurTile({super.key, this.icon, this.leading, required this.title, this.subtitle, this.trailing, this.bottom, this.onTap, this.danger = false, this.showChevron = true, this.dense = false});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Full-width control under the title (e.g. a segmented button on narrow screens).
  final Widget? bottom;
  final VoidCallback? onTap;
  final bool danger;
  final bool showChevron;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final lead = leading ?? (icon == null ? null : IconTile(icon!, color: danger ? NurColors.danger : null, background: danger ? NurColors.danger.withValues(alpha: 0.1) : null));
    final trail = trailing ?? (onTap != null && showChevron ? Icon(NurIcons.chevron, size: 18, color: nur.subtle) : null);
    return NurPressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      pressedScale: 1,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 10 : 13),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: danger ? NurColors.danger : null)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 13, color: nur.muted, height: 1.35)),
              ],
              if (bottom != null) ...[const SizedBox(height: 10), bottom!],
            ]),
          ),
          if (trail != null) ...[const SizedBox(width: 12), trail],
        ]),
      ),
    );
  }
}

/// Settings row with a switch (whole row toggles).
class NurSwitchTile extends StatelessWidget {
  const NurSwitchTile({super.key, this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => NurTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

/// Keyboard shortcut hint ("Ctrl K") in a subtle key cap.
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Text(text.replaceAll('+', ' '), style: TextStyle(fontSize: 10.5, color: nur.subtle, fontWeight: FontWeight.w500, letterSpacing: 0.2)),
    );
  }
}

/// Small outlined tag (sizes, capabilities, languages).
class NurTag extends StatelessWidget {
  const NurTag(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nur.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NurRadius.pill),
        color: color?.withValues(alpha: 0.1),
        border: Border.all(color: color?.withValues(alpha: 0.3) ?? Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Fades and lifts [child] in once when first built (when [enabled]). Used for new messages and states.
class AppearIn extends StatefulWidget {
  const AppearIn({super.key, required this.child, this.enabled = true, this.offset = 8, this.duration = NurMotion.slow, this.delay = Duration.zero});
  final Widget child;
  final bool enabled;
  final double offset;
  final Duration duration;
  final Duration delay;
  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  // Built once: a CurvedAnimation made in build() adds a listener to the controller on every rebuild, and the
  // latest reply rebuilds often while it streams.
  CurvedAnimation? _a;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      final c = _c = AnimationController(vsync: this, duration: widget.duration);
      _a = CurvedAnimation(parent: c, curve: NurMotion.curve);
      if (widget.delay == Duration.zero) {
        c.forward();
      } else {
        Future<void>.delayed(widget.delay, () {
          if (mounted) c.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _a?.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return widget.child;
    return FadeTransition(
      opacity: a,
      child: AnimatedBuilder(
        animation: a,
        child: widget.child,
        builder: (context, child) => Transform.translate(offset: Offset(0, (1 - a.value) * widget.offset), child: child),
      ),
    );
  }
}

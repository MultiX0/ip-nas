// Desktop layout helpers: breakpoint, adaptive sheets (bottom sheet on phones, centered dialog on desktop),
// anchored popovers, hover reveal, and the Windows clipboard bridge used by the composer.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nur_theme.dart';

/// Root navigator of the app (dialogs, full-screen routes).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// True on Windows / macOS / Linux.
final bool isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Desktop layout: width >= 900, or a desktop OS with width >= 700.
bool isDesktopWidth(double width) => width >= 900 || (isDesktopPlatform && width >= 700);

bool isDesktopLayout(BuildContext context) => isDesktopWidth(MediaQuery.sizeOf(context).width);

/// Receiver of files dropped onto the desktop window (set by the open chat screen; null = drops ignored).
final desktopFileDrop = ValueNotifier<void Function(List<String> paths)?>(null);

/// Shows [builder] as a modal bottom sheet on phones and as a centered dialog on desktop.
/// The same content widget is used in both cases (contents call `Navigator.pop(context, value)`).
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  double maxWidth = 560,
  double? maxHeightFraction,
}) {
  if (!isDesktopLayout(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (c) => DesktopSheetDialog(
      maxWidth: maxWidth,
      maxHeightFraction: maxHeightFraction ?? 0.86,
      child: Builder(builder: builder),
    ),
  );
}

/// Dialog frame used for sheet contents on desktop (sheet contents start without top padding,
/// because phones show a drag handle there).
class DesktopSheetDialog extends StatelessWidget {
  const DesktopSheetDialog({super.key, required this.child, this.maxWidth = 560, this.maxHeightFraction = 0.86});
  final Widget child;
  final double maxWidth;
  final double maxHeightFraction;
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: h * maxHeightFraction),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: const EdgeInsets.only(top: 22), child: child),
        ),
      ),
    );
  }
}

/// Opens [builder] in a floating card anchored below (or above) the widget of [anchorContext].
Future<T?> showAnchoredPopover<T>({
  required BuildContext anchorContext,
  required WidgetBuilder builder,
  double width = 360,
  double maxHeight = 520,
  bool alignEnd = false,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  final nav = Navigator.of(anchorContext, rootNavigator: true);
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = nav.overlay?.context.findRenderObject() as RenderBox?;
  final rect = box == null || overlay == null || !box.hasSize ? Rect.zero : (box.localToGlobal(Offset.zero, ancestor: overlay) & box.size);
  return nav.push(
    _PopoverRoute<T>(
      anchor: rect,
      width: width,
      maxHeight: maxHeight,
      alignEnd: alignEnd,
      padding: padding,
      builder: builder,
      barrierLabel: MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel,
      themes: InheritedTheme.capture(from: anchorContext, to: nav.context),
    ),
  );
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.width,
    required this.maxHeight,
    required this.alignEnd,
    required this.padding,
    required this.builder,
    required this.barrierLabel,
    required this.themes,
  });
  final Rect anchor;
  final double width;
  final double maxHeight;
  final bool alignEnd;
  final EdgeInsets padding;
  final WidgetBuilder builder;
  final CapturedThemes themes;
  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 130);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 90);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return themes.wrap(
      MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: CustomSingleChildLayout(
          delegate: _PopoverLayout(anchor, width, maxHeight, alignEnd),
          child: Builder(
            builder: (c) {
              final t = Theme.of(c);
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: t.dialogTheme.backgroundColor ?? t.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: t.colorScheme.outlineVariant),
                  ),
                  child: Padding(padding: padding, child: builder(c)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), alignment: alignEnd ? Alignment.topRight : Alignment.topLeft, child: child),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.width, this.maxHeight, this.alignEnd);
  final Rect anchor;
  final double width;
  final double maxHeight;
  final bool alignEnd;
  static const _margin = 10.0;
  static const _gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) {
    final below = c.maxHeight - anchor.bottom - _gap - _margin;
    final above = anchor.top - _gap - _margin;
    final room = below >= maxHeight || below >= above ? below : above;
    final h = (room < maxHeight ? room : maxHeight).clamp(120.0, c.maxHeight - 2 * _margin);
    final w = (width < c.maxWidth - 2 * _margin ? width : c.maxWidth - 2 * _margin).clamp(0.0, double.infinity);
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: h);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = alignEnd ? anchor.right - child.width : anchor.left;
    x = x.clamp(_margin, (size.width - child.width - _margin).clamp(_margin, double.infinity));
    var y = anchor.bottom + _gap;
    if (y + child.height > size.height - _margin) y = anchor.top - _gap - child.height;
    y = y.clamp(_margin, (size.height - child.height - _margin).clamp(_margin, double.infinity));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor || old.width != width || old.maxHeight != maxHeight || old.alignEnd != alignEnd;
}

/// Shows a desktop context menu at a global position (right click).
Future<T?> showContextMenuAt<T>(BuildContext context, Offset globalPosition, List<PopupMenuEntry<T>> items) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay!.context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  return showMenu<T>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: items,
  );
}

/// Context menu anchored below the widget of [anchorContext].
Future<T?> showMenuBelow<T>(BuildContext anchorContext, List<PopupMenuEntry<T>> items) {
  final box = anchorContext.findRenderObject() as RenderBox;
  final overlay = Navigator.of(anchorContext, rootNavigator: true).overlay!.context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay);
  return showMenu<T>(
    context: anchorContext,
    useRootNavigator: true,
    position: RelativeRect.fromRect(topLeft & Size(box.size.width, 1), Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: items,
  );
}

/// A compact menu row (icon + label) for desktop context menus.
PopupMenuItem<T> menuRow<T>(T value, IconData icon, String label, {bool danger = false, bool enabled = true}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  height: 38,
  child: Builder(
    builder: (c) {
      final color = danger ? NurColors.danger : null;
      return Row(
        children: [
          Icon(icon, size: 18, color: color ?? c.nur.muted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ],
      );
    },
  ),
);

/// Tracks mouse hover over [child]; descendants use [HoverReveal] to show on hover.
class HoverScope extends StatefulWidget {
  const HoverScope({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  static ValueNotifier<bool>? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_HoverInherited>()?.hovered;
  @override
  State<HoverScope> createState() => _HoverScopeState();
}

class _HoverScopeState extends State<HoverScope> {
  final _hovered = ValueNotifier(false);
  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: _HoverInherited(hovered: _hovered, child: widget.child),
    );
  }
}

class _HoverInherited extends InheritedWidget {
  const _HoverInherited({required this.hovered, required super.child});
  final ValueNotifier<bool> hovered;
  @override
  bool updateShouldNotify(_HoverInherited old) => old.hovered != hovered;
}

/// Fades [child] in while the nearest [HoverScope] is hovered (always visible without a scope or when [always]).
class HoverReveal extends StatelessWidget {
  const HoverReveal({super.key, required this.child, this.always = false});
  final Widget child;
  final bool always;
  @override
  Widget build(BuildContext context) {
    final n = HoverScope.maybeOf(context);
    if (n == null || always) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: n,
      builder: (c, v, ch) => AnimatedOpacity(
        opacity: v ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: IgnorePointer(ignoring: !v, child: ch),
      ),
      child: child,
    );
  }
}

/// Clipboard images and copied files on Windows; the native side is in windows/runner/flutter_window.cpp.
class DesktopClipboard {
  static const _channel = MethodChannel('nur/desktop');

  /// PNG (or BMP) bytes of an image on the clipboard, or null. Windows only.
  static Future<Uint8List?> image() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('clipboardImage');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Paths of files copied in Explorer, or an empty list. Windows only.
  static Future<List<String>> files() async {
    if (kIsWeb || !Platform.isWindows) return const [];
    try {
      final r = await _channel.invokeListMethod<String>('clipboardFiles');
      return r ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}

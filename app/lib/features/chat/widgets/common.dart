// Small shared chat widgets: snackbars, typing dots, image viewer, icon buttons.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/nur_theme.dart';
import '../../../core/widgets/nur_icons.dart';
import '../../../core/widgets/nur_ui.dart';

void showSnack(BuildContext context, String message) => showNurToast(context, message, kind: toastKindOf(message));

String errorText(Object e) => e.toString().replaceFirst(RegExp(r'^(Exception|Bad state): ?'), '');

/// Runs [f] and shows any error as a snackbar.
Future<void> guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e));
  }
}

class SmallIconButton extends StatelessWidget {
  const SmallIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 18, this.color, this.padding = 7});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;
  final double padding;
  @override
  Widget build(BuildContext context) => NurIconButton(icon: icon, onTap: onTap, tooltip: tooltip, size: size, box: size + padding * 2, color: color);
}

/// Three pulsing dots (assistant is preparing a reply).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 24,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsetsDirectional.only(end: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2 + 0.7 * (1 - ((_c.value * 3 - i) % 3).clamp(0.0, 1.0))),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Full-screen zoomable image.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.path, required this.heroTag});
  final String path;
  final String heroTag;

  static Future<void> open(BuildContext context, String path, String heroTag) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => ImageViewerPage(path: path, heroTag: heroTag),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Hero(tag: heroTag, child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, _, _) => const _Broken())),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(NurIcons.close, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();
  @override
  Widget build(BuildContext context) => const Icon(NurIcons.brokenImage, color: Colors.white54, size: 44);
}

/// Rounded thumbnail of a stored image, opens the viewer.
class ImageThumb extends StatelessWidget {
  const ImageThumb({super.key, required this.path, this.size = 120});
  final String path;
  final double size;
  @override
  Widget build(BuildContext context) {
    final tag = 'img:$path';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GestureDetector(
      onTap: () => ImageViewerPage.open(context, path, tag),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Hero(
        tag: tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * dpr).round(),
            errorBuilder: (_, _, _) => Container(width: size, height: size, color: context.nur.hover, child: Icon(NurIcons.brokenImage, color: context.nur.muted)),
          ),
        ),
      ),
      ),
    );
  }
}

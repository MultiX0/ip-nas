// FishAudioLogo shows Fish Audio's official files (white on dark, black on light), never a recoloured one.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/widgets/provider_logo.dart';

// A plain Theme, not MaterialApp: MaterialApp animates theme changes, so the brightness would lag one frame.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) => Theme(
  data: ThemeData(brightness: brightness),
  child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
);

SvgPicture _svg(WidgetTester tester) => tester.widget<SvgPicture>(find.byType(SvgPicture));

String _asset(WidgetTester tester) => (_svg(tester).bytesLoader as SvgAssetLoader).assetName;

/// Renders [logo] on [bg] (box [boxWidth] wide) and returns the pixel colours and the right-most inked x (logical px).
Future<(Map<int, int>, double)> _render(WidgetTester tester, Widget logo, Color bg, double boxWidth) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: Container(width: boxWidth, height: 60, color: bg, alignment: Alignment.centerLeft, child: logo),
        ),
      ),
    ),
  );
  final loaded = find.descendant(of: find.byType(SvgPicture), matching: find.byType(FittedBox));
  for (var i = 0; i < 100 && loaded.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(loaded, findsOneWidget, reason: 'the SVG did not load');

  const ratio = 2.0;
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final background = bg.toARGB32() & 0xFFFFFF;
  final colours = <int, int>{};
  var maxX = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 4;
      final c = (bytes.getUint8(i) << 16) | (bytes.getUint8(i + 1) << 8) | bytes.getUint8(i + 2);
      if (c == background) continue;
      colours[c] = (colours[c] ?? 0) + 1;
      if (x > maxX) maxX = x;
    }
  }
  image.dispose();
  return (colours, (maxX + 1) / ratio);
}

void main() {
  testWidgets('white file on dark, black file on light; never a colour filter', (tester) async {
    for (final wordmark in [true, false]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(_host(FishAudioLogo(wordmark: wordmark), brightness: brightness));
        final kind = wordmark ? 'lockup' : 'icon';
        final file = brightness == Brightness.dark ? 'white' : 'black';
        expect(_asset(tester), 'assets/logos/fishaudio-$kind-$file.svg');
        expect(_svg(tester).colorFilter, isNull);
      }
    }
    // An explicit background wins over the theme.
    await tester.pumpWidget(_host(const FishAudioLogo(wordmark: true, onDark: true)));
    expect(_asset(tester), 'assets/logos/fishaudio-lockup-white.svg');
    await tester.pumpWidget(_host(const FishAudioLogo(onDark: false), brightness: Brightness.dark));
    expect(_asset(tester), 'assets/logos/fishaudio-icon-black.svg');
  });

  testWidgets('lockup is size tall; the icon is size wide in a size x size square', (tester) async {
    await tester.pumpWidget(_host(const FishAudioLogo(size: 14, wordmark: true)));
    final lockup = tester.getSize(find.byType(SvgPicture));
    expect(lockup.height, moreOrLessEquals(14));
    expect(lockup.width, moreOrLessEquals(14 * 323 / 44));

    await tester.pumpWidget(_host(const FishAudioLogo(size: 28)));
    expect(tester.getSize(find.byType(FishAudioLogo)), const Size(28, 28));
    final icon = tester.getSize(find.byType(SvgPicture));
    expect(icon.width, moreOrLessEquals(28));
    expect(icon.height, moreOrLessEquals(28 * 44 / 118));
  });

  testWidgets('a quiet mark fades the official file instead of recolouring it', (tester) async {
    await tester.pumpWidget(_host(const FishAudioLogo(opacity: FishAudioLogo.quiet)));
    final fade = find.descendant(of: find.byType(FishAudioLogo), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(fade).opacity, FishAudioLogo.quiet);
    expect(_svg(tester).colorFilter, isNull);

    await tester.pumpWidget(_host(const FishAudioLogo()));
    expect(find.descendant(of: find.byType(FishAudioLogo), matching: find.byType(Opacity)), findsNothing);
  });

  testWidgets('the official SVGs render in their own colours, and the icon crop shows no wordmark', (tester) async {
    // Lockup, white file on black: white letters and bars, the #6B6B6B belly bars; the wordmark reaches the right edge.
    var (colours, inkRight) = await _render(tester, const FishAudioLogo(size: 44, wordmark: true, onDark: true), Colors.black, 400);
    expect(colours[0xFFFFFF] ?? 0, greaterThan(5000));
    expect(colours[0x6B6B6B] ?? 0, greaterThan(500));
    expect(inkRight, greaterThan(310)); // the "o" of "Audio" ends at x = 320.9 of 323

    // Lockup, black file on white: black, plus Fish Audio's light grey #B1B3B4 for the belly bars.
    (colours, inkRight) = await _render(tester, const FishAudioLogo(size: 44, wordmark: true, onDark: false), Colors.white, 400);
    expect(colours[0x000000] ?? 0, greaterThan(5000));
    expect(colours[0xB1B3B4] ?? 0, greaterThan(500));

    // Icon (the horizontal file cut to 0..118): nothing of the wordmark beyond the icon's 118 px.
    (colours, inkRight) = await _render(tester, const FishAudioLogo(size: 118, onDark: true), Colors.black, 400);
    expect(colours[0xFFFFFF] ?? 0, greaterThan(2000));
    expect(colours[0x6B6B6B] ?? 0, greaterThan(500));
    expect(inkRight, lessThanOrEqualTo(118.5));
  });
}

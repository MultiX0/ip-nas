// Nur look: Open WebUI-style monochrome (neutral grays, black/white primary), ChatGPT-like surfaces.
import 'package:flutter/material.dart';

import '../widgets/nur_icons.dart';

class NurColors {
  // Open WebUI gray scale
  static const g50 = Color(0xFFF9F9F9);
  static const g100 = Color(0xFFECECEC);
  static const g200 = Color(0xFFE3E3E3);
  static const g300 = Color(0xFFCDCDCD);
  static const g400 = Color(0xFFB4B4B4);
  static const g500 = Color(0xFF9B9B9B);
  static const g600 = Color(0xFF676767);
  static const g700 = Color(0xFF4E4E4E);
  static const g800 = Color(0xFF333333);
  static const g850 = Color(0xFF262626);
  static const g900 = Color(0xFF171717);
  static const g950 = Color(0xFF0D0D0D);
  // Signals (used sparingly)
  static const ok = Color(0xFF10A37F);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
}

/// Corner radii: controls 10, rows 12, cards 18, sheets/dialogs 24, composer 28.
abstract final class NurRadius {
  static const double sm = 8;
  static const double control = 10;
  static const double row = 12;
  static const double field = 14;
  static const double card = 18;
  static const double panel = 20;
  static const double sheet = 24;
  static const double composer = 28;
  static const double pill = 999;
}

/// Motion tokens: short and calm, ease-out.
abstract final class NurMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutBack;
}

/// Extra semantic colors the widgets need (bubble, sidebar, code block...).
@immutable
class NurPalette extends ThemeExtension<NurPalette> {
  final Color sidebar;
  final Color userBubble;
  final Color composer;
  final Color composerBorder;
  final Color codeBg;
  final Color muted;
  final Color subtle;
  final Color hover;
  const NurPalette({
    required this.sidebar,
    required this.userBubble,
    required this.composer,
    required this.composerBorder,
    required this.codeBg,
    required this.muted,
    required this.subtle,
    required this.hover,
  });

  static const light = NurPalette(
    sidebar: NurColors.g50,
    userBubble: Color(0xFFF4F4F4),
    composer: Colors.white,
    composerBorder: NurColors.g200,
    codeBg: NurColors.g50,
    muted: NurColors.g600,
    subtle: NurColors.g400,
    hover: NurColors.g100,
  );
  static const dark = NurPalette(
    sidebar: NurColors.g950,
    userBubble: NurColors.g800,
    composer: NurColors.g850,
    composerBorder: NurColors.g800,
    codeBg: NurColors.g950,
    muted: NurColors.g400,
    subtle: NurColors.g600,
    hover: NurColors.g850,
  );

  @override
  NurPalette copyWith() => this;
  @override
  NurPalette lerp(ThemeExtension<NurPalette>? other, double t) => t < 0.5 ? this : (other as NurPalette? ?? this);
}

extension NurThemeX on BuildContext {
  NurPalette get nur => Theme.of(this).extension<NurPalette>()!;
}

class NurTheme {
  static const _fontFamily = 'Inter';
  static const _fallback = ['IBMPlexSansArabic', 'Roboto', 'Segoe UI', 'Noto Sans Arabic'];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? NurColors.g900 : Colors.white;
    final fg = dark ? NurColors.g100 : NurColors.g900;
    final scheme = ColorScheme(
      brightness: b,
      primary: dark ? Colors.white : Colors.black,
      onPrimary: dark ? Colors.black : Colors.white,
      secondary: dark ? NurColors.g300 : NurColors.g700,
      onSecondary: dark ? Colors.black : Colors.white,
      error: NurColors.danger,
      onError: Colors.white,
      surface: bg,
      onSurface: fg,
      surfaceContainerLowest: dark ? NurColors.g950 : Colors.white,
      surfaceContainerLow: dark ? NurColors.g900 : NurColors.g50,
      surfaceContainer: dark ? NurColors.g850 : NurColors.g50,
      surfaceContainerHigh: dark ? NurColors.g800 : NurColors.g100,
      surfaceContainerHighest: dark ? NurColors.g700 : NurColors.g200,
      onSurfaceVariant: dark ? NurColors.g400 : NurColors.g600,
      outline: dark ? NurColors.g700 : NurColors.g300,
      outlineVariant: dark ? NurColors.g800 : NurColors.g200,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fallback,
      visualDensity: VisualDensity.standard,
    );
    final muted = dark ? NurColors.g400 : NurColors.g600;
    final hover = dark ? NurColors.g850 : NurColors.g100;
    final raised = dark ? NurColors.g850 : Colors.white;
    // Keyboard focus ring: a 2 px outline in the text colour (only on focus, never on hover/press).
    final focusRing = BorderSide(color: fg.withValues(alpha: 0.55), width: 2);
    WidgetStateProperty<BorderSide?> ringOr(BorderSide? normal) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? focusRing : normal);
    // Quiet monochrome overlays: hover = faint, pressed = a bit more, focus = ring instead of a fill.
    WidgetStateProperty<Color?> overlay(Color c) => WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return c.withValues(alpha: 0.12);
          if (s.contains(WidgetState.hovered)) return c.withValues(alpha: 0.06);
          return Colors.transparent;
        });
    const controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(NurRadius.control)));
    TextStyle font(double size, FontWeight w, [Color? c, double? height, double? spacing]) =>
        TextStyle(fontFamily: _fontFamily, fontFamilyFallback: _fallback, fontSize: size, fontWeight: w, color: c, height: height, letterSpacing: spacing);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      extensions: [dark ? NurPalette.dark : NurPalette.light],
      hoverColor: fg.withValues(alpha: 0.05),
      focusColor: fg.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      splashColor: fg.withValues(alpha: 0.06),
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(size: 20, color: fg),
      // AppBar back / close / drawer buttons use the Nur icon set (mirrors in RTL).
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(NurIcons.back),
        closeButtonIconBuilder: (_) => const Icon(NurIcons.close),
        drawerButtonIconBuilder: (_) => const Icon(NurIcons.menu),
        endDrawerButtonIconBuilder: (_) => const Icon(NurIcons.menu),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        iconTheme: IconThemeData(size: 20, color: fg),
        actionsIconTheme: IconThemeData(size: 20, color: muted),
        titleTextStyle: font(17, FontWeight.w600, fg, null, -0.2),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      textTheme: base.textTheme.apply(bodyColor: fg, displayColor: fg),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: fg,
        selectionColor: NurColors.info.withValues(alpha: dark ? 0.35 : 0.22),
        selectionHandleColor: fg,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? NurColors.g850 : NurColors.g50,
        hintStyle: font(15, FontWeight.w400, dark ? NurColors.g600 : NurColors.g400),
        prefixIconColor: muted,
        suffixIconColor: muted,
        floatingLabelStyle: TextStyle(color: fg),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(NurRadius.field), borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(NurRadius.field), borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(NurRadius.field), borderSide: BorderSide(color: fg.withValues(alpha: 0.6), width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(NurRadius.field), borderSide: const BorderSide(color: NurColors.danger)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconSize: const WidgetStatePropertyAll(20),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.3) : (s.contains(WidgetState.selected) ? fg : muted)),
          overlayColor: overlay(fg),
          shape: const WidgetStatePropertyAll(controlShape),
          side: ringOr(null),
          minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          animationDuration: NurMotion.fast,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.12) : scheme.primary),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.38) : scheme.onPrimary),
          overlayColor: overlay(scheme.onPrimary),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: ringOr(null),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
          textStyle: WidgetStatePropertyAll(font(14.5, FontWeight.w600)),
          iconSize: const WidgetStatePropertyAll(18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(fg),
          overlayColor: overlay(fg),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: ringOr(BorderSide(color: scheme.outline)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          textStyle: WidgetStatePropertyAll(font(14.5, FontWeight.w500)),
          iconSize: const WidgetStatePropertyAll(18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.38) : fg),
          overlayColor: overlay(fg),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: ringOr(null),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          textStyle: WidgetStatePropertyAll(font(14, FontWeight.w500)),
          iconSize: const WidgetStatePropertyAll(18),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.card)),
        extendedTextStyle: font(14.5, FontWeight.w600),
        iconSize: 20,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? NurColors.g700 : NurColors.g200) : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? fg : muted),
          overlayColor: overlay(fg),
          side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? focusRing : BorderSide(color: scheme.outlineVariant)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(font(13, FontWeight.w500)),
          iconSize: const WidgetStatePropertyAll(16),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : (dark ? NurColors.g400 : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : (dark ? NurColors.g700 : NurColors.g300)),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: overlay(fg),
        splashRadius: 18,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? fg : scheme.outline)),
      sliderTheme: SliderThemeData(
        activeTrackColor: fg,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: fg,
        overlayColor: fg.withValues(alpha: 0.08),
        valueIndicatorColor: dark ? NurColors.g100 : NurColors.g900,
        valueIndicatorTextStyle: font(12, FontWeight.w500, dark ? NurColors.g900 : Colors.white),
        trackHeight: 4,
        inactiveTickMarkColor: Colors.transparent,
        activeTickMarkColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 0, pressedElevation: 0),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: fg,
        linearTrackColor: scheme.outlineVariant,
        circularTrackColor: Colors.transparent,
        strokeCap: StrokeCap.round,
        linearMinHeight: 4,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: fg,
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.row)),
        subtitleTextStyle: font(13, FontWeight.w400, muted, 1.35),
        titleTextStyle: font(15, FontWeight.w500, fg),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: muted,
        collapsedIconColor: muted,
        textColor: fg,
        collapsedTextColor: fg,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: fg,
        unselectedLabelColor: muted,
        indicatorColor: fg,
        dividerColor: scheme.outlineVariant,
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: overlay(fg),
        labelStyle: font(14, FontWeight.w600),
        unselectedLabelStyle: font(14, FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: hover,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: font(13, FontWeight.w500, fg),
        iconTheme: IconThemeData(size: 16, color: muted),
        checkmarkColor: fg,
      ),
      cardTheme: CardThemeData(
        color: raised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.card), side: BorderSide(color: scheme.outlineVariant)),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: dark ? NurColors.g950 : NurColors.g50, elevation: 0, shape: const RoundedRectangleBorder()),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: dark ? NurColors.g700 : NurColors.g300,
        dragHandleSize: const Size(36, 4),
        modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.32),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(NurRadius.sheet))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.sheet), side: BorderSide(color: dark ? NurColors.g800 : Colors.transparent)),
        titleTextStyle: font(18, FontWeight.w600, fg, null, -0.2),
        contentTextStyle: font(14.5, FontWeight.w400, muted, 1.45),
        iconColor: fg,
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      ),
      // Thin, quiet scrollbars (visible on desktop; phones keep the platform overlay behaviour).
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged) ? 8 : 5),
        radius: const Radius.circular(8),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => fg.withValues(alpha: s.contains(WidgetState.dragged) ? 0.45 : (s.contains(WidgetState.hovered) ? 0.32 : 0.16))),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        textStyle: font(12, FontWeight.w500, dark ? NurColors.g900 : Colors.white),
        decoration: BoxDecoration(color: dark ? NurColors.g100 : NurColors.g900, borderRadius: BorderRadius.circular(NurRadius.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
        iconColor: muted,
        iconSize: 20,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        textStyle: font(14, FontWeight.w400, fg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.field), side: BorderSide(color: scheme.outlineVariant)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.field), side: BorderSide(color: scheme.outlineVariant))),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? NurColors.g100 : NurColors.g900,
        contentTextStyle: font(14, FontWeight.w500, dark ? NurColors.g900 : Colors.white),
        actionTextColor: dark ? NurColors.g900 : Colors.white,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.field)),
      ),
    );
  }
}

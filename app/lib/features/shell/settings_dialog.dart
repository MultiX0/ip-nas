// Settings on desktop: a large centered dialog with a navigation list on the left. The right pane hosts the
// normal settings screens in a nested navigator, so their own pushes stay inside the dialog.
// On phones `openSettings` uses the full-screen routes.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import '../memory/memory_screen.dart';
import '../nas/nas_screen.dart';
import '../providers/providers_screen.dart';
import '../tools/tools_screen.dart';
import '../voice/voice_settings_screen.dart';
import 'settings_screen.dart';

enum SettingsSection { general, providers, memory, tools, voice, nas }

extension SettingsSectionX on SettingsSection {
  String get label => switch (this) {
    SettingsSection.general => 'General',
    SettingsSection.providers => 'Models & providers',
    SettingsSection.memory => 'Memory',
    SettingsSection.tools => 'Tools, MCP & skills',
    SettingsSection.voice => 'Voice',
    SettingsSection.nas => 'NAS',
  };
  IconData get icon => switch (this) {
    SettingsSection.general => NurIcons.settings,
    SettingsSection.providers => NurIcons.models,
    SettingsSection.memory => NurIcons.memory,
    SettingsSection.tools => NurIcons.extension,
    SettingsSection.voice => NurIcons.voice,
    SettingsSection.nas => NurIcons.nas,
  };
  String get route => switch (this) {
    SettingsSection.general => '/settings',
    SettingsSection.providers => '/settings/providers',
    SettingsSection.memory => '/settings/memory',
    SettingsSection.tools => '/settings/tools',
    SettingsSection.voice => '/settings/voice',
    SettingsSection.nas => '/nas',
  };
  Widget page() => switch (this) {
    SettingsSection.general => const _GeneralPage(),
    SettingsSection.providers => const ProvidersScreen(),
    SettingsSection.memory => const MemoryScreen(),
    SettingsSection.tools => const ToolsScreen(),
    SettingsSection.voice => const VoiceSettingsScreen(),
    SettingsSection.nas => const NasScreen(),
  };
}

/// Section shown by the open settings dialog (null when closed).
final _openSection = ValueNotifier<SettingsSection?>(null);

/// Opens settings: a dialog on desktop, the full-screen route on phones.
/// Completes when the dialog / page is closed.
Future<void> openSettings(BuildContext context, [SettingsSection section = SettingsSection.general]) async {
  final ctx = rootNavigatorKey.currentContext ?? (context.mounted ? context : null);
  if (ctx == null) return;
  if (!isDesktopLayout(ctx)) {
    await GoRouter.of(ctx).push<void>(section.route);
    return;
  }
  if (_openSection.value != null) {
    _openSection.value = section;
    return;
  }
  _openSection.value = section;
  try {
    await showDialog<void>(context: ctx, builder: (_) => const SettingsDialog());
  } finally {
    _openSection.value = null;
  }
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final nur = context.nur;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      backgroundColor: scheme.surface,
      child: SizedBox(
        width: math.min(1060, size.width - 64),
        height: math.min(760, size.height - 64),
        child: ValueListenableBuilder<SettingsSection?>(
          valueListenable: _openSection,
          builder: (context, section, _) {
            final current = section ?? SettingsSection.general;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 236,
                  color: nur.sidebar,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(10, 12, 12, 12),
                        child: Row(
                          children: [
                            NurIconButton(tooltip: 'Close (Esc)', icon: NurIcons.close, box: 34, onTap: () => Navigator.of(context).pop()),
                            const SizedBox(width: 6),
                            const Text('Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                          ],
                        ),
                      ),
                      for (final s in SettingsSection.values) _NavItem(section: s, selected: s == current, onTap: () => _openSection.value = s),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                Expanded(
                  child: ScaffoldMessenger(
                    child: KeyedSubtree(
                      key: ValueKey(current),
                      child: HeroControllerScope.none(
                        child: Navigator(
                          onGenerateRoute: (_) => PageRouteBuilder<void>(
                            pageBuilder: (_, _, _) => current.page(),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap});
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: NurPressable(
        onTap: onTap,
        selected: selected,
        selectedColor: dark ? NurColors.g800 : NurColors.g200.withValues(alpha: 0.7),
        pressedScale: 0.985,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(section.icon, size: 18, color: selected ? Theme.of(context).colorScheme.onSurface : nur.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneralPage extends StatelessWidget {
  const _GeneralPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('General')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: const [
        NurSectionLabel('Appearance', padding: EdgeInsetsDirectional.fromSTEB(6, 4, 6, 8)),
        AppearanceSettings(),
        NurSectionLabel('Keyboard shortcuts'),
        NurGroup(children: [
          _Shortcut('New chat', 'Ctrl+N'),
          _Shortcut('Search chats', 'Ctrl+K'),
          _Shortcut('Toggle sidebar', 'Ctrl+Shift+S'),
          _Shortcut('Settings', 'Ctrl+,'),
          _Shortcut('Send message', 'Enter'),
          _Shortcut('New line', 'Shift+Enter'),
          _Shortcut('Stop generating', 'Esc'),
        ]),
      ],
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.label, this.keys);
  final String label;
  final String keys;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
        Wrap(spacing: 4, children: [for (final k in keys.split('+')) _Key(k)]),
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key(this.k);
  final String k;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.nur.hover,
        borderRadius: BorderRadius.circular(6),
        border: Border(bottom: BorderSide(color: scheme.outline, width: 1.5)),
      ),
      child: Text(k, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
    );
  }
}

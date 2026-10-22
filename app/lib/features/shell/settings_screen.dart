import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_logo.dart';
import '../../core/widgets/nur_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String subtitle, String route) => NurTile(icon: icon, title: title, subtitle: subtitle, onTap: () => context.push(route));
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const Padding(padding: EdgeInsets.fromLTRB(0, 16, 0, 12), child: Center(child: AppearIn(child: NurLogo(size: 48, withWordmark: true)))),
        const NurSectionLabel('Workspace'),
        NurGroup(children: [
          item(NurIcons.nas, 'NAS', 'Status, apps, local models', '/nas'),
          item(NurIcons.models, 'Models & providers', 'llama.cpp, Ollama, OpenAI, Anthropic, OpenRouter...', '/settings/providers'),
          item(NurIcons.memory, 'Memory', 'What Nur remembers about you', '/settings/memory'),
          item(NurIcons.extension, 'Tools, MCP & skills', 'NAS control, web search, MCP servers, skills', '/settings/tools'),
          item(NurIcons.voice, 'Voice', 'Fish Audio Drama 3 voices, calls', '/settings/voice'),
        ]),
        const NurSectionLabel('Appearance'),
        const AppearanceSettings(),
      ]),
    );
  }
}

/// Theme and language rows (shared by the phone settings page and the desktop settings dialog).
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    // Segmented controls sit beside the title when there is room, under it on phones.
    final wide = MediaQuery.sizeOf(context).width >= 560;
    Widget tile(IconData icon, String title, Widget control) =>
        NurTile(icon: icon, title: title, trailing: wide ? control : null, bottom: wide ? null : Align(alignment: AlignmentDirectional.centerStart, child: control));
    return NurGroup(children: [
      StreamBuilder<String?>(
        stream: db.watchSetting('theme_mode'),
        builder: (c, s) => tile(
          NurIcons.theme,
          'Theme',
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', label: Text('Auto')),
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {s.data ?? 'system'},
            onSelectionChanged: (v) => db.setSetting('theme_mode', v.first),
          ),
        ),
      ),
      StreamBuilder<String?>(
        stream: db.watchSetting('locale'),
        builder: (c, s) => tile(
          NurIcons.language,
          'Language / اللغة',
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: '', label: Text('Auto')),
              ButtonSegment(value: 'en', label: Text('EN')),
              ButtonSegment(value: 'ar', label: Text('عربي')),
            ],
            selected: {s.data ?? ''},
            onSelectionChanged: (v) => db.setSetting('locale', v.first),
          ),
        ),
      ),
    ]);
  }
}

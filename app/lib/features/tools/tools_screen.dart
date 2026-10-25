// The "Tools, MCP & skills" page in Settings: command mode, built-in tool switches, result size, MCP and skills.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../context/intel_settings.dart';
import '../mcp/mcp_tab.dart';
import '../skills/skills_tab.dart';
import 'builtin_tools.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tools, MCP & skills'),
          bottom: TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Theme.of(context).colorScheme.outlineVariant,
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: nur.muted,
            indicatorColor: Theme.of(context).colorScheme.onSurface,
            tabs: const [Tab(text: 'Tools'), Tab(text: 'MCP'), Tab(text: 'Skills')],
          ),
        ),
        body: const TabBarView(children: [_ToolsTab(), McpTab(), SkillsTab()]),
      ),
    );
  }
}

const _groupTitles = {
  'nas': 'NAS',
  'web': 'Web',
  'memory': 'Memory',
  'skills': 'Skills',
  'agent': 'Agent mode',
};

class _ToolsTab extends ConsumerWidget {
  const _ToolsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nur = context.nur;
    final db = ref.read(dbProvider);
    final rawOff = ref.watch(stringSettingProvider(IntelKeys.toolsDisabled)).value;
    final off = rawOff == null
        ? {for (final t in builtinTools) if (!t.defaultEnabled) t.name}
        : _decodeSet(rawOff);
    final mode = ref.watch(stringSettingProvider(IntelKeys.execMode)).value ?? 'safe';
    final maxChars = int.tryParse(ref.watch(stringSettingProvider(IntelKeys.toolResultMax)).value ?? '') ?? 6000;

    Future<void> toggle(String name, bool on) async {
      final s = {...off};
      on ? s.remove(name) : s.add(name);
      await db.setStringSet(IntelKeys.toolsDisabled, s);
    }

    Future<void> setMode(String m) async {
      if (m == 'admin') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Allow any command?'),
            content: const Text(
                'In admin mode the model can ask to run any shell command on your NAS, including ones that change or delete data. '
                'You will still approve every command, but read each one carefully.\n\nThe NAS hub must also be set to admin mode.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Enable admin mode'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      await db.setSetting(IntelKeys.execMode, m);
    }

    final groups = <String, List<BuiltinTool>>{};
    for (final t in builtinTools) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      _Section(title: 'Command execution', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'safe', label: Text('Safe'), icon: Icon(NurIcons.shieldCheck, size: 16)),
              ButtonSegment(value: 'admin', label: Text('Admin'), icon: Icon(NurIcons.warning, size: 16)),
            ],
            selected: {mode == 'admin' ? 'admin' : 'safe'},
            onSelectionChanged: (v) => setMode(v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Text(
            mode == 'admin'
                ? 'Any command can be requested. Every command still needs your approval.'
                : 'Only read-only diagnostics (df, free, uptime, docker ps, logs). Every command needs your approval.',
            style: TextStyle(color: mode == 'admin' ? NurColors.warn : nur.muted, fontSize: 13),
          ),
        ),
      ]),
      for (final e in groups.entries)
        _Section(title: _groupTitles[e.key] ?? e.key, children: [
          for (final t in e.value)
            SwitchListTile(
              title: Text(t.title),
              subtitle: Text(t.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 13)),
              value: !off.contains(t.name),
              onChanged: (v) => toggle(t.name, v),
            ),
        ]),
      _Section(title: 'Tool results', children: [
        ListTile(
          title: const Text('Max result size sent to the model'),
          subtitle: Text('Longer results are shortened (start and end kept). Smaller = more room for the conversation.',
              style: TextStyle(color: nur.muted, fontSize: 13)),
          trailing: Text('${(maxChars / 1000).toStringAsFixed(maxChars % 1000 == 0 ? 0 : 1)}k chars'),
        ),
        Slider(
          value: maxChars.clamp(2000, 30000).toDouble(),
          min: 2000,
          max: 30000,
          divisions: 14,
          label: '$maxChars',
          onChanged: (v) => db.setSetting(IntelKeys.toolResultMax, '${v.round()}'),
        ),
      ]),
    ]);
  }

  static Set<String> _decodeSet(String raw) {
    try {
      final s = raw.trim();
      if (s.isEmpty) return {};
      return (jsonDecode(s) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 0.7, fontWeight: FontWeight.w600, color: context.nur.muted)),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(NurRadius.card),
            ),
            child: Material(type: MaterialType.transparency, child: Column(children: children)),
          ),
        ]),
      );
}

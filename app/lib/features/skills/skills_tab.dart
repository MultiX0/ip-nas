// Skills list: built-in and installed skills, enable switches, install from URL / zip / paste, view, delete.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/utils/text_dir.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import 'skills_repo.dart';
import '../../core/widgets/nur_icons.dart';

final _skillsProvider = StreamProvider.autoDispose<List<Skill>>((ref) {
  final repo = ref.watch(skillsRepoProvider);
  repo.ensureBuiltins().catchError((_) {});
  return repo.watchAll();
});

class SkillsTab extends ConsumerWidget {
  const SkillsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nur = context.nur;
    final skills = ref.watch(_skillsProvider);
    final repo = ref.read(skillsRepoProvider);
    return Stack(children: [
      skills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load skills: $e')),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Skills are instruction packs (SKILL.md). Only their names and descriptions are in the prompt; Nur loads a skill\'s full text when a task needs it.',
              style: TextStyle(color: nur.muted, fontSize: 13),
            ),
          ),
          for (final s in list)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(NurRadius.card),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NurRadius.card)),
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: nur.hover, borderRadius: BorderRadius.circular(10)),
                  child: Icon(NurIcons.skills, size: 18, color: Theme.of(context).colorScheme.onSurface),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                title: Row(children: [
                  Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  if (s.source == 'builtin') _Tag('built-in'),
                ]),
                subtitle: Text(s.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 13)),
                onTap: () => _view(context, ref, s),
                trailing: Switch(value: s.enabled, onChanged: (v) => repo.setEnabled(s.id, v)),
              ),
            ),
          if (list.every((s) => s.source != 'builtin'))
            TextButton.icon(
              onPressed: () => repo.restoreBuiltins(),
              icon: const Icon(NurIcons.reset, size: 18),
              label: const Text('Restore built-in skills'),
            ),
        ]),
      ),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'skill_add',
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: const StadiumBorder(),
          onPressed: () => showAdaptiveSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _InstallSheet()),
          icon: const Icon(NurIcons.add),
          label: const Text('Install skill'),
        ),
      ),
    ]);
  }

  void _view(BuildContext context, WidgetRef ref, Skill s) {
    final desktop = isDesktopLayout(context);
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      maxWidth: 760,
      builder: (c) => desktop ? _detail(context, ref, s, c, null) : DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (c, scroll) => _detail(context, ref, s, c, scroll),
      ),
    );
  }

  Widget _detail(BuildContext context, WidgetRef ref, Skill s, BuildContext c, ScrollController? scroll) {
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Row(children: [
            Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
            IconButton(
                tooltip: 'Delete skill',
                icon: const Icon(NurIcons.delete, color: NurColors.danger),
                onPressed: () async {
                  Navigator.pop(c);
                  try {
                    await ref.read(skillsRepoProvider).delete(s);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
                  }
                },
              ),
          ]),
          Text(s.description, style: TextStyle(color: context.nur.muted)),
          const SizedBox(height: 4),
          Text('Source: ${s.source}', style: TextStyle(color: context.nur.subtle, fontSize: 12)),
          const Divider(height: 28),
          Directionality(textDirection: textDirOf(s.body), child: GptMarkdown(s.body)),
        ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, color: context.nur.muted)),
      );
}

class _InstallSheet extends ConsumerStatefulWidget {
  const _InstallSheet();
  @override
  ConsumerState<_InstallSheet> createState() => _InstallSheetState();
}

class _InstallSheetState extends ConsumerState<_InstallSheet> {
  String _mode = 'url';
  final _url = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _go(Future<Skill?> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await f();
      if (s == null) return;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(content: Text('Installed "${s.name}"')));
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Skill?> _pickZip() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['zip', 'md']);
    if (files.isEmpty) return null;
    final f = files.first;
    final bytes = await f.xFile.readAsBytes();
    final repo = ref.read(skillsRepoProvider);
    if (f.name.toLowerCase().endsWith('.md')) return repo.installFromText(utf8.decode(bytes, allowMalformed: true), source: 'file');
    return repo.installFromZipBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(skillsRepoProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Install a skill', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'url', label: Text('URL')),
            ButtonSegment(value: 'file', label: Text('File')),
            ButtonSegment(value: 'paste', label: Text('Paste')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() {
            _mode = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 14),
        if (_mode == 'url')
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Link to SKILL.md or a .zip', hintText: 'https://github.com/…/SKILL.md'),
          ),
        if (_mode == 'file')
          Text('Choose a .zip containing a skill folder (SKILL.md + files) or a single SKILL.md.', style: TextStyle(color: context.nur.muted)),
        if (_mode == 'paste')
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(hintText: '---\nname: my-skill\ndescription: What it does and when to use it\n---\n\n# Instructions…'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: NurColors.danger, fontSize: 13)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy
                ? null
                : () => _go(() async => switch (_mode) {
                      'url' => await repo.installFromUrl(_url.text),
                      'file' => await _pickZip(),
                      _ => await repo.installFromText(_text.text),
                    }),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_mode == 'file' ? 'Choose file…' : 'Install'),
          ),
        ),
      ]),
    );
  }
}

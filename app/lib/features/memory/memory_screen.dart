// The Memory page in Settings: what Nur remembers about the user.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/desktop.dart';
import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/utils/text_dir.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import '../context/intel_settings.dart';
import '../context/llm_access.dart';
import 'memory_repo.dart';
import 'memory_text.dart';

final _memoriesProvider = StreamProvider.autoDispose<List<Memory>>((ref) => ref.watch(memoryRepoProvider).watchAll());

const _categoryLabels = {
  'profile': 'Profile',
  'preference': 'Preferences',
  'nas': 'NAS & devices',
  'project': 'Projects',
  'general': 'General',
};

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});
  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() f, String failMsg) async {
    try {
      await f();
    } catch (e) {
      if (mounted) _snack('$failMsg: $e');
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all memories?'),
        content: const Text('Nur will forget everything it has learned about you. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(memoryRepoProvider).deleteAll(), 'Could not delete');
  }

  Future<void> _pickEmbedding() async {
    final models = await ref.read(intelLlmProvider).allModels();
    if (!mounted) return;
    final ctrl = TextEditingController(text: await ref.read(dbProvider).getSetting(IntelKeys.memoryEmbeddingModel) ?? '');
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    final likely = models.where((m) => RegExp('embed|bge|e5|gte|minilm|nomic', caseSensitive: false).hasMatch(m.modelId)).toList();
    final picked = await showAdaptiveSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Embedding model', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Optional. Adds meaning-based memory search on top of keyword search. Use an embedding model served by '
              'one of your providers (OpenAI-compatible /v1/embeddings).', style: TextStyle(color: c.nur.muted, fontSize: 13)),
          const SizedBox(height: 12),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(NurIcons.blocked), title: const Text('Off'), onTap: () => Navigator.pop(c, '')),
          for (final m in likely)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(NurIcons.sparkle), title: Text(m.displayName), subtitle: Text(m.ref), onTap: () => Navigator.pop(c, m.ref)),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Or enter providerId::modelId')),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Use this model'))),
        ]),
      ),
    );
    ctrl.dispose();
    if (picked == null) return;
    await _run(() async {
      await ref.read(dbProvider).setSetting(IntelKeys.memoryEmbeddingModel, picked);
      if (picked.contains('::')) {
        final n = await ref.read(memoryRepoProvider).backfillEmbeddings();
        if (mounted) _snack(n > 0 ? 'Indexed $n memories' : 'Saved. If nothing was indexed, check that the model serves embeddings.');
      }
    }, 'Could not set the embedding model');
  }

  Future<void> _edit([Memory? m]) async {
    final r = await showAdaptiveSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditSheet(memory: m),
    );
    if (r == null) return;
    final repo = ref.read(memoryRepoProvider);
    await _run(() async {
      if (m == null) {
        await repo.add(r.content, category: r.category, source: 'user', pinned: r.pinned);
      } else {
        await repo.update(m.id, content: r.content, category: r.category, pinned: r.pinned);
      }
    }, 'Could not save');
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final enabled = ref.watch(boolSettingProvider((IntelKeys.memoryEnabled, true))).value ?? true;
    final auto = ref.watch(boolSettingProvider((IntelKeys.memoryAutoExtract, true))).value ?? true;
    final all = ref.watch(_memoriesProvider);
    final embed = ref.watch(stringSettingProvider(IntelKeys.memoryEmbeddingModel)).value;
    final db = ref.read(dbProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(NurIcons.more),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'delete_all') _deleteAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete_all', child: Text('Delete all memories', style: TextStyle(color: NurColors.danger))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        shape: const StadiumBorder(),
        onPressed: () => _edit(),
        icon: const Icon(NurIcons.add),
        label: const Text('Add memory'),
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(NurRadius.card),
              ),
              child: Column(children: [
                SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: const Text('Use memory'),
                  subtitle: Text('Nur uses saved memories to personalise answers', style: TextStyle(color: nur.muted, fontSize: 13)),
                  value: enabled,
                  onChanged: (v) => db.setSetting(IntelKeys.memoryEnabled, '$v'),
                ),
                SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: const Text('Learn from chats'),
                  subtitle: Text('Automatically save lasting facts and preferences after each reply', style: TextStyle(color: nur.muted, fontSize: 13)),
                  value: auto && enabled,
                  onChanged: enabled ? (v) => db.setSetting(IntelKeys.memoryAutoExtract, '$v') : null,
                ),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: const Text('Semantic search'),
                  subtitle: Text(
                    (embed ?? '').contains('::') ? 'Embeddings: ${embed!.split('::').last}' : 'Off · keyword search (BM25) only',
                    style: TextStyle(color: nur.muted, fontSize: 13),
                  ),
                  trailing: Icon(NurIcons.chevron, size: 18, color: nur.subtle),
                  onTap: enabled ? _pickEmbedding : null,
                ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search memories',
                prefixIcon: const Icon(NurIcons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(NurIcons.close, size: 16),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _chip('All', _category == null, () => setState(() => _category = null)),
                for (final c in kMemoryCategories) _chip(_categoryLabels[c] ?? c, _category == c, () => setState(() => _category = _category == c ? null : c)),
              ],
            ),
          ),
        ),
        ...all.when(
          loading: () => [const SliverFillRemaining(child: SkeletonList(count: 5))],
          error: (e, _) => [SliverFillRemaining(child: NurEmptyState(icon: NurIcons.error, tone: NurColors.danger, title: 'Could not load memories', body: '$e'))],
          data: (list) {
            final q = normalizeText(_query.trim());
            final shown = list.where((m) => (_category == null || m.category == _category) && (q.isEmpty || normalizeText(m.content).contains(q))).toList();
            if (shown.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: NurEmptyState(
                    icon: list.isEmpty ? NurIcons.memory : NurIcons.search,
                    title: list.isEmpty ? 'No memories yet' : 'Nothing matches',
                    body: list.isEmpty ? 'Tell Nur things like "remember that I prefer short answers", or add one here.' : 'Try another search or category.',
                  ),
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                sliver: SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (c, i) => _MemoryTile(
                    memory: shown[i],
                    onEdit: () => _edit(shown[i]),
                    onPin: () => _run(() => ref.read(memoryRepoProvider).update(shown[i].id, pinned: !shown[i].pinned), 'Could not update'),
                    onToggle: (v) => _run(() => ref.read(memoryRepoProvider).update(shown[i].id, enabled: v), 'Could not update'),
                    onDelete: () => _run(() => ref.read(memoryRepoProvider).delete(shown[i].id), 'Could not delete'),
                  ),
                ),
              ),
            ];
          },
        ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          shape: const StadiumBorder(),
        ),
      );
}

String _ago(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.memory, required this.onEdit, required this.onPin, required this.onToggle, required this.onDelete});
  final Memory memory;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final m = memory;
    final (srcLabel, srcIcon) = switch (m.source) {
      'auto' => ('auto', NurIcons.sparkle),
      'model' => ('model', NurIcons.agent),
      _ => ('you', NurIcons.person),
    };
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: NurColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NurRadius.card)),
        child: const Icon(NurIcons.delete, color: NurColors.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: Opacity(
        opacity: m.enabled ? 1 : 0.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Directionality(
                    textDirection: textDirOf(m.content),
                    child: SizedBox(width: double.infinity, child: Text(m.content, style: const TextStyle(fontSize: 15, height: 1.4))),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _Badge(_categoryLabels[m.category] ?? m.category),
                    _Badge(srcLabel, icon: srcIcon),
                    if (m.pinned) const _Badge('pinned', icon: NurIcons.pin),
                    Text(
                      m.useCount == 0 ? 'not used yet' : 'used ${m.useCount == 1 ? 'once' : '${m.useCount} times'} · last ${_ago(m.lastUsedAt)}',
                      style: TextStyle(color: nur.subtle, fontSize: 12),
                    ),
                  ]),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'Memory actions',
                icon: Icon(NurIcons.moreVertical, color: nur.muted, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit();
                    case 'pin':
                      onPin();
                    case 'toggle':
                      onToggle(!m.enabled);
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'pin', child: Text(m.pinned ? 'Unpin' : 'Pin (always use)')),
                  PopupMenuItem(value: 'toggle', child: Text(m.enabled ? 'Disable' : 'Enable')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: NurColors.danger))),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: nur.hover, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: nur.muted), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, color: nur.muted)),
      ]),
    );
  }
}

class _EditResult {
  final String content;
  final String category;
  final bool pinned;
  const _EditResult(this.content, this.category, this.pinned);
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({this.memory});
  final Memory? memory;
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _text = TextEditingController(text: widget.memory?.content ?? '');
  late String _category = widget.memory?.category ?? 'general';
  late bool _pinned = widget.memory?.pinned ?? false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.memory == null ? 'New memory' : 'Edit memory', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (c, v, _) => TextField(
            controller: _text,
            autofocus: widget.memory == null,
            minLines: 2,
            maxLines: 6,
            textDirection: textDirOf(v.text),
            decoration: const InputDecoration(hintText: 'e.g. Prefers answers in Arabic · يفضّل الإجابات المختصرة'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in kMemoryCategories)
            ChoiceChip(
              label: Text(_categoryLabels[c] ?? c),
              selected: _category == c,
              showCheckmark: false,
              shape: const StadiumBorder(),
              onSelected: (_) => setState(() => _category = c),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pinned'),
          subtitle: Text('Always included in every chat', style: TextStyle(color: context.nur.muted, fontSize: 13)),
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final t = _text.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(context, _EditResult(t, _category, _pinned));
            },
            child: const Text('Save'),
          ),
        ),
      ]),
    );
  }
}

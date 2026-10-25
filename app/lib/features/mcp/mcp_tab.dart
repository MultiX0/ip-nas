// MCP servers list: add (URL + optional auth header), test, per-tool switches, refresh, remove.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import 'mcp_client.dart';
import 'mcp_manager.dart';

final _serversProvider = StreamProvider.autoDispose<List<McpServer>>((ref) => ref.watch(mcpManagerProvider).watchServers());

class McpTab extends ConsumerWidget {
  const McpTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nur = context.nur;
    final servers = ref.watch(_serversProvider);
    return Stack(children: [
      servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load servers: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(NurIcons.mcp, size: 40, color: nur.subtle),
                    const SizedBox(height: 12),
                    Text('No MCP servers', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Connect Model Context Protocol servers (Streamable HTTP or SSE) to give Nur more tools.',
                        textAlign: TextAlign.center, style: TextStyle(color: nur.muted)),
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: list.length,
                itemBuilder: (c, i) => _ServerCard(server: list[i]),
              ),
      ),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'mcp_add',
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: const StadiumBorder(),
          onPressed: () => showAdaptiveSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _AddServerSheet()),
          icon: const Icon(NurIcons.add),
          label: const Text('Add server'),
        ),
      ),
    ]);
  }
}

class _ServerCard extends ConsumerStatefulWidget {
  const _ServerCard({required this.server});
  final McpServer server;
  @override
  ConsumerState<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<_ServerCard> {
  bool _open = false;
  bool _busy = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final tools = await ref.read(mcpManagerProvider).refresh(widget.server.id);
      _snack('Connected · ${tools.length} tools');
    } catch (e) {
      _snack('Connection failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${widget.server.name}?'),
        content: const Text('Its tools will no longer be available to Nur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(mcpManagerProvider).remove(widget.server.id);
    } catch (e) {
      _snack('Could not remove: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    final nur = context.nur;
    final tools = McpManager.toolsOf(s);
    final off = McpManager.disabledOf(s);
    final mgr = ref.read(mcpManagerProvider);
    final active = tools.where((t) => !off.contains(t.name)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: nur.hover, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          leading: Icon(NurIcons.mcp, color: s.enabled ? null : nur.subtle),
          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${s.transport == 'sse' ? 'SSE' : 'HTTP'} · $active/${tools.length} tools\n${s.url}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 12.5)),
          isThreeLine: true,
          onTap: () => setState(() => _open = !_open),
          trailing: Switch(value: s.enabled, onChanged: (v) => mgr.setEnabled(s.id, v)),
        ),
        if (_open) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              TextButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NurIcons.refresh, size: 18),
                label: const Text('Test & refresh'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: NurColors.danger),
                icon: const Icon(NurIcons.delete, size: 18),
                label: const Text('Remove'),
              ),
            ]),
          ),
          if (tools.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No tools. Tap "Test & refresh".', style: TextStyle(color: nur.muted))),
          for (final t in tools)
            SwitchListTile(
              dense: true,
              title: Text(t.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5)),
              subtitle: t.description.isEmpty
                  ? null
                  : Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 12.5)),
              value: !off.contains(t.name),
              onChanged: (v) => mgr.setToolEnabled(s, t.name, v),
            ),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }
}

class _AddServerSheet extends ConsumerStatefulWidget {
  const _AddServerSheet();
  @override
  ConsumerState<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends ConsumerState<_AddServerSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _hName = TextEditingController();
  final _hValue = TextEditingController();
  String _transport = 'auto';
  bool _busy = false;
  String? _status;
  bool _ok = false;

  void _set(String? status, bool ok) => setState(() {
        _status = status;
        _ok = ok;
      });

  @override
  void dispose() {
    for (final c in [_name, _url, _token, _hName, _hValue]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _headers => {
        if (_token.text.trim().isNotEmpty) 'Authorization': 'Bearer ${_token.text.trim()}',
        if (_hName.text.trim().isNotEmpty && _hValue.text.trim().isNotEmpty) _hName.text.trim(): _hValue.text.trim(),
      };

  String? _validUrl() {
    final u = Uri.tryParse(_url.text.trim());
    if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) return 'Enter the full server URL (http:// or https://).';
    return null;
  }

  Future<void> _test() async {
    final err = _validUrl();
    if (err != null) return _set(err, false);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final (t, tools) = await ref.read(mcpManagerProvider).test(_url.text.trim(), _headers, _transport);
      _set('Connected via ${t == 'sse' ? 'SSE' : 'Streamable HTTP'} · ${tools.length} tools', true);
    } catch (e) {
      _set(e is McpException ? e.message : '$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final err = _validUrl();
    if (err != null) return _set(err, false);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await ref.read(mcpManagerProvider).add(name: _name.text, url: _url.text.trim(), transport: _transport, headers: _headers);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _set('Could not add: ${e is McpException ? e.message : e}', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add MCP server', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Home Assistant')),
        const SizedBox(height: 10),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://host/mcp'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Bearer token (optional)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _hName, autocorrect: false, decoration: const InputDecoration(labelText: 'Header name (optional)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _hValue, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'Header value'))),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'auto', label: Text('Auto')),
            ButtonSegment(value: 'http', label: Text('HTTP')),
            ButtonSegment(value: 'sse', label: Text('SSE (legacy)')),
          ],
          selected: {_transport},
          onSelectionChanged: (v) => setState(() => _transport = v.first),
        ),
        const SizedBox(height: 6),
        Text('Secrets are kept in the device\'s secure storage.', style: TextStyle(color: nur.subtle, fontSize: 12)),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_ok ? NurIcons.success : NurIcons.error, size: 18, color: _ok ? NurColors.ok : NurColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_status!, style: TextStyle(color: _ok ? NurColors.ok : NurColors.danger, fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : _test, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Test connection'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
            ),
          ),
        ]),
      ]),
    );
  }
}

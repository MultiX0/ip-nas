// The "Models & providers" page in Settings: presets, connection test, model refresh, per-model settings.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/contracts/llm.dart';
import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import '../../core/widgets/provider_logo.dart';
import '../../data/db/app_db.dart' hide LlmModel;
import '../models/model_picker_sheet.dart';
import 'capabilities.dart';
import 'llm_registry.dart';
import 'presets.dart';

void _snack(BuildContext context, String m) => showNurToast(context, m, kind: toastKindOf(m));

String _err(Object e) => e.toString().replaceFirst(RegExp(r'^(Exception|Bad state): ?'), '');

IconData _iconFor(String? preset, String kind) => switch (preset ?? kind) {
      'llamacpp' || 'nas' || 'nas_hub' => NurIcons.nas,
      'lmstudio' || 'vllm' => NurIcons.computer,
      'anthropic' => NurIcons.sparkle,
      'custom' => NurIcons.link,
      _ => NurIcons.cloud,
    };

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(providersListProvider);
    ref.watch(modelEntriesProvider);
    final reg = ref.read(llmRegistryProvider);
    final def = ref.watch(defaultModelProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Models & providers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddProvider(context),
        icon: const Icon(NurIcons.add),
        label: const Text('Add provider'),
      ),
      body: providers.when(
        loading: () => const SkeletonList(cards: true, count: 4),
        error: (e, _) => NurEmptyState(icon: NurIcons.error, tone: NurColors.danger, title: 'Could not load providers', body: _err(e)),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyProviders(onAdd: () => showAddProvider(context));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            _Section('Default model'),
            _Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: def == null
                    ? const IconTile(NurIcons.favorite, size: 36)
                    : _LogoTile(ProviderLogo(
                        preset: reg.entryByRef(def.ref)?.preset,
                        kind: reg.entryByRef(def.ref)?.providerKind,
                        modelId: def.modelId,
                        name: def.displayName,
                        size: 20,
                      )),
                title: Text(def?.displayName ?? 'Not set', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: def == null ? null : Text(reg.entryByRef(def.ref)?.providerName ?? '', style: TextStyle(color: context.nur.muted)),
                trailing: Icon(NurIcons.chevron, size: 18, color: context.nur.subtle),
                onTap: () async {
                  final r = await showModelPicker(context, currentRef: def?.ref);
                  if (r != null) await reg.setDefault(r);
                },
              ),
            ),
            _Section('Providers'),
            for (final p in list) _ProviderCard(provider: p),
          ]);
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => NurSectionLabel(text, padding: const EdgeInsetsDirectional.fromSTEB(6, 20, 6, 8));
}

/// Brand logo on a soft bordered tile (provider and model rows).
class _LogoTile extends StatelessWidget {
  const _LogoTile(this.logo);
  final Widget logo;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? NurColors.g800 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: IconTheme(data: IconThemeData(color: Theme.of(context).colorScheme.onSurface), child: logo),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? NurColors.g850.withValues(alpha: 0.55) : Colors.white,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(NurRadius.card),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => NurEmptyState(
        icon: NurIcons.providers,
        title: 'No providers yet',
        body: 'Add llama.cpp on your NAS, or a cloud provider with an API key.',
        action: FilledButton.icon(onPressed: onAdd, icon: const Icon(NurIcons.add), label: const Text('Add provider')),
      );
}

class _ProviderCard extends ConsumerWidget {
  const _ProviderCard({required this.provider});
  final LlmProvider provider;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reg = ref.read(llmRegistryProvider);
    final count = reg.entries(includeHidden: true).where((e) => e.model.providerId == provider.id).length;
    return _Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _LogoTile(ProviderLogo(preset: provider.preset, kind: provider.kind, name: provider.name, size: 20)),
        title: Text(provider.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${provider.enabled ? '$count model${count == 1 ? '' : 's'}' : 'Disabled'} · ${Uri.tryParse(provider.baseUrl)?.host ?? provider.baseUrl}',
          style: TextStyle(color: context.nur.muted),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: provider.enabled ? NurColors.ok : context.nur.subtle),
          ),
          const SizedBox(width: 10),
          Icon(NurIcons.chevron, size: 18, color: context.nur.subtle),
        ]),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProviderDetailPage(providerId: provider.id))),
      ),
    );
  }
}


Future<void> showAddProvider(BuildContext context) async {
  Widget list(BuildContext c, ScrollController? scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
        const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 8), child: Text('Add a provider', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
        _Section('ON YOUR NETWORK'),
        for (final p in providerPresets.where((p) => p.local)) _presetTile(c, p),
        _Section('CLOUD'),
        for (final p in providerPresets.where((p) => !p.local)) _presetTile(c, p),
      ]);
  final desktop = isDesktopLayout(context);
  final preset = await showAdaptiveSheet<ProviderPreset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => desktop
        ? list(c, null)
        : DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (c, scroll) => list(c, scroll),
          ),
  );
  if (preset == null || !context.mounted) return;
  await showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: _ProviderForm(preset: preset)),
  );
}

Widget _presetTile(BuildContext c, ProviderPreset p) => ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      hoverColor: c.nur.hover,
      leading: _LogoTile(_presetLogo(p, 20)),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(p.subtitle, style: TextStyle(color: c.nur.muted)),
      onTap: () => Navigator.pop(c, p),
    );

/// Brand logo of a preset; generic presets (custom server...) keep their icon.
Widget _presetLogo(ProviderPreset p, double size) {
  if (logoFileFor(preset: p.id, kind: p.kind) == null && p.kind != 'nas_hub' && p.id != 'nas') return Icon(_iconFor(p.id, p.kind), size: size * 0.9);
  return ProviderLogo(preset: p.id, kind: p.kind, name: p.name, size: size);
}

class _ProviderForm extends ConsumerStatefulWidget {
  const _ProviderForm({required this.preset, this.existing});
  final ProviderPreset preset;
  final LlmProvider? existing;
  @override
  ConsumerState<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends ConsumerState<_ProviderForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? widget.preset.name);
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? widget.preset.baseUrl);
  final _key = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _createdId;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      ref.read(llmRegistryProvider).apiKey(widget.existing!.id).then((k) {
        if (mounted && k != null) _key.text = k;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  String _normalizedUrl() {
    var u = _url.text.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final p = widget.preset;
    // Local OpenAI-compatible servers: add /v1 when only host:port was given.
    if (p.kind == 'openai_compat' && p.local) {
      final uri = Uri.tryParse(u);
      if (uri != null && (uri.path.isEmpty || uri.path == '/')) u = '$u/v1';
    }
    return u;
  }

  Future<void> _save({bool force = false}) async {
    final reg = ref.read(llmRegistryProvider);
    final url = _normalizedUrl();
    if (Uri.tryParse(url)?.host.isEmpty ?? true) {
      setState(() => _error = 'Enter a valid address, for example http://192.168.1.50:8080');
      return;
    }
    if (widget.preset.needsKey && _key.text.trim().isEmpty) {
      setState(() => _error = 'Paste your API key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String id;
      if (widget.existing != null) {
        id = widget.existing!.id;
        await reg.updateProvider(id, name: _name.text.trim().isEmpty ? null : _name.text.trim(), baseUrl: url, apiKey: _key.text);
      } else if (_createdId != null) {
        id = _createdId!;
        await reg.updateProvider(id, name: _name.text.trim(), baseUrl: url, apiKey: _key.text);
      } else {
        id = await reg.addProvider(
          kind: widget.preset.kind,
          name: _name.text.trim().isEmpty ? widget.preset.name : _name.text.trim(),
          baseUrl: url,
          preset: widget.preset.id,
          apiKey: _key.text,
        );
        _createdId = id;
      }
      final err = force ? null : await reg.testConnection(id);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _busy = false;
          _error = err;
        });
        return;
      }
      final count = reg.entries(includeHidden: true).where((e) => e.model.providerId == id).length;
      Navigator.pop(context);
      _snack(context, force ? 'Saved ${_name.text}' : 'Connected · $count models');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _err(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _LogoTile(_presetLogo(p, 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.existing == null ? 'Connect ${p.name}' : 'Edit ${widget.existing!.name}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 16),
          if (p.needsKey || !p.local) ...[
            TextField(
              controller: _key,
              obscureText: _obscure,
              autofocus: widget.existing == null && p.needsKey,
              decoration: InputDecoration(
                labelText: p.needsKey ? 'API key' : 'API key (optional)',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(NurIcons.paste, size: 18),
                    onPressed: () async {
                      final d = await Clipboard.getData('text/plain');
                      if (d?.text != null) _key.text = d!.text!.trim();
                    },
                  ),
                  IconButton(
                      tooltip: _obscure ? 'Show key' : 'Hide key',
                      icon: Icon(_obscure ? NurIcons.visibility : NurIcons.visibilityOff, size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure)),
                ]),
              ),
            ),
            if (p.keyUrl != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(p.keyUrl!), mode: LaunchMode.externalApplication).catchError((Object _) => false),
                  child: const Text('Get an API key'),
                ),
              ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autofocus: widget.existing == null && p.local,
            decoration: InputDecoration(labelText: 'Server address', helperText: p.local ? 'IP or hostname of the machine running ${p.name}' : null),
          ),
          if (p.local && p.id != 'custom' && !p.needsKey) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('More options', style: TextStyle(color: context.nur.muted, fontSize: 14)),
              children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'API key (optional)')),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NurColors.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(NurRadius.field),
                border: Border.all(color: NurColors.danger.withValues(alpha: 0.25)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(NurIcons.error, size: 16, color: NurColors.danger),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13.5, height: 1.4))),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () => _save(),
            child: AnimatedSwitcher(
              duration: NurMotion.base,
              child: _busy
                  ? const SizedBox(key: ValueKey('busy'), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.existing == null ? 'Connect' : 'Save & test', key: const ValueKey('label')),
            ),
          ),
          if (_error != null && (_createdId != null || widget.existing != null))
            TextButton(onPressed: _busy ? null : () => _save(force: true), child: const Text('Save anyway')),
        ]),
      ),
    );
  }
}


class ProviderDetailPage extends ConsumerStatefulWidget {
  const ProviderDetailPage({super.key, required this.providerId});
  final String providerId;
  @override
  ConsumerState<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends ConsumerState<ProviderDetailPage> {
  bool _refreshing = false;
  String _filter = '';

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final err = await ref.read(llmRegistryProvider).testConnection(widget.providerId);
    if (!mounted) return;
    setState(() => _refreshing = false);
    _snack(context, err ?? 'Models updated');
  }

  Future<void> _delete(LlmProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove provider?'),
        content: Text('${p.name} and its model settings will be removed. The API key is deleted from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(llmRegistryProvider).deleteProvider(p.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(providersListProvider);
    ref.watch(modelEntriesProvider);
    final reg = ref.read(llmRegistryProvider);
    final p = reg.provider(widget.providerId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Provider removed')));
    final all = reg.entries(includeHidden: true).where((e) => e.model.providerId == p.id).toList();
    final q = _filter.toLowerCase();
    final models = q.isEmpty ? all : all.where((e) => e.model.displayName.toLowerCase().contains(q) || e.model.modelId.toLowerCase().contains(q)).toList();
    final preset = presetById(p.preset) ??
        ProviderPreset(id: p.preset ?? 'custom', name: p.name, kind: p.kind == 'nas_hub' ? 'openai_compat' : p.kind, baseUrl: p.baseUrl, needsKey: false, local: true, subtitle: '');
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(NurIcons.edit),
            onPressed: () => showAdaptiveSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: _ProviderForm(preset: preset, existing: p)),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(NurIcons.more),
            onSelected: (v) {
              if (v == 'delete') _delete(p);
            },
            itemBuilder: (_) => [menuRow('delete', NurIcons.delete, 'Remove provider', danger: true)],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        _Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Enabled'),
              subtitle: Text(p.baseUrl, style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
              value: p.enabled,
              onChanged: (v) => reg.updateProvider(p.id, enabled: v),
            ),
            const Divider(),
            ListTile(
              leading: _refreshing
                  ? const SizedBox(width: 36, height: 36, child: Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2)))
                  : const IconTile(NurIcons.sync, size: 36),
              title: const Text('Test connection & refresh models'),
              subtitle: Text('Detects vision, tools, reasoning and context size', style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
              onTap: _refreshing ? null : _refresh,
            ),
          ]),
        ),
        _Section('Models (${all.length})'),
        if (all.length > 8)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: const InputDecoration(hintText: 'Filter models', prefixIcon: Icon(NurIcons.search, size: 18), isDense: true),
            ),
          ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No models yet. Tap "Test connection & refresh models".', textAlign: TextAlign.center, style: TextStyle(color: context.nur.muted)),
          ),
        for (final e in models)
          _Card(
            child: ListTile(
              leading: Opacity(
                opacity: e.hidden ? 0.5 : 1,
                child: _LogoTile(ProviderLogo(preset: e.preset, kind: e.providerKind, modelId: e.model.modelId, name: e.model.displayName, size: 20)),
              ),
              title: Text(e.model.displayName, style: TextStyle(fontWeight: FontWeight.w500, color: e.hidden ? context.nur.subtle : null)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Flexible(child: Text(e.model.modelId, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.nur.muted))),
                  const SizedBox(width: 8),
                  CapabilityBadges(caps: e.model.caps, size: 13),
                ]),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.hidden) Icon(NurIcons.visibilityOff, size: 16, color: context.nur.subtle),
                IconButton(
                  tooltip: e.favorite ? 'Remove from favorites' : 'Add to favorites',
                  icon: Icon(NurIcons.favorite, size: 18, color: e.favorite ? NurColors.warn : context.nur.subtle),
                  onPressed: () => reg.updateModel(e.ref, favorite: !e.favorite),
                ),
              ]),
              onTap: () => showModelSettings(context, e),
            ),
          ),
      ]),
    );
  }
}


Future<void> showModelSettings(BuildContext context, ModelEntry e) => showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: _ModelSettings(entry: e)),
    );

class _ModelSettings extends ConsumerStatefulWidget {
  const _ModelSettings({required this.entry});
  final ModelEntry entry;
  @override
  ConsumerState<_ModelSettings> createState() => _ModelSettingsState();
}

class _ModelSettingsState extends ConsumerState<_ModelSettings> {
  late final _name = TextEditingController(text: widget.entry.model.displayName);
  late final _ctx = TextEditingController(text: widget.entry.overrides.contextWindow?.toString() ?? '');
  late bool? _vision = widget.entry.overrides.vision;
  late bool? _tools = widget.entry.overrides.tools;
  late bool? _reasoning = widget.entry.overrides.reasoning;
  late bool? _canDisable = widget.entry.overrides.reasoningCanDisable;
  late double? _temp = widget.entry.overrides.temperature;
  late ReasoningLevel? _defReasoning = widget.entry.overrides.defaultReasoning;
  late bool _fav = widget.entry.favorite;
  late bool _hidden = widget.entry.hidden;

  @override
  void dispose() {
    _name.dispose();
    _ctx.dispose();
    super.dispose();
  }

  ModelOverrides get _ov => ModelOverrides(
        vision: _vision,
        tools: _tools,
        reasoning: _reasoning,
        reasoningCanDisable: _canDisable,
        contextWindow: int.tryParse(_ctx.text.trim().replaceAll(RegExp(r'[^0-9]'), '')),
        temperature: _temp,
        defaultReasoning: _defReasoning,
        // Not edited in this sheet: keep them (sampling preset choice, small-model mode).
        samplingMode: widget.entry.overrides.samplingMode,
        samplingCustom: widget.entry.overrides.samplingCustom,
        smallModel: widget.entry.overrides.smallModel,
      );

  Future<void> _save() async {
    try {
      await ref.read(llmRegistryProvider).updateModel(
            widget.entry.ref,
            displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
            overrides: _ov,
            favorite: _fav,
            hidden: _hidden,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  Widget _capSwitch(String title, String sub, bool detected, bool? value, ValueChanged<bool?> set) {
    final eff = value ?? detected;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value == null ? '$sub · detected' : '$sub · set by you', style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
      value: eff,
      onChanged: (v) => setState(() => set(v == detected ? null : v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.entry.detected;
    final caps = _ov.apply(d);
    final levels = pillLevels(caps);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.entry.model.modelId, style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name')),
          const SizedBox(height: 8),
          _capSwitch('Vision', 'Can read images', d.vision, _vision, (v) => _vision = v),
          _capSwitch('Tools', 'Can call tools (NAS, web search, MCP)', d.tools, _tools, (v) => _tools = v),
          _capSwitch('Reasoning', 'Thinks before answering', d.reasoning, _reasoning, (v) => _reasoning = v),
          if (caps.reasoning) _capSwitch('Thinking can be turned off', 'Shows "Off" in the reasoning menu', d.reasoningCanDisable, _canDisable, (v) => _canDisable = v),
          const SizedBox(height: 6),
          TextField(
            controller: _ctx,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Context window (tokens)',
              hintText: d.contextWindow == null ? 'Unknown' : '${d.contextWindow} (detected)',
              helperText: null,
            ),
          ),
          if (levels.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<ReasoningLevel?>(
              initialValue: levels.contains(_defReasoning) ? _defReasoning : null,
              decoration: const InputDecoration(labelText: 'Default reasoning'),
              items: [
                const DropdownMenuItem<ReasoningLevel?>(value: null, child: Text('Automatic (medium)')),
                for (final l in levels) DropdownMenuItem<ReasoningLevel?>(value: l, child: Text(l.name[0].toUpperCase() + l.name.substring(1))),
              ],
              onChanged: (v) => setState(() => _defReasoning = v),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            const Text('Temperature'),
            const Spacer(),
            Text(_temp == null ? 'Default' : _temp!.toStringAsFixed(1), style: TextStyle(color: context.nur.muted)),
            if (_temp != null) IconButton(icon: const Icon(NurIcons.reset, size: 18), onPressed: () => setState(() => _temp = null), tooltip: 'Use default'),
          ]),
          Slider(value: _temp ?? 0.7, min: 0, max: 2, divisions: 20, onChanged: (v) => setState(() => _temp = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Favorite'), value: _fav, onChanged: (v) => setState(() => _fav = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hide from model menu'), value: _hidden, onChanged: (v) => setState(() => _hidden = v)),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: () => setState(() {
                _vision = _tools = _reasoning = _canDisable = null;
                _ctx.clear();
                _temp = null;
                _defReasoning = null;
              }),
              child: const Text('Reset to detected'),
            ),
            const Spacer(),
            TextButton(onPressed: () => ref.read(llmRegistryProvider).setDefault(widget.entry.ref).then((_) {
                  if (context.mounted) _snack(context, 'Default model set');
                }), child: const Text('Make default')),
            const SizedBox(width: 6),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ]),
        ]),
      ),
    );
  }
}

// Model picker (search, favorites, capability badges, brand logos): bottom sheet on phones, anchored popover on desktop.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/llm.dart';
import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import '../../core/widgets/provider_logo.dart';
import '../providers/capabilities.dart';
import '../providers/llm_registry.dart';
import '../shell/settings_dialog.dart';

class CapabilityBadges extends StatelessWidget {
  const CapabilityBadges({super.key, required this.caps, this.size = 14});
  final ModelCapabilities caps;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.nur.muted;
    Widget icon(IconData i, String tip) => Tooltip(message: tip, child: Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Icon(i, size: size - 1, color: c)));
    final ctx = formatCtx(caps.contextWindow);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (caps.vision) icon(NurIcons.vision, 'Vision'),
      if (caps.tools) icon(NurIcons.tools, 'Tools'),
      if (caps.reasoning) icon(NurIcons.think, 'Reasoning'),
      if (ctx.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: context.nur.hover, borderRadius: BorderRadius.circular(NurRadius.pill)),
          child: Text(ctx, style: TextStyle(fontSize: size - 3, color: c, fontWeight: FontWeight.w600, letterSpacing: 0.1)),
        ),
    ]);
  }
}

/// Shows the picker; returns the chosen model ref. On desktop it opens as a popover anchored to [anchor]
/// (or a centered dialog without an anchor); on phones as a bottom sheet.
Future<String?> showModelPicker(BuildContext context, {String? currentRef, BuildContext? anchor}) {
  if (isDesktopLayout(context)) {
    if (anchor != null) {
      return showAnchoredPopover<String>(
        anchorContext: anchor,
        width: 420,
        maxHeight: 560,
        padding: const EdgeInsets.only(top: 12),
        builder: (_) => _ModelPicker(currentRef: currentRef, desktop: true),
      );
    }
    return showDialog<String>(
      context: context,
      builder: (_) => DesktopSheetDialog(maxWidth: 480, maxHeightFraction: 0.8, child: _ModelPicker(currentRef: currentRef, desktop: true)),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (c, scroll) => _ModelPicker(currentRef: currentRef, scroll: scroll),
    ),
  );
}

class _ModelPicker extends ConsumerStatefulWidget {
  const _ModelPicker({required this.currentRef, this.scroll, this.desktop = false});
  final String? currentRef;
  final ScrollController? scroll;
  final bool desktop;
  @override
  ConsumerState<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends ConsumerState<_ModelPicker> {
  final _q = TextEditingController();
  late final ScrollController _ownScroll = ScrollController();
  String _query = '';

  ScrollController get _scroll => widget.scroll ?? _ownScroll;

  @override
  void dispose() {
    _q.dispose();
    _ownScroll.dispose();
    super.dispose();
  }

  void _manage() {
    Navigator.pop(context);
    openSettings(context, SettingsSection.providers);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(modelEntriesProvider).value ?? const <ModelEntry>[];
    final defaultRef = ref.watch(defaultModelProvider).value?.ref;
    final q = _query.toLowerCase();
    final list = q.isEmpty
        ? entries
        : entries.where((e) => e.model.displayName.toLowerCase().contains(q) || e.model.modelId.toLowerCase().contains(q) || e.providerName.toLowerCase().contains(q)).toList();
    final favs = list.where((e) => e.favorite).toList();
    final byProvider = <String, List<ModelEntry>>{};
    for (final e in list.where((e) => !e.favorite)) {
      (byProvider[e.providerName] ??= []).add(e);
    }
    final reg = ref.read(llmRegistryProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget header(String t, {ModelEntry? logoOf}) => Padding(
          padding: EdgeInsetsDirectional.fromSTEB(widget.desktop ? 18 : 22, 14, 20, 6),
          child: Row(children: [
            if (logoOf != null) ...[
              IconTheme(
                data: IconThemeData(color: context.nur.muted),
                child: ProviderLogo(preset: logoOf.preset, kind: logoOf.providerKind, name: logoOf.providerName, size: 13),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(child: Text(t, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.nur.muted, letterSpacing: 0.6))),
          ]),
        );
    Widget tile(ModelEntry e) {
      final selected = e.ref == widget.currentRef;
      final logoSize = widget.desktop ? 18.0 : 20.0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: NurPressable(
          onTap: () => Navigator.pop(context, e.ref),
          selected: selected,
          borderRadius: BorderRadius.circular(NurRadius.row),
          pressedScale: 0.99,
          padding: EdgeInsetsDirectional.fromSTEB(10, widget.desktop ? 6 : 8, 4, widget.desktop ? 6 : 8),
          child: Row(children: [
            // Brand logo on a soft tile (ChatGPT / Perplexity model menu look).
            Container(
              width: logoSize + 16,
              height: logoSize + 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? NurColors.g800 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: IconTheme(
                data: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
                child: ProviderLogo(preset: e.preset, kind: e.providerKind, modelId: e.model.modelId, name: e.model.displayName, size: logoSize),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(
                    child: Text(e.model.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  ),
                  if (e.ref == defaultRef)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: NurTag('default'),
                    ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Flexible(child: Text(e.providerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: context.nur.muted))),
                  const SizedBox(width: 8),
                  CapabilityBadges(caps: e.model.caps, size: 13),
                ]),
              ]),
            ),
            if (selected) const Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(NurIcons.check, size: 18)),
            NurIconButton(
              tooltip: e.favorite ? 'Remove from favorites' : 'Add to favorites',
              icon: NurIcons.favorite,
              size: 17,
              box: 32,
              color: e.favorite ? NurColors.warn : context.nur.subtle,
              onTap: () => reg.updateModel(e.ref, favorite: !e.favorite),
            ),
            _moreMenu(e, reg),
          ]),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _q,
          autofocus: widget.desktop,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: const InputDecoration(hintText: 'Search models', prefixIcon: Icon(NurIcons.search, size: 18), isDense: true),
        ),
      ),
      Expanded(
        child: entries.isEmpty
            ? _EmptyModels(onManage: _manage)
            : ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 8), children: [
                if (favs.isNotEmpty) ...[header('FAVORITES'), ...favs.map(tile)],
                for (final p in byProvider.entries) ...[header(p.key.toUpperCase(), logoOf: p.value.first), ...p.value.map(tile)],
                if (list.isEmpty)
                  NurEmptyState(icon: NurIcons.search, title: 'No models match "$_query"', body: 'Try a shorter name or a provider.', compact: true),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: NurPressable(
                    onTap: _manage,
                    borderRadius: BorderRadius.circular(NurRadius.row),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Row(children: [
                      Icon(NurIcons.tune, size: 18, color: context.nur.muted),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Manage models & providers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                      Icon(NurIcons.chevron, size: 16, color: context.nur.subtle),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
      ),
    ]);
  }

  Widget _moreMenu(ModelEntry e, LlmRegistry reg) => PopupMenuButton<String>(
            tooltip: 'Model options',
            icon: Icon(NurIcons.moreVertical, size: 17, color: context.nur.subtle),
            onSelected: (v) {
              if (v == 'default') reg.setDefault(e.ref);
              if (v == 'hide') reg.updateModel(e.ref, hidden: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'default', child: Text('Set as default')),
              PopupMenuItem(value: 'hide', child: Text('Hide model')),
            ],
          );
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels({required this.onManage});
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) => NurEmptyState(
    icon: NurIcons.models,
    title: 'No models yet',
    body: 'Connect your NAS, a local server or a cloud provider.',
    action: FilledButton(onPressed: onManage, child: const Text('Add a provider')),
  );
}

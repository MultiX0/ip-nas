// Message views: user bubbles, assistant turns (reasoning, markdown, tool cards, footer), markers.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/desktop.dart';
import '../../../core/theme/nur_theme.dart';
import '../../../core/utils/text_dir.dart';
import '../../../core/widgets/nur_icons.dart';
import '../../../core/widgets/nur_ui.dart';
import '../../../core/widgets/provider_logo.dart';
import '../../../data/db/app_db.dart' hide LlmModel;
import '../../providers/llm_registry.dart';
import '../../tools/tool_call_card.dart';
import '../../voice/voice_buttons.dart';
import '../chat_providers.dart';
import '../data/chat_repo.dart';
import '../engine/chat_engine_provider.dart';
import '../engine/live_store.dart';
import 'common.dart';
import 'markdown_view.dart';

const _maxWidth = 760.0;
const _desktopMaxWidth = 800.0; // 768 px column + 16 px side padding

/// Only messages created in the last few seconds animate in (scrolling back never re-animates old ones).
bool _isFresh(DateTime createdAt) => DateTime.now().difference(createdAt).inMilliseconds.abs() < 4000;

/// Centers content with a readable max width (tablets / desktop).
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktopLayout(context) ? _desktopMaxWidth : _maxWidth),
          // Full column width, so user bubbles sit at the right edge (not centered under Center's loose constraints).
          child: SizedBox(width: double.infinity, child: Padding(padding: padding, child: child)),
        ),
      );
}


class BranchNav extends ConsumerWidget {
  const BranchNav({super.key, required this.chatId, required this.current, required this.siblings, this.enabled = true});
  final String chatId;
  final Message current;
  final List<Message> siblings;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (siblings.length < 2) return const SizedBox.shrink();
    final i = siblings.indexWhere((m) => m.id == current.id);
    final idx = i < 0 ? 0 : i;
    Future<void> go(int d) => guard(context, () => ref.read(chatEngineImplProvider).switchBranch(chatId, siblings[idx + d]));
    final style = TextStyle(fontSize: 13, color: context.nur.muted, fontFeatures: const [FontFeature.tabularFigures()]);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SmallIconButton(icon: NurIcons.chevronLeft, tooltip: 'Previous version', onTap: enabled && idx > 0 ? () => go(-1) : null, size: 16, padding: 6),
        Text('${idx + 1}/${siblings.length}', style: style),
        SmallIconButton(icon: NurIcons.chevronRight, tooltip: 'Next version', onTap: enabled && idx < siblings.length - 1 ? () => go(1) : null, size: 16, padding: 6),
      ]),
    );
  }
}


class UserMessageView extends ConsumerStatefulWidget {
  const UserMessageView({super.key, required this.chatId, required this.item, required this.busy});
  final String chatId;
  final UserItem item;
  final bool busy;
  @override
  ConsumerState<UserMessageView> createState() => _UserMessageViewState();
}

class _UserMessageViewState extends ConsumerState<UserMessageView> {
  bool _editing = false;
  TextEditingController? _edit;

  @override
  void dispose() {
    _edit?.dispose();
    super.dispose();
  }

  Message get m => widget.item.msg;

  void _menu() {
    final text = stripFileBlocks(m.content);
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(NurIcons.copy),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(c);
              Clipboard.setData(ClipboardData(text: text));
              showSnack(context, 'Copied');
            },
          ),
          ListTile(
            leading: const Icon(NurIcons.edit),
            title: const Text('Edit message'),
            enabled: !widget.busy,
            onTap: () {
              Navigator.pop(c);
              _startEdit();
            },
          ),
        ]),
      ),
    );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: stripFileBlocks(m.content)));
    showSnack(context, 'Copied');
  }

  Future<void> _menuAt(Offset pos) async {
    final v = await showContextMenuAt<String>(context, pos, [
      menuRow('copy', NurIcons.copy, 'Copy'),
      menuRow('edit', NurIcons.edit, 'Edit message', enabled: !widget.busy),
    ]);
    if (!mounted) return;
    if (v == 'copy') _copy();
    if (v == 'edit') _startEdit();
  }

  void _startEdit() {
    _edit?.dispose();
    _edit = TextEditingController(text: stripFileBlocks(m.content));
    setState(() => _editing = true);
  }

  Future<void> _submitEdit() async {
    final t = _edit?.text.trim() ?? '';
    if (t.isEmpty) return;
    setState(() => _editing = false);
    await guard(context, () => ref.read(chatEngineImplProvider).editAndResend(widget.chatId, m, t));
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final text = stripFileBlocks(m.content);
    final files = fileNamesIn(m.content);
    final images = attachmentsOf(m).where((a) => a['type'] == 'image' && a['path'] is String).map((a) => a['path'] as String).toList();
    final dir = textDirOf(text);
    final desktop = isDesktopLayout(context);
    if (_editing) {
      return Readable(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            color: nur.userBubble,
            borderRadius: BorderRadius.circular(NurRadius.sheet),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CallbackShortcuts(
              bindings: {
                if (desktop) const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _editing = false),
              },
              child: TextField(
              controller: _edit,
              autofocus: true,
              minLines: 1,
              maxLines: 10,
              textDirection: textDirOf(_edit!.text),
              decoration: const InputDecoration(filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
            ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
              const SizedBox(width: 6),
              FilledButton(onPressed: _submitEdit, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)), child: const Text('Send')),
            ]),
          ]),
        ),
      );
    }
    return AppearIn(
      enabled: _isFresh(m.createdAt),
      child: HoverScope(
      enabled: desktop,
      child: Readable(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
              for (final p in images) ImageThumb(path: p, size: images.length == 1 ? 180 : 110),
            ]),
          ),
        if (files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [for (final f in files) _FileChip(name: f)]),
          ),
        if (text.isNotEmpty)
          GestureDetector(
            onLongPress: desktop ? null : _menu,
            onSecondaryTap: desktop ? null : _menu,
            onSecondaryTapUp: desktop ? (d) => _menuAt(d.globalPosition) : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: desktop ? _desktopMaxWidth * 0.75 : MediaQuery.sizeOf(context).width * 0.8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: nur.userBubble, borderRadius: BorderRadius.circular(NurRadius.sheet)),
                child: Directionality(
                  textDirection: dir,
                  child: Text(text, style: const TextStyle(fontSize: 16, height: 1.45)),
                ),
              ),
            ),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (desktop && text.isNotEmpty)
            HoverReveal(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CopyButton(text: () => stripFileBlocks(m.content), box: 30),
                SmallIconButton(icon: NurIcons.edit, tooltip: 'Edit message', size: 16, onTap: widget.busy ? null : _startEdit),
              ]),
            ),
          if (m.audioPath != null) Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Icon(NurIcons.mic, size: 14, color: nur.subtle)),
          BranchNav(chatId: widget.chatId, current: m, siblings: widget.item.siblings, enabled: !widget.busy),
        ]),
      ]),
      ),
    ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 6),
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(NurRadius.field)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const IconTile(NurIcons.file, size: 30),
          const SizedBox(width: 8),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
}


class ReasoningView extends StatefulWidget {
  const ReasoningView({super.key, required this.text, required this.thinking, this.ms});
  final String text;
  final bool thinking;
  final int? ms;
  @override
  State<ReasoningView> createState() => _ReasoningViewState();
}

class _ReasoningViewState extends State<ReasoningView> with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.thinking) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ReasoningView old) {
    super.didUpdateWidget(old);
    if (widget.thinking && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.thinking && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _label {
    if (widget.thinking) return 'Thinking...';
    final ms = widget.ms;
    if (ms == null) return 'Thoughts';
    final s = (ms / 1000).round();
    if (s < 1) return 'Thought for a moment';
    if (s < 60) return 'Thought for ${s}s';
    return 'Thought for ${s ~/ 60}m ${s % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final header = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FadeTransition(
            opacity: widget.thinking ? Tween(begin: 0.35, end: 1.0).animate(_pulse) : const AlwaysStoppedAnimation(1),
            child: Text(_label, style: TextStyle(color: nur.muted, fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: _open ? (Directionality.of(context) == TextDirection.rtl ? -0.25 : 0.25) : 0,
            duration: NurMotion.base,
            curve: NurMotion.curve,
            child: Icon(NurIcons.chevron, size: 16, color: nur.muted),
          ),
        ]),
      ),
    );
    final text = widget.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: !_open || text.isEmpty
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8, top: 2),
                padding: const EdgeInsetsDirectional.only(start: 12),
                decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 2))),
                child: Directionality(
                  textDirection: textDirOf(text),
                  child: Text(
                    // Long live reasoning: show the tail only while streaming to keep layout cheap.
                    widget.thinking && text.length > 4000 ? '...${text.substring(text.length - 4000)}' : text,
                    style: TextStyle(color: nur.muted, fontSize: 14, height: 1.5),
                  ),
                ),
              ),
      ),
    ]);
  }
}


class AssistantTurnView extends ConsumerWidget {
  const AssistantTurnView({super.key, required this.chatId, required this.item, required this.isLast, required this.busy});
  final String chatId;
  final AssistantItem item;
  final bool isLast;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveStoreProvider);
    final turnStreaming = item.group.any((m) => m.status == 'streaming');
    final children = <Widget>[];
    for (final m in item.group) {
      final notifier = m.status == 'streaming' ? live.of(m.id) : null;
      if (notifier != null) {
        children.add(ValueListenableBuilder<LiveMessage>(
          valueListenable: notifier,
          builder: (context, v, _) => _AssistantPart(m: m, content: v.content, reasoning: v.reasoning, thinking: v.thinking, reasoningMs: v.reasoningMs, streaming: true),
        ));
      } else {
        children.add(_AssistantPart(m: m, content: m.content, reasoning: m.reasoning ?? '', thinking: false, reasoningMs: m.reasoningMs, streaming: m.status == 'streaming'));
      }
      for (final call in toolCallsOf(m)) {
        final res = item.toolResults[call.id];
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ToolCallCard(
            name: call.name,
            argumentsJson: call.argumentsJson,
            resultJson: res?.toolResultJson,
            running: res == null ? turnStreaming || busy : res.status == 'streaming',
          ),
        ));
      }
      if (m.status == 'error') {
        children.add(_ErrorBox(text: m.errorText ?? 'Something went wrong.', onRetry: isLast && !busy ? () => guard(context, () => ref.read(chatEngineImplProvider).retry(chatId, m)) : null));
      }
    }
    final showFooter = !turnStreaming && !(busy && isLast) && item.last.status != 'error';
    final desktop = isDesktopLayout(context);
    // Desktop: actions show on hover (always on the latest reply), like ChatGPT desktop.
    return AppearIn(
      enabled: _isFresh(item.first.createdAt),
      offset: 4,
      child: HoverScope(
      enabled: desktop,
      child: Readable(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...children,
          if (item.last.status == 'cancelled' && item.fullText.isEmpty)
            Text('Stopped', style: TextStyle(color: context.nur.subtle, fontStyle: FontStyle.italic)),
          if (showFooter) HoverReveal(always: isLast || item.siblings.length > 1, child: _Footer(chatId: chatId, item: item, busy: busy)),
          if (!showFooter && item.siblings.length > 1 && !turnStreaming)
            Align(alignment: AlignmentDirectional.centerStart, child: BranchNav(chatId: chatId, current: item.first, siblings: item.siblings, enabled: !busy)),
        ]),
      ),
    ),
    );
  }
}

class _AssistantPart extends StatelessWidget {
  const _AssistantPart({required this.m, required this.content, required this.reasoning, required this.thinking, required this.reasoningMs, required this.streaming});
  final Message m;
  final String content;
  final String reasoning;
  final bool thinking;
  final int? reasoningMs;
  final bool streaming;
  @override
  Widget build(BuildContext context) {
    final hasReasoning = reasoning.trim().isNotEmpty || thinking;
    final empty = content.trim().isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasReasoning) ReasoningView(text: reasoning, thinking: thinking, ms: reasoningMs),
      if (!empty)
        Directionality(
          textDirection: textDirOf(content),
          child: SelectionArea(child: NurMarkdown(text: content, streaming: streaming, direction: textDirOf(content))),
        ),
      if (streaming && empty && !hasReasoning && m.toolCallsJson == null) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: TypingDots()),
    ]);
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: NurColors.danger.withValues(alpha: 0.07),
          border: Border.all(color: NurColors.danger.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(NurRadius.card),
        ),
        child: Row(children: [
          const Icon(NurIcons.error, color: NurColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
          if (onRetry != null) TextButton.icon(onPressed: onRetry, icon: const Icon(NurIcons.regenerate, size: 16), label: const Text('Retry')),
        ]),
      );
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.chatId, required this.item, required this.busy});
  final String chatId;
  final AssistantItem item;
  final bool busy;

  void _info(BuildContext context, WidgetRef ref) {
    final last = item.last;
    final entry = ref.read(llmRegistryProvider).entryByRef(last.modelRef);
    final prompt = item.group.map((m) => m.promptTokens ?? 0).fold<int>(0, (a, b) => b > a ? b : a);
    final completion = item.group.map((m) => m.completionTokens ?? 0).fold<int>(0, (a, b) => a + b);
    final tps = item.group.map((m) => m.tokensPerSecond).whereType<double>().fold<double?>(null, (a, b) => b);
    final thinkMs = item.group.map((m) => m.reasoningMs ?? 0).fold<int>(0, (a, b) => a + b);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: context.nur.muted))), Text(v, style: const TextStyle(fontWeight: FontWeight.w500))]),
        );
    showAdaptiveSheet<void>(
      context: context,
      maxWidth: 420,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (entry != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  ProviderLogo(preset: entry.preset, kind: entry.providerKind, modelId: entry.model.modelId, name: entry.model.displayName, size: 26),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.model.displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ]),
              ),
            row('Model', entry?.model.displayName ?? (last.modelRef?.split('::').last ?? 'Unknown')),
            if (entry != null) row('Provider', entry.providerName),
            if (prompt > 0) row('Prompt tokens', '$prompt'),
            if (completion > 0) row('Output tokens', '$completion'),
            if (tps != null) row('Speed', '${tps.toStringAsFixed(1)} tok/s'),
            if (thinkMs > 0) row('Thinking time', '${(thinkMs / 1000).toStringAsFixed(1)} s'),
            if (item.group.length > 1) row('Tool rounds', '${item.group.length - 1}'),
            row('Time', MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(last.createdAt))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = item.fullText;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (text.isNotEmpty) CopyButton(text: () => text, size: 17, box: 32),
        if (text.isNotEmpty) ReadAloudButton(text: text),
        SmallIconButton(
          icon: NurIcons.regenerate,
          size: 17,
          tooltip: 'Regenerate',
          onTap: busy || item.userId == null ? null : () => unawaited(guard(context, () => ref.read(chatEngineImplProvider).regenerate(chatId, item.userId!))),
        ),
        SmallIconButton(icon: NurIcons.info, size: 17, tooltip: 'Details', onTap: () => _info(context, ref)),
        BranchNav(chatId: chatId, current: item.first, siblings: item.siblings, enabled: !busy),
      ]),
    );
  }
}


class MarkerView extends StatelessWidget {
  const MarkerView({super.key, required this.msg});
  final Message msg;
  @override
  Widget build(BuildContext context) {
    final label = switch (msg.kind) {
      'summary' => 'Earlier messages were summarized',
      'context_reset' => 'Context cleared: the model starts fresh from here',
      _ => msg.kind,
    };
    return Readable(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(label, style: TextStyle(color: context.nur.muted, fontSize: 12.5))),
        const Expanded(child: Divider()),
      ]),
    );
  }
}

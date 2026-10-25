// Context gauge for the composer row + breakdown sheet (used/total, slices, compact, clear, auto-compact).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/desktop.dart';
import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import 'context_assembler_impl.dart';
import 'intel_settings.dart';
import 'llm_access.dart';

/// Small circular gauge of context usage; tap opens the breakdown sheet (compact / clear).
class ContextRing extends ConsumerWidget {
  const ContextRing({super.key, required this.chatId});
  final String? chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(contextInfoProvider(chatId ?? '')).value ?? ContextInfo.empty;
    final b = info.breakdown;
    final f = b.contextWindow <= 0 ? 0.0 : b.used / b.contextWindow;
    final color = gaugeColor(context, f);
    final pct = '${(f * 100).clamp(0, 999).toStringAsFixed(0)}%';
    return Tooltip(
      triggerMode: TooltipTriggerMode.longPress,
      message: b.contextWindow <= 0 ? 'Context' : '$pct · ${fmtTokens(b.used)} / ${fmtTokens(b.contextWindow)} tokens',
      child: Semantics(
        button: true,
        label: 'Context usage $pct',
        child: InkResponse(
          radius: 20,
          onTap: () => showContextSheet(context, chatId),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: 22,
              height: 22,
              child: info.compacting
                  ? CircularProgressIndicator(strokeWidth: 2.4, color: context.nur.muted)
                  : CustomPaint(painter: _RingPainter(f.clamp(0, 1).toDouble(), color, Theme.of(context).colorScheme.outlineVariant)),
            ),
          ),
        ),
      ),
    );
  }
}

Color gaugeColor(BuildContext context, double f) {
  if (f > 0.9) return NurColors.danger;
  if (f > 0.7) return NurColors.warn;
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
}

String fmtTokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.6;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    if (value > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * math.max(value, 0.03), false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

const sliceColors = {
  Slices.system: Color(0xFF3B82F6),
  Slices.memories: Color(0xFF10A37F),
  Slices.skills: Color(0xFFEAB308),
  Slices.tools: Color(0xFF06B6D4),
  Slices.summary: Color(0xFFF97316),
  Slices.messages: Color(0xFF8E8E8E),
  Slices.images: Color(0xFFEC4899),
};

/// Breakdown: bottom sheet on phones, popover anchored to the ring on desktop.
Future<void> showContextSheet(BuildContext context, String? chatId) {
  if (isDesktopLayout(context)) {
    return showAnchoredPopover<void>(
      anchorContext: context,
      width: 420,
      maxHeight: 640,
      alignEnd: true,
      padding: const EdgeInsets.only(top: 18),
      builder: (_) => _ContextSheet(chatId: chatId),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ContextSheet(chatId: chatId),
  );
}

class _ContextSheet extends ConsumerStatefulWidget {
  const _ContextSheet({required this.chatId});
  final String? chatId;
  @override
  ConsumerState<_ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends ConsumerState<_ContextSheet> {
  bool _busy = false;
  double? _threshold; // while dragging

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _compact() async {
    final id = widget.chatId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(dbProvider);
      final chat = await (db.select(db.chats)..where((c) => c.id.equals(id))).getSingleOrNull();
      final llm = ref.read(intelLlmProvider);
      await llm.ready();
      final model = llm.modelByRef(chat?.modelRef) ?? await llm.defaultModel();
      if (model == null) throw StateError('Choose a model first.');
      await ref.read(nurContextAssemblerProvider).compact(chatId: id, model: model);
      _snack('Context compacted');
    } catch (e) {
      _snack(e is StateError ? e.message : 'Could not compact: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final id = widget.chatId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear context?'),
        content: const Text('The model will start fresh from the next message. Your messages stay visible in the chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(nurContextAssemblerProvider).clearContext(chatId: id);
      _snack('Context cleared');
    } catch (e) {
      _snack('Could not clear the context: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(contextInfoProvider(widget.chatId ?? '')).value ?? ContextInfo.empty;
    final b = info.breakdown;
    final theme = Theme.of(context);
    final nur = context.nur;
    final f = b.contextWindow <= 0 ? 0.0 : b.used / b.contextWindow;
    final slices = [
      for (final l in Slices.order)
        for (final s in b.slices)
          if (s.label == l && s.tokens > 0) s
    ];
    final free = math.max(0, b.contextWindow - b.used);
    final auto = ref.watch(boolSettingProvider((IntelKeys.autoCompact, true))).value ?? true;
    final thrRaw = double.tryParse(ref.watch(stringSettingProvider(IntelKeys.autoCompactThreshold)).value ?? '') ?? 0.8;
    final thr = _threshold ?? thrRaw.clamp(0.5, 0.95);
    final hasChat = widget.chatId != null;
    final busy = _busy || info.compacting;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Context window', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          _Pill(b.exact ? 'Exact' : 'Estimated', tooltip: b.exact ? 'Counted with the model\'s tokenizer' : 'Approximate count (the backend has no tokenizer endpoint)'),
        ]),
        if (info.modelName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${info.modelName}${info.windowKnown ? '' : ' · window size unknown, assuming ${fmtTokens(b.contextWindow)}'}',
              style: TextStyle(color: nur.muted, fontSize: 13),
            ),
          ),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(_grouped(b.used), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          Text('  / ${_grouped(b.contextWindow)} tokens', style: TextStyle(color: nur.muted)),
          const Spacer(),
          Text('${(f * 100).toStringAsFixed(f < 0.1 ? 1 : 0)}%',
              style: theme.textTheme.titleMedium?.copyWith(color: gaugeColor(context, f), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: LayoutBuilder(builder: (c, cons) {
              final total = math.max(b.contextWindow, b.used);
              if (total <= 0) return Container(color: theme.colorScheme.outlineVariant);
              return Row(children: [
                for (final s in slices)
                  Container(width: cons.maxWidth * s.tokens / total, color: sliceColors[s.label] ?? nur.muted),
                Expanded(child: Container(color: theme.colorScheme.outlineVariant)),
              ]);
            }),
          ),
        ),
        const SizedBox(height: 14),
        for (final s in slices) _LegendRow(color: sliceColors[s.label] ?? nur.muted, label: s.label, tokens: s.tokens, window: b.contextWindow),
        _LegendRow(color: theme.colorScheme.outlineVariant, label: 'Free', tokens: free, window: b.contextWindow),
        if (info.hasSummary || info.excludedIds.isNotEmpty || info.droppedForSpace > 0 || (info.reportedPromptTokens ?? 0) > 0) ...[
          const SizedBox(height: 10),
          if (info.hasSummary)
            _Note(NurIcons.compress, '${info.compactedIds.length} earlier messages are summarised (still visible in the chat).'),
          if (!info.hasSummary && info.excludedIds.isNotEmpty)
            _Note(NurIcons.reset, '${info.excludedIds.length} messages before the last reset are not sent.'),
          if (info.droppedForSpace > 0)
            _Note(NurIcons.warning, 'The window is full: ${info.droppedForSpace} oldest messages are left out. Compact to keep them as a summary.'),
          if ((info.reportedPromptTokens ?? 0) > 0)
            _Note(NurIcons.context, 'Last request reported by the model: ${_grouped(info.reportedPromptTokens!)} prompt tokens.'),
        ],
        if (info.lastError != null) _Note(NurIcons.error, 'Last compaction failed: ${info.lastError}', color: NurColors.danger),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: hasChat && !busy ? _compact : null,
              icon: busy
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
                  : const Icon(NurIcons.compress, size: 18),
              label: Text(busy ? 'Compacting...' : 'Compact now'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasChat && !busy ? _clear : null,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(NurIcons.reset, size: 18),
              label: const Text('Clear context'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: nur.hover, borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-compact'),
              subtitle: Text('Summarise older messages when the context passes ${(thr * 100).round()}%', style: TextStyle(color: nur.muted, fontSize: 13)),
              value: auto,
              onChanged: (v) => ref.read(dbProvider).setSetting(IntelKeys.autoCompact, '$v'),
            ),
            if (auto)
              Slider(
                value: thr,
                min: 0.5,
                max: 0.95,
                divisions: 9,
                label: '${(thr * 100).round()}%',
                onChanged: (v) => setState(() => _threshold = v),
                onChangeEnd: (v) async {
                  await ref.read(dbProvider).setSetting(IntelKeys.autoCompactThreshold, v.toStringAsFixed(2));
                  if (mounted) setState(() => _threshold = null);
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.tokens, required this.window});
  final Color color;
  final String label;
  final int tokens;
  final int window;
  @override
  Widget build(BuildContext context) {
    final muted = context.nur.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(_grouped(tokens), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        SizedBox(
          width: 52,
          child: Text(window <= 0 ? '' : '${(tokens / window * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.end, style: TextStyle(color: muted, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.tooltip});
  final String text;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, color: context.nur.muted)),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nur.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: c, fontSize: 13))),
      ]),
    );
  }
}

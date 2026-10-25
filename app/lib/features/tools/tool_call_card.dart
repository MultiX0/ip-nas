// ChatGPT-style collapsible tool row: "Used docker_list" with spinner while running, arguments, result preview.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/nur_theme.dart';
import '../../core/utils/text_dir.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import 'builtin_tools.dart';

/// Collapsible card showing one tool call (name, arguments, status, result).
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.name, required this.argumentsJson, this.resultJson, this.running = false});
  final String name;
  final String argumentsJson;
  final String? resultJson;
  final bool running;
  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _Parsed {
  final String args;
  final String result; // shortened for display
  final String fullResult;
  final bool isError;
  final String? headline;
  const _Parsed(this.args, this.result, this.fullResult, this.isError, this.headline);
}

const _previewMax = 4000;

_Parsed _parse(String name, String argsJson, String? resultJson) {
  String args;
  String? headline;
  try {
    final a = jsonDecode(argsJson.isEmpty ? '{}' : argsJson);
    args = a is Map && a.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(a);
    if (a is Map) {
      headline = (a['query'] ?? a['command'] ?? a['url'] ?? a['task'] ?? a['name'] ?? a['content'])?.toString();
      if (name == 'docker_action' && a['action'] != null) headline = '${a['action']} ${a['name'] ?? ''}';
    }
  } catch (_) {
    args = argsJson;
  }
  var result = '';
  var isError = false;
  final raw = resultJson;
  if (raw != null && raw.isNotEmpty) {
    try {
      final r = jsonDecode(raw);
      if (r is Map && r.containsKey('content')) {
        result = (r['content'] ?? '').toString();
        isError = r['isError'] == true;
      } else {
        result = r is String ? r : const JsonEncoder.withIndent('  ').convert(r);
      }
    } catch (_) {
      result = raw;
    }
  }
  final full = result;
  if (result.length > _previewMax) result = '${result.substring(0, _previewMax)}\n...';
  if (headline != null && headline.length > 80) headline = '${headline.substring(0, 80)}...';
  return _Parsed(args, result, full, isError, headline);
}

String toolTitle(String name) {
  for (final t in builtinTools) {
    if (t.name == name) return t.title;
  }
  if (name.startsWith('mcp__')) {
    final parts = name.split('__');
    if (parts.length >= 3) return '${parts.sublist(2).join('__')} · ${parts[1]}';
  }
  return name;
}

IconData _icon(String name) => switch (name) {
      'web_search' => NurIcons.webSearch,
      'fetch_url' => NurIcons.link,
      'nas_system_status' => NurIcons.health,
      'docker_list' || 'docker_action' || 'docker_logs' => NurIcons.container,
      'run_command' => NurIcons.terminal,
      'memory_save' || 'memory_search' || 'memory_forget' => NurIcons.memory,
      'load_skill' => NurIcons.skills,
      'nas_agent' => NurIcons.agent,
      _ when name.startsWith('mcp__') => NurIcons.mcp,
      _ => NurIcons.tools,
    };

class _ToolCallCardState extends State<ToolCallCard> {
  bool _open = false;
  late _Parsed _p;

  @override
  void initState() {
    super.initState();
    _p = _parse(widget.name, widget.argumentsJson, widget.resultJson);
  }

  @override
  void didUpdateWidget(ToolCallCard old) {
    super.didUpdateWidget(old);
    if (old.argumentsJson != widget.argumentsJson || old.resultJson != widget.resultJson || old.name != widget.name) {
      _p = _parse(widget.name, widget.argumentsJson, widget.resultJson);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final theme = Theme.of(context);
    final title = toolTitle(widget.name);
    final failed = !widget.running && _p.isError;
    final verb = widget.running ? 'Using' : (failed ? 'Failed' : 'Used');
    final color = failed ? NurColors.danger : nur.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 16,
                height: 16,
                child: widget.running
                    ? CircularProgressIndicator(strokeWidth: 1.8, color: nur.muted)
                    : Icon(failed ? NurIcons.error : _icon(widget.name), size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$verb ', style: TextStyle(color: color)),
                    TextSpan(text: title, style: TextStyle(color: failed ? color : theme.colorScheme.onSurface, fontWeight: FontWeight.w500)),
                    if (_p.headline != null && _p.headline!.isNotEmpty) TextSpan(text: '  ${_p.headline}', style: TextStyle(color: nur.subtle)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _open ? (Directionality.of(context) == TextDirection.rtl ? -0.25 : 0.25) : 0,
                duration: NurMotion.base,
                curve: NurMotion.curve,
                child: Icon(NurIcons.chevron, size: 16, color: nur.subtle),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4, bottom: 6),
                  decoration: BoxDecoration(
                    color: nur.codeBg,
                    borderRadius: BorderRadius.circular(NurRadius.field),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(widget.name, style: TextStyle(fontSize: 12, color: nur.muted, fontFamily: 'monospace'))),
                      if (_p.result.isNotEmpty) CopyButton(text: () => _p.fullResult, size: 14, box: 26, tooltip: 'Copy result'),
                    ]),
                    if (_p.args.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _Label('Arguments'),
                      _Mono(_p.args),
                    ],
                    const SizedBox(height: 8),
                    _Label(widget.running ? 'Running...' : (failed ? 'Error' : 'Result')),
                    if (!widget.running) _Mono(_p.result.isEmpty ? '(no output)' : _p.result, color: failed ? NurColors.danger : null),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: context.nur.subtle)),
      );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text, {this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          child: Directionality(
            textDirection: textDirOf(text),
            child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45, color: color)),
          ),
        ),
      );
}

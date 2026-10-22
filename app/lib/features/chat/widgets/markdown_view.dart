// Markdown renderer for assistant replies. While streaming, the settled prefix (completed blocks) is built once
// and cached behind a RepaintBoundary; only the live tail block is rebuilt per frame.
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/nur_theme.dart';

class NurMarkdown extends StatefulWidget {
  const NurMarkdown({super.key, required this.text, this.streaming = false, required this.direction});
  final String text;
  final bool streaming;
  final TextDirection direction;

  @override
  State<NurMarkdown> createState() => _NurMarkdownState();
}

class _NurMarkdownState extends State<NurMarkdown> {
  String? _wholeText;
  Widget? _whole;
  String? _headText;
  Widget? _head;
  GptMarkdownStyleSheet? _sheet;
  TextStyle? _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final nur = context.nur;
    _style = theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.55, color: theme.colorScheme.onSurface);
    _sheet = GptMarkdownStyleSheet(
      codeBlock: CodeBlockStyle(
        backgroundColor: nur.codeBg,
        borderColor: theme.colorScheme.outlineVariant,
        borderRadius: const Radius.circular(14),
        showLanguageLabel: true,
        showCopyButton: true,
        highlightWhileStreaming: false,
        fontSize: 13.5,
        languageStyle: TextStyle(fontSize: 12, color: nur.muted),
      ),
      inlineCode: InlineCodeStyle(backgroundColor: nur.hover, borderRadius: const Radius.circular(6)),
      table: TableStyle(
        borderColor: theme.colorScheme.outlineVariant,
        borderRadius: const Radius.circular(12),
        headerBackground: nur.hover,
        cellPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
    // Theme changed: drop caches.
    _whole = null;
    _head = null;
  }

  void _openLink(String url, String title) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
  }

  Widget _md(String s) => GptMarkdown(
        s,
        style: _style,
        textDirection: widget.direction,
        styleSheet: _sheet,
        onLinkTap: _openLink,
        useDollarSignsForLatex: true,
      );

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (!widget.streaming) {
      if (_whole == null || _wholeText != text) {
        _wholeText = text;
        _whole = RepaintBoundary(child: _md(text));
      }
      return _whole!;
    }
    final split = settledSplitOffset(text);
    final head = text.substring(0, split);
    final tail = text.substring(split);
    if (_head == null || _headText != head) {
      _headText = head;
      _head = head.trim().isEmpty ? const SizedBox.shrink() : RepaintBoundary(child: _md(head));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_head!, if (tail.trim().isNotEmpty) _md(tail.trimLeft())],
    );
  }
}

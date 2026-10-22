// ChatGPT-style floating composer: auto-growing input, attachments, reasoning pill, tools toggle,
// context ring, voice message / voice call / send / stop buttons.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/contracts/chat_engine.dart';
import '../../../core/contracts/llm.dart';
import '../../../core/layout/desktop.dart';
import '../../../core/providers.dart';
import '../../../core/theme/nur_theme.dart';
import '../../../core/utils/text_dir.dart';
import '../../../core/widgets/nur_icons.dart';
import '../../../core/widgets/nur_ui.dart';
import '../../context/context_ring.dart';
import '../../providers/capabilities.dart';
import '../../voice/voice_buttons.dart';
import 'common.dart';

class _FileAttachment {
  final String name;
  final String text;
  const _FileAttachment(this.name, this.text);
}

const _textExts = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml', 'xml', 'html', 'htm', 'css', 'js', 'ts', 'tsx', 'jsx', 'dart', 'py', 'java',
  'kt', 'swift', 'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'bash', 'ps1', 'bat', 'sql', 'toml', 'ini', 'cfg', 'conf', 'log',
  'env', 'dockerfile', 'gradle', 'properties', 'srt', 'vtt', 'tex', 'lua', 'r', 'scala', 'vue', 'svelte',
};
const _imageExts = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp', 'gif': 'image/gif'};
const _maxFileChars = 200000;

String? _decodeText(Uint8List bytes) {
  try {
    final s = utf8.decode(bytes);
    if (s.contains('\u0000')) return null;
    return s;
  } catch (_) {
    return null;
  }
}

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.chatId,
    required this.caps,
    required this.hasModel,
    required this.busy,
    required this.reasoning,
    required this.toolsOn,
    required this.onReasoning,
    required this.onTools,
    required this.onSend,
    required this.onStop,
    this.showContextRing = true,
  });

  final String? chatId;
  final ModelCapabilities? caps;
  final bool hasModel;
  final bool busy;
  final ReasoningLevel reasoning;
  final bool toolsOn;
  final ValueChanged<ReasoningLevel> onReasoning;
  final ValueChanged<bool> onTools;
  final Future<bool> Function(UserInput input) onSend;
  final VoidCallback onStop;

  /// False on desktop, where the ring lives in the top bar.
  final bool showContextRing;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _images = <LlmImage>[];
  final _files = <_FileAttachment>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
    _focus.addListener(_onFocusVisual);
    if (isDesktopPlatform) HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Focusing the box warms the model: llama.cpp reads the prompt prefix while the user types.
  void _onFocus() {
    if (!_focus.hasFocus || !widget.hasModel) return;
    unawaited(ProviderScope.containerOf(context, listen: false).read(chatEngineProvider).prewarm(widget.chatId));
  }

  /// Repaints the composer border / shadow when focus changes.
  void _onFocusVisual() {
    if (mounted) setState(() {});
  }

  bool _hadText = false;
  void _onText() {
    final has = _text.text.trim().isNotEmpty;
    if (has != _hadText) setState(() => _hadText = has);
  }

  @override
  void dispose() {
    if (isDesktopPlatform) HardwareKeyboard.instance.removeHandler(_onKey);
    _text.removeListener(_onText);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend => (_text.text.trim().isNotEmpty || _images.isNotEmpty || _files.isNotEmpty) && !_sending;
  bool get _vision => widget.caps?.vision ?? false;
  bool get _desktop => isDesktopPlatform;

  Future<void> _send({String? override, String? audioPath}) async {
    if (widget.busy || _sending) return;
    if (!widget.hasModel) {
      showSnack(context, 'Add a model first (Settings > Models & providers).');
      return;
    }
    var text = override ?? _text.text.trim();
    if (text.isEmpty && _images.isEmpty && _files.isEmpty) return;
    for (final f in _files) {
      text += '\n\n<file name="${f.name.replaceAll('"', '')}">\n${f.text}\n</file>';
    }
    final input = UserInput(text, images: _vision ? List.of(_images) : const [], audioPath: audioPath);
    setState(() => _sending = true);
    final ok = await widget.onSend(input);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        if (override == null) _text.clear();
        _images.clear();
        _files.clear();
      }
    });
  }


  Future<void> _pickImages({required bool camera}) async {
    try {
      final picker = ImagePicker();
      final picked = camera
          ? [?await picker.pickImage(source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 85)]
          : await picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 85, limit: 8);
      for (final x in picked) {
        final bytes = await x.readAsBytes();
        final ext = x.name.split('.').last.toLowerCase();
        _images.add(LlmImage(bytes, _imageExts[ext] ?? x.mimeType ?? 'image/jpeg'));
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, camera ? 'Could not open the camera: ${errorText(e)}' : 'Could not open photos: ${errorText(e)}');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      for (final f in files) {
        final ext = (f.extension ?? f.name.split('.').last).toLowerCase();
        await _addFile(f.name, ext, await f.xFile.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, 'Could not attach the file: ${errorText(e)}');
    }
  }

  /// Adds one image or text file (shared by the file picker, drag & drop and paste).
  Future<void> _addFile(String name, String ext, Uint8List bytes) async {
    if (_imageExts.containsKey(ext)) {
      if (!_vision) {
        if (mounted) showSnack(context, 'The current model cannot see images.');
        return;
      }
      _images.add(LlmImage(bytes, _imageExts[ext]!));
      return;
    }
    final text = bytes.length > 64 * 1024 ? await compute(_decodeText, bytes) : _decodeText(bytes);
    if (text == null || (!_textExts.contains(ext) && text.isEmpty)) {
      if (mounted) showSnack(context, '$name: only text and code files can be attached for now.');
      return;
    }
    _files.add(_FileAttachment(name, text.length > _maxFileChars ? '${text.substring(0, _maxFileChars)}\n...(truncated)' : text));
  }

  /// Attaches files by path (desktop drag & drop, files copied in Explorer).
  Future<void> addPaths(List<String> paths) async {
    try {
      for (final path in paths) {
        final f = File(path);
        if (!await f.exists()) continue; // folders and vanished files
        final name = path.split(RegExp(r'[\\/]')).last;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        await _addFile(name, ext, await f.readAsBytes());
      }
      if (mounted) {
        setState(() {});
        _focus.requestFocus();
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not attach the file: ${errorText(e)}');
    }
  }

  // Ctrl+V: text pastes normally; an image or files on the clipboard (and no text) are attached.
  bool _onKey(KeyEvent e) {
    final kb = HardwareKeyboard.instance;
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyV && (kb.isControlPressed || kb.isMetaPressed) && _focus.hasFocus) {
      unawaited(_pasteAttachments());
    }
    return false;
  }

  Future<void> _pasteAttachments() async {
    try {
      if (await Clipboard.hasStrings()) return;
      final files = await DesktopClipboard.files();
      if (files.isNotEmpty) {
        await addPaths(files);
        return;
      }
      final img = await DesktopClipboard.image();
      if (img == null || !mounted) return;
      if (!_vision) {
        showSnack(context, 'The current model cannot see images.');
        return;
      }
      final png = await _normalizeImage(img);
      if (png == null || !mounted) return;
      setState(() => _images.add(LlmImage(png, 'image/png')));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not paste the image: ${errorText(e)}');
    }
  }

  /// Decodes clipboard image bytes (PNG/BMP) off the UI thread and returns a PNG of at most 2048 px.
  static Future<Uint8List?> _normalizeImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    try {
      final w = desc.width, h = desc.height;
      final isPng = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      if (isPng && w <= 2048 && h <= 2048) return bytes;
      final scale = math.min(1.0, 2048 / math.max(w, h));
      final codec = await desc.instantiateCodec(targetWidth: math.max(1, (w * scale).round()), targetHeight: math.max(1, (h * scale).round()));
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      return data?.buffer.asUint8List();
    } finally {
      desc.dispose();
      buffer.dispose();
    }
  }

  /// "+" button: anchored menu on desktop, bottom sheet on phones.
  Future<void> _attach(BuildContext anchor) async {
    if (!isDesktopLayout(context)) {
      _attachSheet();
      return;
    }
    final v = await showMenuBelow<String>(anchor, [
      menuRow('images', NurIcons.image, _vision ? 'Add images' : 'Add images (model has no vision)', enabled: _vision),
      menuRow('files', NurIcons.attach, 'Add files'),
    ]);
    if (!mounted) return;
    if (v == 'images') unawaited(_pickImages(camera: false));
    if (v == 'files') unawaited(_pickFiles());
  }

  void _attachSheet() {
    final cameraOk = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final noVision = 'The current model cannot see images';
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _AttachTile(
                icon: NurIcons.camera,
                label: 'Camera',
                disabledReason: !_vision ? noVision : (!cameraOk ? 'Camera is not available on this device' : null),
                onTap: () {
                  Navigator.pop(c);
                  _pickImages(camera: true);
                },
              ),
              const SizedBox(width: 10),
              _AttachTile(
                icon: NurIcons.image,
                label: 'Photos',
                disabledReason: !_vision ? noVision : null,
                onTap: () {
                  Navigator.pop(c);
                  _pickImages(camera: false);
                },
              ),
              const SizedBox(width: 10),
              _AttachTile(
                icon: NurIcons.attach,
                label: 'Files',
                onTap: () {
                  Navigator.pop(c);
                  _pickFiles();
                },
              ),
            ]),
            if (!_vision)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Images need a model with vision (eye badge). Pick one from the model menu to attach photos.',
                    style: TextStyle(color: context.nur.muted, fontSize: 13)),
              ),
          ]),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nur = context.nur;
    final caps = widget.caps;
    final levels = caps == null ? const <ReasoningLevel>[] : pillLevels(caps);
    final hasText = _text.text.trim().isNotEmpty || _images.isNotEmpty || _files.isNotEmpty;

    // One round button that swaps between voice call, send and stop (ChatGPT style).
    Widget action;
    if (widget.busy) {
      action = _RoundButton(key: const ValueKey('stop'), stop: true, tooltip: _desktop ? 'Stop (Esc)' : 'Stop', onTap: widget.onStop);
    } else if (hasText) {
      action = _RoundButton(key: const ValueKey('send'), icon: NurIcons.send, tooltip: _desktop ? 'Send (Enter)' : 'Send', onTap: _canSend ? () => _send() : null);
    } else {
      action = KeyedSubtree(key: const ValueKey('call'), child: VoiceCallButton(chatId: widget.chatId));
    }
    action = AnimatedSwitcher(
      duration: NurMotion.base,
      switchInCurve: NurMotion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
      child: action,
    );

    final field = TextField(
      controller: _text,
      focusNode: _focus,
      minLines: 1,
      maxLines: 8,
      textDirection: textDirOf(_text.text),
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 16, height: 1.4),
      decoration: InputDecoration(
        hintText: _desktop ? 'Message Nur (Shift+Enter for a new line)' : 'Message Nur',
        hintStyle: TextStyle(color: nur.subtle),
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      ),
    );

    final dark = theme.brightness == Brightness.dark;
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: NurMotion.base,
      curve: NurMotion.curve,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      decoration: BoxDecoration(
        color: nur.composer,
        borderRadius: BorderRadius.circular(NurRadius.composer),
        border: Border.all(color: focused ? (dark ? NurColors.g700 : NurColors.g300) : nur.composerBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : (focused ? 0.09 : 0.06)), blurRadius: focused ? 24 : 16, offset: const Offset(0, 6)),
          if (!dark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_images.isNotEmpty || _files.isNotEmpty)
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              children: [
                for (var i = 0; i < _images.length; i++)
                  _Removable(
                    key: ObjectKey(_images[i]),
                    onRemove: () => setState(() => _images.removeAt(i)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_images[i].bytes, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192),
                    ),
                  ),
                for (var i = 0; i < _files.length; i++)
                  _Removable(
                    key: ObjectKey(_files[i]),
                    onRemove: () => setState(() => _files.removeAt(i)),
                    child: Container(
                      height: 64,
                      width: 150,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: nur.composer,
                        borderRadius: BorderRadius.circular(NurRadius.field),
                        border: Border.all(color: nur.composerBorder),
                      ),
                      child: Row(children: [
                        const IconTile(NurIcons.file, size: 34),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_files[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        _desktop
            ? CallbackShortcuts(bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () => _send(),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _send(),
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (widget.busy) widget.onStop();
                },
              }, child: field)
            : field,
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 8, 8),
          child: Row(children: [
            Builder(builder: (b) => NurIconButton(icon: NurIcons.add, size: 22, box: 36, circle: true, tooltip: 'Attach', onTap: () => _attach(b))),
            const SizedBox(width: 2),
            // Pills scroll sideways on narrow phones instead of overflowing.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (levels.isNotEmpty) _ReasoningPill(levels: levels, value: widget.reasoning, onChanged: widget.onReasoning),
                  if (caps?.tools ?? false)
                    _Pill(
                      icon: NurIcons.tools,
                      label: 'Tools',
                      active: widget.toolsOn,
                      tooltip: widget.toolsOn ? 'Tools on (NAS, web search, MCP)' : 'Tools off',
                      onTap: () => widget.onTools(!widget.toolsOn),
                    ),
                ]),
              ),
            ),
            if (widget.showContextRing) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ContextRing(chatId: widget.chatId)),
            if (!widget.busy)
              VoiceMessageButton(onTranscript: (text, audioPath) {
                if (text.trim().isEmpty) return;
                _send(override: text.trim(), audioPath: audioPath);
              }),
            const SizedBox(width: 2),
            action,
          ]),
        ),
      ]),
    );
  }
}

class _Removable extends StatelessWidget {
  const _Removable({super.key, required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => AppearIn(
        offset: 4,
        duration: NurMotion.base,
        child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Stack(clipBehavior: Clip.none, children: [
          child,
          PositionedDirectional(
            top: -6,
            end: -6,
            child: Tooltip(
              message: 'Remove',
              child: GestureDetector(
              onTap: onRemove,
              child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface, shape: BoxShape.circle),
                child: Icon(NurIcons.close, size: 12, color: Theme.of(context).colorScheme.surface),
              ),
              ),
              ),
            ),
          ),
        ]),
      ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, this.icon, required this.onTap, this.tooltip, this.stop = false});
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Draws ChatGPT's filled stop square instead of an icon.
  final bool stop;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = enabled ? s.onPrimary : s.surface;
    return NurPressable(
      onTap: onTap,
      tooltip: tooltip,
      shape: BoxShape.circle,
      color: enabled ? s.primary : s.onSurface.withValues(alpha: 0.18),
      hoverColor: s.primary.withValues(alpha: 0.82),
      pressedScale: 0.9,
      child: SizedBox.square(
        dimension: 36,
        child: Center(
          child: stop
              ? Container(width: 11, height: 11, decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2.5)))
              : Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}

/// Composer toggle pill (Think / Tools): outlined when off, soft filled when on; animates between them.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.active, required this.onTap, this.tooltip, this.trailing});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? tooltip;
  final IconData? trailing;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = active ? scheme.onSurface : nur.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: NurPressable(
        onTap: onTap,
        tooltip: tooltip,
        borderRadius: BorderRadius.circular(NurRadius.pill),
        color: active ? (dark ? NurColors.g800 : NurColors.g100) : Colors.transparent,
        border: Border.all(color: active ? (dark ? NurColors.g700 : NurColors.g200) : scheme.outlineVariant),
        pressedScale: 0.96,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: NurMotion.base,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(icon, key: ValueKey(active), size: 16, color: fg),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
          if (trailing != null) ...[const SizedBox(width: 2), Icon(trailing, size: 14, color: fg)],
        ]),
      ),
    );
  }
}

class _ReasoningPill extends StatelessWidget {
  const _ReasoningPill({required this.levels, required this.value, required this.onChanged});
  final List<ReasoningLevel> levels;
  final ReasoningLevel value;
  final ValueChanged<ReasoningLevel> onChanged;

  bool get _onOff => levels.where((l) => l != ReasoningLevel.off).length == 1;

  String _name(ReasoningLevel l) {
    if (l == ReasoningLevel.off) return 'Off';
    if (_onOff) return 'On';
    return switch (l) {
      ReasoningLevel.minimal => 'Minimal',
      ReasoningLevel.low => 'Low',
      ReasoningLevel.medium => 'Medium',
      ReasoningLevel.high => 'High',
      ReasoningLevel.extra => 'Extra',
      ReasoningLevel.off => 'Off',
    };
  }

  @override
  Widget build(BuildContext context) {
    final v = levels.contains(value) ? value : levels.last;
    final active = v != ReasoningLevel.off;
    final label = _onOff ? (active ? 'Think' : 'Think: off') : 'Think: ${_name(v)}';
    if (levels.length == 2 && _onOff) {
      return _Pill(
        icon: NurIcons.think,
        label: label,
        active: active,
        tooltip: 'Reasoning',
        onTap: () => onChanged(active ? ReasoningLevel.off : levels.last),
      );
    }
    if (levels.length == 1) {
      return _Pill(icon: NurIcons.think, label: 'Think', active: true, tooltip: 'This model always reasons', onTap: () {});
    }
    return PopupMenuButton<ReasoningLevel>(
      tooltip: 'Reasoning effort',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final l in levels)
          PopupMenuItem(
            value: l,
            child: Row(children: [
              SizedBox(width: 26, child: l == v ? const Icon(NurIcons.check, size: 16) : null),
              Text(_name(l)),
            ]),
          ),
      ],
      child: IgnorePointer(child: _Pill(icon: NurIcons.think, label: label, active: active, trailing: NurIcons.chevronDown, onTap: () {})),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({required this.icon, required this.label, required this.onTap, this.disabledReason});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? disabledReason;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final enabled = disabledReason == null;
    return Expanded(
      child: Tooltip(
        message: disabledReason ?? '',
        child: Material(
          color: nur.hover,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onTap : () => showSnack(context, disabledReason!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Column(children: [Icon(icon, size: 26), const SizedBox(height: 8), Text(label, style: const TextStyle(fontWeight: FontWeight.w500))]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ChatGPT-style chat list: search, new chat, grouped history, chat actions, NAS + settings.
// [ChatListPanel] is shared by the phone drawer ([ChatDrawer]) and the desktop sidebar (features/shell/app_shell.dart).
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/desktop.dart';
import '../../../core/theme/nur_theme.dart';
import '../../../core/utils/text_dir.dart';
import '../../../core/widgets/nur_icons.dart';
import '../../../core/widgets/nur_ui.dart';
import '../../../data/db/app_db.dart' hide LlmModel;
import '../../shell/settings_dialog.dart';
import '../chat_providers.dart';
import '../data/chat_repo.dart';
import 'common.dart';

/// Phone drawer.
class ChatDrawer extends StatelessWidget {
  const ChatDrawer({super.key, this.currentChatId});
  final String? currentChatId;

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final width = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: width < 420 ? width * 0.86 : 340,
      backgroundColor: nur.sidebar,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ChatListPanel(
          currentChatId: currentChatId,
          onOpen: (route) {
            Navigator.of(context).pop();
            context.go(route);
          },
          footer: Column(mainAxisSize: MainAxisSize.min, children: [
            ChatNavTile(icon: NurIcons.nas, label: 'NAS', onTap: () {
              Navigator.of(context).pop();
              context.push('/nas');
            }),
            ChatNavTile(icon: NurIcons.settings, label: 'Settings', onTap: () {
              Navigator.of(context).pop();
              openSettings(context);
            }),
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }
}

/// Search + new chat + grouped history + per-chat actions. [desktop] switches to hover / right-click menus.
class ChatListPanel extends ConsumerStatefulWidget {
  const ChatListPanel({super.key, this.currentChatId, required this.onOpen, required this.footer, this.desktop = false, this.searchFocus, this.header});
  final String? currentChatId;

  /// Navigates to a chat route (`/` or `/chat/:id`).
  final void Function(String route) onOpen;
  final Widget footer;
  final bool desktop;
  final FocusNode? searchFocus;
  final Widget? header;

  @override
  ConsumerState<ChatListPanel> createState() => _ChatListPanelState();
}

class _ChatListPanelState extends ConsumerState<ChatListPanel> {
  final _search = TextEditingController();
  final _historyScroll = ScrollController();
  final _resultsScroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  List<(Chat, String?)> _results = const [];
  bool _archived = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _historyScroll.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final q = v.trim();
      final r = q.isEmpty ? const <(Chat, String?)>[] : await ref.read(chatRepoProvider).search(q);
      if (!mounted) return;
      setState(() {
        _query = q;
        _results = r;
      });
    });
  }

  void _clearSearch() {
    _search.clear();
    _onSearch('');
  }

  void _open(String route) => widget.onOpen(route);

  Widget _searchField() {
    final nur = context.nur;
    final field = TextField(
      controller: _search,
      focusNode: widget.searchFocus,
      onChanged: _onSearch,
      style: widget.desktop ? const TextStyle(fontSize: 14) : null,
      decoration: InputDecoration(
        hintText: widget.desktop ? 'Search chats' : 'Search',
        prefixIcon: Icon(NurIcons.search, size: widget.desktop ? 16 : 18),
        prefixIconConstraints: BoxConstraints(minWidth: widget.desktop ? 34 : 40, minHeight: 20),
        isDense: true,
        contentPadding: EdgeInsets.zero,
        fillColor: nur.hover,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.desktop ? 10 : 14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.desktop ? 10 : 14), borderSide: BorderSide.none),
        focusedBorder: widget.desktop
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline))
            : null,
        suffixIcon: _search.text.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: NurIconButton(tooltip: 'Clear search', icon: NurIcons.close, size: widget.desktop ? 14 : 16, box: 26, onTap: _clearSearch),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
      ),
    );
    if (!widget.desktop) return field;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_search.text.isNotEmpty) {
            _clearSearch();
          } else {
            widget.searchFocus?.unfocus();
          }
        },
      },
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?widget.header,
        ChatNavTile(icon: NurIcons.newChat, label: 'New chat', shortcut: 'Ctrl+N', desktop: true, onTap: () => _open('/')),
        Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 4), child: SizedBox(height: 36, child: _searchField())),
        if (_archived) ChatNavTile(icon: NurIcons.back, label: 'Back to chats', desktop: true, onTap: () => setState(() => _archived = false)),
        const SizedBox(height: 2),
        Expanded(child: _query.isNotEmpty ? _searchResults() : _history()),
        const Divider(),
        widget.footer,
      ]);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Row(children: [
          Expanded(child: SizedBox(height: 42, child: _searchField())),
          const SizedBox(width: 4),
          NurIconButton(tooltip: 'New chat', icon: NurIcons.newChat, size: 22, box: 42, color: Theme.of(context).colorScheme.onSurface, onTap: () => _open('/')),
        ]),
      ),
      ChatNavTile(icon: NurIcons.newChat, label: 'New chat', onTap: () => _open('/')),
      if (_archived) ChatNavTile(icon: NurIcons.back, label: 'Back to chats', onTap: () => setState(() => _archived = false)),
      const SizedBox(height: 4),
      Expanded(child: _query.isNotEmpty ? _searchResults() : _history()),
      const Divider(),
      widget.footer,
    ]);
  }

  Widget _scrollable(ScrollController controller, int count, IndexedWidgetBuilder builder) {
    final list = ListView.builder(controller: controller, itemCount: count, itemBuilder: builder, padding: widget.desktop ? const EdgeInsets.only(bottom: 8) : null);
    if (!widget.desktop) return list;
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false), child: list),
    );
  }

  Widget _searchResults() {
    if (_results.isEmpty) {
      return NurEmptyState(icon: NurIcons.search, title: 'No chats found', body: 'Try other words or check the spelling.', compact: true);
    }
    return _scrollable(_resultsScroll, _results.length, (c, i) {
      final (chat, snip) = _results[i];
      return _ChatTile(
        chat: chat,
        selected: chat.id == widget.currentChatId,
        snippet: snip,
        desktop: widget.desktop,
        onTap: () => _open('/chat/${chat.id}'),
        onMenuAt: widget.desktop ? (pos) => _menuAt(chat, pos) : null,
        onMenuBelow: widget.desktop ? (anchor) => _menuBelow(chat, anchor) : null,
      );
    });
  }

  Widget _history() {
    final chats = ref.watch(chatListProvider(_archived)).value;
    if (chats == null) return SkeletonList(count: 9, leading: false, dense: true, padding: EdgeInsets.fromLTRB(widget.desktop ? 14 : 18, 16, 14, 8));
    final rows = <Widget>[];
    if (chats.isEmpty) {
      return NurEmptyState(
        compact: true,
        icon: _archived ? NurIcons.archive : NurIcons.chat,
        title: _archived ? 'No archived chats' : 'No chats yet',
        body: _archived ? 'Chats you archive are kept here.' : 'Your conversations will appear here.',
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String group(Chat c) {
      if (c.pinned && !_archived) return 'Pinned';
      final d = c.updatedAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      if (diff <= 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      if (diff <= 7) return 'Previous 7 days';
      if (diff <= 30) return 'Previous 30 days';
      return 'Older';
    }

    String? last;
    for (final c in chats) {
      final g = group(c);
      if (g != last) {
        rows.add(Padding(
          padding: widget.desktop ? const EdgeInsets.fromLTRB(20, 14, 16, 4) : const EdgeInsets.fromLTRB(20, 14, 16, 6),
          child: Text(g, style: TextStyle(fontSize: widget.desktop ? 11.5 : 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: context.nur.subtle)),
        ));
        last = g;
      }
      rows.add(_ChatTile(
        chat: c,
        selected: c.id == widget.currentChatId,
        desktop: widget.desktop,
        onTap: () => _open('/chat/${c.id}'),
        onMenu: () => _menu(c),
        onMenuAt: widget.desktop ? (pos) => _menuAt(c, pos) : null,
        onMenuBelow: widget.desktop ? (anchor) => _menuBelow(c, anchor) : null,
      ));
    }
    if (!_archived) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ChatNavTile(icon: NurIcons.archive, label: 'Archived chats', desktop: widget.desktop, onTap: () => setState(() => _archived = true)),
      ));
    }
    return _scrollable(_historyScroll, rows.length, (_, i) => rows[i]);
  }


  List<PopupMenuEntry<String>> _menuItems(Chat c) => [
        menuRow('rename', NurIcons.rename, 'Rename'),
        menuRow('pin', c.pinned ? NurIcons.unpin : NurIcons.pin, c.pinned ? 'Unpin' : 'Pin'),
        menuRow('archive', c.archived ? NurIcons.unarchive : NurIcons.archive, c.archived ? 'Unarchive' : 'Archive'),
        menuRow('export', NurIcons.export, 'Export as Markdown'),
        const PopupMenuDivider(height: 8),
        menuRow('delete', NurIcons.delete, 'Delete', danger: true),
      ];

  Future<void> _menuAt(Chat c, Offset globalPosition) async {
    final action = await showContextMenuAt<String>(context, globalPosition, _menuItems(c));
    if (action != null && mounted) await _handle(c, action);
  }

  Future<void> _menuBelow(Chat c, BuildContext anchor) async {
    final action = await showMenuBelow<String>(anchor, _menuItems(c));
    if (action != null && mounted) await _handle(c, action);
  }

  Future<void> _menu(Chat c) async {
    if (widget.desktop) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          ListTile(leading: const Icon(NurIcons.rename), title: const Text('Rename'), onTap: () => Navigator.pop(s, 'rename')),
          ListTile(leading: Icon(c.pinned ? NurIcons.unpin : NurIcons.pin), title: Text(c.pinned ? 'Unpin' : 'Pin'), onTap: () => Navigator.pop(s, 'pin')),
          ListTile(
            leading: Icon(c.archived ? NurIcons.unarchive : NurIcons.archive),
            title: Text(c.archived ? 'Unarchive' : 'Archive'),
            onTap: () => Navigator.pop(s, 'archive'),
          ),
          ListTile(leading: const Icon(NurIcons.export), title: const Text('Export as Markdown'), onTap: () => Navigator.pop(s, 'export')),
          ListTile(
            leading: const Icon(NurIcons.delete, color: NurColors.danger),
            title: const Text('Delete', style: TextStyle(color: NurColors.danger)),
            onTap: () => Navigator.pop(s, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    await _handle(c, action);
  }

  Future<void> _handle(Chat c, String action) async {
    final repo = ref.read(chatRepoProvider);
    switch (action) {
      case 'rename':
        final name = await _ask(context, 'Rename chat', c.title);
        if (name != null && name.trim().isNotEmpty && mounted) await guard(context, () => repo.rename(c.id, name.trim()));
      case 'pin':
        await guard(context, () => repo.setPinned(c.id, !c.pinned));
      case 'archive':
        await guard(context, () => repo.setArchived(c.id, !c.archived));
        if (c.id == widget.currentChatId && !c.archived && mounted) _open('/');
      case 'export':
        await _export(c, repo);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Delete chat?'),
            content: Text('"${c.title}" will be deleted permanently.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NurColors.danger, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          await guard(context, () => repo.deleteChat(c.id));
          if (c.id == widget.currentChatId && mounted) _open('/');
        }
    }
  }

  Future<void> _export(Chat c, ChatRepo repo) async {
    try {
      final md = await repo.exportMarkdown(c.id);
      final safe = c.title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
      final uri = await FilePicker.saveFile(
        fileName: '${safe.isEmpty ? 'chat' : safe}.md',
        bytes: Uint8List.fromList(utf8.encode(md)),
        mimeType: 'text/markdown',
        dialogTitle: 'Export chat',
      );
      if (!mounted) return;
      if (uri != null) {
        showSnack(context, 'Chat exported');
      }
    } catch (e) {
      // No save dialog on this platform (or it failed): copy the Markdown instead.
      try {
        await Clipboard.setData(ClipboardData(text: await repo.exportMarkdown(c.id)));
        if (mounted) showSnack(context, 'Could not save a file, the Markdown was copied instead.');
      } catch (_) {
        if (mounted) showSnack(context, 'Export failed: ${errorText(e)}');
      }
    }
  }
}

Future<String?> _ask(BuildContext context, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(() => WidgetsBinding.instance.addPostFrameCallback((_) => ctl.dispose()));
}

/// Navigation row of the chat list (New chat, Archived, NAS, Settings...).
class ChatNavTile extends StatefulWidget {
  const ChatNavTile({super.key, required this.icon, required this.label, required this.onTap, this.desktop = false, this.shortcut, this.selected = false, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool desktop;
  final String? shortcut;
  final bool selected;
  final Widget? trailing;
  @override
  State<ChatNavTile> createState() => _ChatNavTileState();
}

class _ChatNavTileState extends State<ChatNavTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final desktop = widget.desktop;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: desktop ? 1 : 1.5),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: NurPressable(
          onTap: widget.onTap,
          selected: widget.selected,
          borderRadius: BorderRadius.circular(desktop ? NurRadius.control : NurRadius.row),
          pressedScale: 0.985,
          padding: EdgeInsets.symmetric(horizontal: desktop ? 10 : 12, vertical: desktop ? 8 : 11),
          child: Row(children: [
            Icon(widget.icon, size: desktop ? 18 : 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9)),
            SizedBox(width: desktop ? 11 : 14),
            Expanded(
              child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: desktop ? 14 : 15, fontWeight: FontWeight.w500)),
            ),
            if (widget.shortcut != null)
              AnimatedOpacity(opacity: _hover ? 1 : 0, duration: NurMotion.fast, child: KeyHint(widget.shortcut!)),
            ?widget.trailing,
          ]),
        ),
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  const _ChatTile({required this.chat, required this.selected, required this.onTap, this.onMenu, this.snippet, this.desktop = false, this.onMenuAt, this.onMenuBelow});
  final Chat chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final String? snippet;
  final bool desktop;
  final Future<void> Function(Offset globalPosition)? onMenuAt;
  final Future<void> Function(BuildContext anchor)? onMenuBelow;
  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  bool _hover = false;
  bool _menuOpen = false;

  Future<void> _withMenu(Future<void> Function() f) async {
    setState(() => _menuOpen = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final chat = widget.chat;
    final snippet = widget.snippet;
    final desktop = widget.desktop;
    final showMore = desktop && (_hover || _menuOpen);
    final title = Text(
      chat.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: textDirOf(chat.title),
      style: TextStyle(fontSize: desktop ? 14 : 15, fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400),
    );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      title,
      if (snippet != null && snippet.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: textDirOf(snippet), style: TextStyle(fontSize: desktop ? 12 : 12.5, color: nur.muted)),
        ),
    ]);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: desktop ? 0.5 : 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: NurPressable(
          onTap: widget.onTap,
          onLongPress: desktop ? null : widget.onMenu,
          onSecondaryTapUp: desktop
              ? (widget.onMenuAt == null ? null : (d) => _withMenu(() => widget.onMenuAt!(d.globalPosition)))
              : (widget.onMenu == null ? null : (_) => widget.onMenu!()),
          selected: widget.selected,
          color: _menuOpen ? nur.hover.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(desktop ? NurRadius.control : NurRadius.row),
          pressedScale: 0.99,
          padding: desktop ? const EdgeInsetsDirectional.fromSTEB(10, 7, 4, 7) : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: body),
            if (chat.pinned && !showMore)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(NurIcons.pin, size: 13, color: nur.subtle)),
            if (desktop)
              AnimatedSize(
                duration: NurMotion.fast,
                child: SizedBox(
                  width: showMore ? 28 : 0,
                  height: 24,
                  child: showMore && widget.onMenuBelow != null
                      ? Builder(
                          builder: (b) => SmallIconButton(
                            icon: NurIcons.more,
                            tooltip: 'More',
                            size: 16,
                            padding: 4,
                            onTap: () => _withMenu(() => widget.onMenuBelow!(b)),
                          ),
                        )
                      : null,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

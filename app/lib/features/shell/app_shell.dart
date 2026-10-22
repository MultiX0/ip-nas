// Desktop shell: a collapsible sidebar that stays mounted next to the main area, global keyboard shortcuts and
// file drop on the whole window. On narrow widths it is a pass-through and the phone UI is used.
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/desktop.dart';
import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_logo.dart';
import '../../core/widgets/nur_ui.dart';
import '../chat/widgets/chat_drawer.dart';
import '../nas/nas_service.dart';
import 'settings_dialog.dart';

const _sidebarWidth = 260.0;
const _railWidth = 60.0;

/// Settings key `sidebar_collapsed` ('true' | 'false').
final sidebarCollapsedProvider = StreamProvider<bool>((ref) => ref.watch(dbProvider).watchSetting('sidebar_collapsed').map((v) => v == 'true'));

/// NAS reachability for the sidebar chip: null = no NAS paired. Pings `/api/v1/info` every 30 s.
final nasOnlineProvider = StreamProvider.autoDispose<bool?>((ref) async* {
  final client = await ref.watch(activeNasProvider.future);
  if (client == null) {
    yield null;
    return;
  }
  while (true) {
    try {
      await client.info();
      yield true;
    } catch (_) {
      yield false;
    }
    await Future<void>.delayed(const Duration(seconds: 30));
  }
});

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// Current path (e.g. `/chat/abc`), used to highlight the open chat.
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _childKey = GlobalKey(debugLabel: 'shell-child');
  final _searchFocus = FocusNode(debugLabel: 'sidebar-search');
  bool? _collapsedLocal;
  bool _dragging = false;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _collapsed => _collapsedLocal ?? ref.read(sidebarCollapsedProvider).value ?? false;

  void _toggle() {
    final v = !_collapsed;
    setState(() => _collapsedLocal = v);
    unawaited(ref.read(dbProvider).setSetting('sidebar_collapsed', '$v'));
  }

  void _focusSearch() {
    if (_collapsed) _toggle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _newChat() => context.go('/');

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (!isDesktopLayout(context)) return child;
    final stored = ref.watch(sidebarCollapsedProvider).value;
    final collapsed = _collapsedLocal ?? stored ?? false;
    final loc = widget.location;
    final chatId = loc.startsWith('/chat/') ? Uri.decodeComponent(loc.substring(6)) : null;
    final nur = context.nur;
    final scheme = Theme.of(context).colorScheme;

    final sidebar = AnimatedContainer(
      duration: NurMotion.slow,
      curve: NurMotion.curve,
      width: collapsed ? _railWidth : _sidebarWidth,
      decoration: BoxDecoration(
        color: nur.sidebar,
        border: BorderDirectional(end: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.topStart,
          // Each side keeps its own width while the container animates; the two cross-fade.
          minWidth: 0,
          maxWidth: _sidebarWidth,
          child: AnimatedSwitcher(
            duration: NurMotion.base,
            switchInCurve: NurMotion.curve,
            layoutBuilder: (current, previous) => Stack(alignment: AlignmentDirectional.topStart, children: [...previous, ?current]),
            child: collapsed
                ? SizedBox(
                    key: const ValueKey('rail'),
                    width: _railWidth,
                    child: _Rail(location: loc, onToggle: _toggle, onNew: _newChat, onSearch: _focusSearch),
                  )
                : SizedBox(
                    key: const ValueKey('panel'),
                    width: _sidebarWidth,
                    child: ChatListPanel(
                      desktop: true,
                      currentChatId: chatId,
                      searchFocus: _searchFocus,
                      onOpen: (route) => context.go(route),
                      header: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 6),
                        child: Row(
                          children: [
                            const NurLogo(size: 22, withWordmark: true),
                            const Spacer(),
                            NurIconButton(tooltip: 'Close sidebar (Ctrl+Shift+S)', icon: NurIcons.sidebarClose, box: 36, onTap: _toggle),
                          ],
                        ),
                      ),
                      footer: Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _NasChip(selected: loc == '/nas'),
                            ChatNavTile(icon: NurIcons.settings, label: 'Settings', shortcut: 'Ctrl+,', desktop: true, onTap: () => openSettings(context)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );

    final main = DropTarget(
      onDragEntered: (_) {
        if (desktopFileDrop.value != null) setState(() => _dragging = true);
      },
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        final handler = desktopFileDrop.value;
        final paths = [
          for (final f in d.files)
            if (f.path.isNotEmpty) f.path,
        ];
        if (handler != null && paths.isNotEmpty) handler(paths);
      },
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: AppearIn(
                  duration: NurMotion.base,
                  offset: 0,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(NurRadius.sheet),
                      border: Border.all(color: scheme.outline, width: 1.5),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EmptyIllustration(icon: NurIcons.fileUpload, size: 120),
                          const SizedBox(height: 12),
                          const Text('Drop files to attach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Images and text or code files', style: TextStyle(color: nur.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newChat,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newChat,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): _toggle,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true): _toggle,
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => openSettings(context),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => openSettings(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: scheme.surface,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebar,
              Expanded(child: main),
            ],
          ),
        ),
      ),
    );
  }
}

/// The collapsed sidebar: icon buttons only.
class _Rail extends ConsumerWidget {
  const _Rail({required this.location, required this.onToggle, required this.onNew, required this.onSearch});
  final String location;
  final VoidCallback onToggle;
  final VoidCallback onNew;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(nasOnlineProvider);
    Widget btn(IconData icon, String tip, VoidCallback onTap, {bool selected = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: NurIconButton(tooltip: tip, icon: icon, selected: selected, box: 40, onTap: onTap),
    );
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Tooltip(
            message: 'Nur',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: NurLogo(size: 22, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          btn(NurIcons.sidebarOpen, 'Open sidebar (Ctrl+Shift+S)', onToggle),
          btn(NurIcons.newChat, 'New chat (Ctrl+N)', onNew),
          btn(NurIcons.search, 'Search chats (Ctrl+K)', onSearch),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              btn(NurIcons.nas, 'NAS · ${_nasStatus(online)}', () => context.go('/nas'), selected: location == '/nas'),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: IgnorePointer(child: _Dot(color: _nasColor(context, online))),
              ),
            ],
          ),
          btn(NurIcons.settings, 'Settings (Ctrl+,)', () => openSettings(context)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

String _nasStatus(AsyncValue<bool?> v) => switch (v) {
  AsyncData(value: true) => 'Online',
  AsyncData(value: false) => 'Offline',
  AsyncData(value: null) => 'Not connected',
  AsyncError() => 'Offline',
  _ => 'Checking...',
};

Color _nasColor(BuildContext context, AsyncValue<bool?> v) => switch (v) {
  AsyncData(value: true) => NurColors.ok,
  AsyncData(value: false) || AsyncError() => NurColors.danger,
  _ => context.nur.subtle,
};

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: context.nur.sidebar, width: 1.5),
    ),
  );
}

/// NAS status chip at the bottom of the sidebar; opens the NAS dashboard.
class _NasChip extends ConsumerWidget {
  const _NasChip({required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nur = context.nur;
    final name = ref.watch(activeNasProvider).value?.device?.name;
    final online = ref.watch(nasOnlineProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: NurPressable(
        selected: selected,
        onTap: () => context.go('/nas'),
        pressedScale: 0.985,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            const Icon(NurIcons.nas, size: 18),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name ?? 'NAS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(_nasStatus(online), style: TextStyle(fontSize: 11.5, color: nur.muted)),
                ],
              ),
            ),
            _Dot(color: _nasColor(context, online)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

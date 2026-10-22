// Main chat screen (routes `/` and `/chat/:id`): ChatGPT mobile layout on phones, ChatGPT desktop layout on wide windows.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/contracts/chat_engine.dart';
import '../../core/contracts/llm.dart';
import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_logo.dart';
import '../../core/widgets/nur_ui.dart';
import '../../core/widgets/provider_logo.dart';
import '../context/context_ring.dart';
import '../models/model_picker_sheet.dart';
import '../providers/capabilities.dart';
import '../providers/llm_registry.dart';
import '../shell/settings_dialog.dart';
import 'chat_providers.dart';
import 'data/chat_repo.dart';
import 'engine/chat_engine_provider.dart';
import 'engine/live_store.dart';
import 'widgets/approval_sheet.dart';
import 'widgets/chat_drawer.dart';
import 'widgets/common.dart';
import 'widgets/composer.dart';
import 'widgets/messages.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.chatId});
  final String? chatId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  final _composerKey = GlobalKey<ComposerState>();
  String? _pendingModelRef;
  ChatSettings _newSettings = const ChatSettings();
  bool _stick = true;
  bool _showDown = false;
  bool _jumpQueued = false;
  int _lastItemCount = -1;
  bool _busy = false;
  ValueNotifier<LiveMessage>? _liveListened;
  late final LiveStore _live;
  late final ToolApprovalBroker _broker;

  @override
  void initState() {
    super.initState();
    _live = ref.read(liveStoreProvider);
    _broker = ref.read(toolApprovalBrokerProvider);
    _broker.register(_approve);
    _live.active.addListener(_onActiveListener);
    _onActive(init: true);
    desktopFileDrop.value = _onDrop;
    // Create the engine early (it also cleans up replies interrupted by a previous crash).
    ref.read(chatEngineImplProvider);
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) {
      _stick = true;
      _lastItemCount = -1;
      _onActive(init: true);
    }
  }

  @override
  void dispose() {
    _broker.unregister(_approve);
    if (desktopFileDrop.value == _onDrop) desktopFileDrop.value = null;
    _live.active.removeListener(_onActiveListener);
    _liveListened?.removeListener(_onLive);
    _scroll.dispose();
    super.dispose();
  }

  void _onDrop(List<String> paths) => _composerKey.currentState?.addPaths(paths);

  Future<bool> _approve(ApprovalRequest r) async {
    if (!mounted) return false;
    return showApprovalSheet(context, r);
  }


  void _onActiveListener() => _onActive();

  void _onActive({bool init = false}) {
    final id = widget.chatId;
    final busy = _live.isActive(id);
    final msgId = id == null ? null : _live.active.value[id];
    final n = msgId == null || msgId.isEmpty ? null : _live.of(msgId);
    final changed = busy != _busy || !identical(n, _liveListened);
    if (!identical(n, _liveListened)) {
      _liveListened?.removeListener(_onLive);
      _liveListened = n;
      n?.addListener(_onLive);
    }
    if (init) {
      _busy = busy;
    } else if (changed && mounted) {
      // Rebuild so the streaming message picks up its live notifier and the composer shows Stop.
      setState(() => _busy = busy);
    }
  }

  void _onLive() {
    if (_stick) _queueJump();
  }

  void _queueJump() {
    if (_jumpQueued) return;
    _jumpQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpQueued = false;
      if (!_scroll.hasClients || !_stick) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset < max - 0.5) _scroll.jumpTo(max);
    });
  }

  /// Jumps a few frames in a row so lazily-built items settle (opening a long chat).
  void _settleToBottom([int frames = 4]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !_stick) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (frames > 1) _settleToBottom(frames - 1);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is UserScrollNotification && n.direction == ScrollDirection.forward) _stick = false;
    if (n is ScrollUpdateNotification && n.dragDetails != null && (n.scrollDelta ?? 0) < 0) _stick = false;
    final after = n.metrics.extentAfter;
    if (after < 40) _stick = true;
    final show = after > 240;
    if (show != _showDown) setState(() => _showDown = show);
    return false;
  }

  Future<void> _toBottom() async {
    if (!_scroll.hasClients) return;
    _stick = true;
    await _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    _settleToBottom(3);
  }


  Future<bool> _send(UserInput input, String? modelRef, ChatSettings settings) async {
    try {
      final id = await ref.read(chatEngineImplProvider).sendFromUi(chatId: widget.chatId, input: input, modelRef: modelRef, settings: settings);
      _stick = true;
      _queueJump();
      if (widget.chatId == null && mounted) context.go('/chat/$id');
      return true;
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
      return false;
    }
  }

  Future<void> _pickModel(String? current, {BuildContext? anchor}) async {
    final ref0 = await showModelPicker(context, currentRef: current, anchor: anchor);
    if (ref0 == null || !mounted) return;
    if (widget.chatId != null) {
      await guard(context, () => ref.read(chatRepoProvider).setModel(widget.chatId!, ref0));
    } else {
      setState(() => _pendingModelRef = ref0);
    }
  }

  void _setSettings(ChatSettings s) {
    if (widget.chatId == null) {
      setState(() => _newSettings = s);
    } else {
      guard(context, () => ref.read(chatRepoProvider).setSettings(widget.chatId!, s));
    }
  }


  @override
  Widget build(BuildContext context) {
    final chatId = widget.chatId;
    final thread = chatId == null ? null : ref.watch(threadProvider(chatId));
    final data = thread?.value;
    final chat = data?.chat;
    final entriesAsync = ref.watch(modelEntriesProvider);
    final entries = entriesAsync.value;
    final defaultModel = ref.watch(defaultModelProvider).value;
    final reg = ref.read(llmRegistryProvider);

    final wantedRef = chat?.modelRef ?? _pendingModelRef;
    var entry = reg.entryByRef(wantedRef);
    if (entry == null || entry.hidden && wantedRef == null) entry = reg.entryByRef(defaultModel?.ref);
    final modelRef = entry?.ref;
    final caps = entry?.model.caps;
    final settings = chatId == null ? _newSettings : ChatSettings.parse(chat?.settingsJson);
    final wantLevel = settings.reasoning ?? entry?.overrides.defaultReasoning ?? ReasoningLevel.medium;
    final level = caps == null ? wantLevel : effectiveLevel(caps, wantLevel);
    final noModels = entries != null && entries.isEmpty;

    Widget body;
    if (chatId != null && thread != null && thread.hasValue && chat == null) {
      body = _Centered(
        icon: NurIcons.chat,
        title: 'Chat not found',
        text: 'It may have been deleted.',
        actions: [FilledButton(onPressed: () => context.go('/'), child: const Text('New chat'))],
      );
    } else if (chatId == null || (data != null && data.path.isEmpty)) {
      body = noModels ? const _NoModels() : _EmptyChat(onSuggestion: (t) => _send(UserInput(t), modelRef, settings));
    } else if (data == null) {
      body = thread?.hasError == true
          ? _Centered(icon: NurIcons.error, title: 'Could not open this chat', text: errorText(thread!.error!))
          : const SizedBox.shrink();
    } else {
      body = _messageList(chatId, data);
    }

    final desktop = isDesktopLayout(context);
    final title = entry?.model.displayName ?? (noModels ? 'No model' : 'Choose a model');
    final onNew = chatId == null && _pendingModelRef == null ? null : () => context.go('/');
    final composer = Composer(
      key: _composerKey,
      chatId: chatId,
      caps: caps,
      hasModel: entry != null,
      busy: _busy,
      reasoning: level,
      toolsOn: settings.tools,
      showContextRing: !desktop,
      onReasoning: (l) => _setSettings(settings.copyWith(reasoning: l)),
      onTools: (v) => _setSettings(settings.copyWith(tools: v)),
      onSend: (input) => _send(input, modelRef, settings),
      onStop: () {
        if (chatId != null) ref.read(chatEngineImplProvider).stop(chatId);
      },
    );

    return Scaffold(
      drawer: desktop ? null : ChatDrawer(currentChatId: chatId),
      drawerEdgeDragWidth: desktop ? null : MediaQuery.sizeOf(context).width * 0.25,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (desktop)
            _DesktopTopBar(
              title: title,
              entry: entry,
              chatId: chatId,
              onModel: (anchor) => _pickModel(modelRef, anchor: anchor),
              onNew: onNew,
            )
          else
            _TopBar(
              title: title,
              onModel: () => _pickModel(modelRef),
              onNew: onNew,
            ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: body),
              if (chatId != null)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IgnorePointer(
                      ignoring: !_showDown,
                      child: AnimatedSlide(
                        offset: _showDown ? Offset.zero : const Offset(0, 0.4),
                        duration: NurMotion.base,
                        curve: NurMotion.curve,
                        child: AnimatedOpacity(
                          opacity: _showDown ? 1 : 0,
                          duration: NurMotion.base,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: NurPressable(
                              onTap: _toBottom,
                              tooltip: 'Scroll to bottom',
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              pressedScale: 0.92,
                              child: SizedBox.square(dimension: 36, child: Icon(NurIcons.scrollDown, size: 18, color: Theme.of(context).colorScheme.onSurface)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                // Desktop: 768 px column (+ the composer's 10 px side margins).
                constraints: BoxConstraints(maxWidth: desktop ? 788 : 800),
                child: composer,
              ),
            ),
          ),
          if (desktop)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Nur can make mistakes. Check important info.', style: TextStyle(fontSize: 11.5, color: context.nur.subtle)),
            ),
        ]),
      ),
    );
  }

  Widget _messageList(String chatId, ThreadData data) {
    final items = buildItems(data);
    final showPending = _busy && (items.isEmpty || items.last is UserItem || (items.last is AssistantItem && (items.last as AssistantItem).last.status != 'streaming' && _live.active.value[chatId] == ''));
    final count = items.length + (showPending ? 1 : 0);
    if (count != _lastItemCount) {
      final first = _lastItemCount < 0;
      _lastItemCount = count;
      if (first) {
        _settleToBottom();
      } else if (_stick) {
        _queueJump();
      }
    }
    final desktop = isDesktopLayout(context);
    final list = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: count,
          itemBuilder: (context, i) {
            if (i >= items.length) {
              return const Readable(key: ValueKey('pending'), padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Align(alignment: AlignmentDirectional.centerStart, child: TypingDots()));
            }
            final it = items[i];
            return switch (it) {
              UserItem() => UserMessageView(key: ValueKey(it.key), chatId: chatId, item: it, busy: _busy),
              AssistantItem() => AssistantTurnView(key: ValueKey(it.key), chatId: chatId, item: it, isLast: i == items.length - 1, busy: _busy),
              MarkerItem() => MarkerView(key: ValueKey(it.key), msg: it.msg),
            };
          },
        ),
    );
    if (!desktop) return list;
    // Desktop: always-visible thin scrollbar at the window edge.
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false), child: list),
    );
  }
}


class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onModel, required this.onNew});
  final String title;
  final VoidCallback onModel;
  final VoidCallback? onNew;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(alignment: Alignment.center, children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Builder(
            builder: (c) => Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: NurIconButton(tooltip: 'Chats', icon: NurIcons.menu, size: 22, box: 42, color: Theme.of(context).colorScheme.onSurface, onTap: () => Scaffold.of(c).openDrawer()),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: NurPressable(
            onTap: onModel,
            borderRadius: BorderRadius.circular(NurRadius.row),
            pressedScale: 0.97,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2))),
              const SizedBox(width: 4),
              Icon(NurIcons.chevronDown, size: 16, color: context.nur.muted),
            ]),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: NurIconButton(tooltip: 'New chat', icon: NurIcons.newChat, size: 22, box: 42, color: onNew == null ? null : Theme.of(context).colorScheme.onSurface, onTap: onNew),
          ),
        ),
      ]),
    );
  }
}

/// Desktop top bar: model picker (anchored popover) on the left, context ring + new chat on the right.
class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({required this.title, required this.entry, required this.chatId, required this.onModel, required this.onNew});
  final String title;
  final ModelEntry? entry;
  final String? chatId;
  final void Function(BuildContext anchor) onModel;
  final VoidCallback? onNew;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final e = entry;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Builder(
            builder: (anchor) => NurPressable(
              tooltip: 'Choose model',
              onTap: () => onModel(anchor),
              borderRadius: BorderRadius.circular(NurRadius.control),
              pressedScale: 0.98,
              padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 8, 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e != null) ...[
                  ProviderLogo(preset: e.preset, kind: e.providerKind, modelId: e.model.modelId, name: e.model.displayName, size: 18),
                  const SizedBox(width: 8),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                ),
                const SizedBox(width: 4),
                Icon(NurIcons.chevronDown, size: 16, color: nur.muted),
              ]),
            ),
          ),
          const Spacer(),
          ContextRing(chatId: chatId),
          const SizedBox(width: 2),
          NurIconButton(tooltip: 'New chat (Ctrl+N)', icon: NurIcons.newChat, box: 36, onTap: onNew),
        ]),
      ),
    );
  }
}


class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion});
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final suggestions = ar
        ? const [
            ('حالة الـ NAS', 'كيف حال جهاز الـ NAS الآن؟', NurIcons.nas),
            ('اشرح ببساطة', 'اشرح لي كيف يعمل الذكاء الاصطناعي ببساطة', NurIcons.think),
            ('اكتب رسالة', 'ساعدني في كتابة رسالة شكر قصيرة لزميلي', NurIcons.edit),
            ('خطة يوم', 'ضع لي خطة يوم منظم ومريح', NurIcons.uptime),
          ]
        : const [
            ('Check my NAS', 'How is my NAS doing right now?', NurIcons.nas),
            ('Explain simply', 'Explain how large language models work, simply', NurIcons.think),
            ('Write a message', 'Help me write a short thank-you note to a colleague', NurIcons.edit),
            ('Plan my day', 'Make me a calm, focused plan for today', NurIcons.uptime),
          ];
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const AppearIn(child: NurLogo(size: 44)),
              const SizedBox(height: 18),
              AppearIn(
                delay: const Duration(milliseconds: 60),
                child: Text(ar ? 'كيف أقدر أساعدك؟' : 'What can I help with?', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                  for (var i = 0; i < suggestions.length; i++)
                    AppearIn(
                      delay: Duration(milliseconds: 120 + 50 * i),
                      child: _SuggestionChip(title: suggestions[i].$1, prompt: suggestions[i].$2, icon: suggestions[i].$3, onTap: () => onSuggestion(suggestions[i].$2)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.title, required this.prompt, required this.icon, required this.onTap});
  final String title;
  final String prompt;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final w = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: w < 420 ? (w - 50) / 2 : 260,
      child: NurPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NurRadius.card),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        pressedScale: 0.98,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: nur.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
          ]),
          const SizedBox(height: 4),
          Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 13, height: 1.35)),
        ]),
      ),
    );
  }
}

class _NoModels extends StatelessWidget {
  const _NoModels();
  @override
  Widget build(BuildContext context) => _Centered(
        logo: true,
        title: 'Welcome to Nur',
        text: 'Connect your NAS to chat with local models, or add a cloud provider like OpenAI, Anthropic or OpenRouter.',
        actions: [
          FilledButton.icon(onPressed: () => context.push('/onboarding'), icon: const Icon(NurIcons.nas), label: const Text('Connect my NAS')),
          OutlinedButton.icon(
            onPressed: () => openSettings(context, SettingsSection.providers),
            icon: const Icon(NurIcons.providers),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Add a provider')),
          ),
        ],
      );
}

class _Centered extends StatelessWidget {
  const _Centered({this.icon, this.logo = false, required this.title, required this.text, this.actions = const []});
  final IconData? icon;
  final bool logo;
  final String title;
  final String text;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AppearIn(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (logo) const NurLogo(size: 48) else if (icon != null) EmptyIllustration(icon: icon!),
                    const SizedBox(height: 16),
                    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                    const SizedBox(height: 8),
                    Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.nur.muted, height: 1.4)),
                    const SizedBox(height: 20),
                    for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(width: double.infinity, child: a)),
                  ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

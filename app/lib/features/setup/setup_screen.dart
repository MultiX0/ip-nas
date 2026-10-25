// Shown instead of the chat until Nur is really ready: connect Nur Hub, install llama.cpp on it, download a model
// that fits the NAS. Every line comes from the hub as it is now; nothing here is assumed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_logo.dart';
import '../nas/nas_hub_client.dart';
import '../nas/nas_service.dart';
import '../nas/nas_widgets.dart';
import '../providers/llm_registry.dart';
import 'setup_status.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  List<Map<String, dynamic>>? _catalog;
  String? _catalogError;
  String? _jobId;
  String _jobLabel = '';
  double _progress = 0;
  String? _jobError;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  NasHubClientImpl? get _client => ref.read(activeNasProvider).value;

  Future<void> _loadCatalog() async {
    final c = _client;
    if (c == null) return;
    try {
      final all = await c.catalog();
      if (mounted) setState(() => (_catalog = all.where((e) => e['fits'] == true).toList(), _catalogError = null));
    } catch (e) {
      if (mounted) setState(() => _catalogError = '$e');
    }
  }

  void _watch(String jobId, String label) {
    setState(() => (_jobId = jobId, _jobLabel = label, _progress = 0, _jobError = null));
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final c = _client;
      if (c == null) return;
      try {
        final j = await c.job(jobId);
        final st = '${j['state']}';
        if (!mounted) return;
        setState(() => _progress = ((j['progress'] as num?) ?? 0).toDouble());
        if (j['stage'] == 'warming' && _jobLabel.startsWith('Downloading')) setState(() => _jobLabel = 'Preparing the model');
        if (st != 'running' && st != 'queued') {
          _poll?.cancel();
          setState(() => (_jobId = null, _jobError = st == 'done' ? null : '${j['error'] ?? st}'));
          final status = ref.read(setupStatusProvider.notifier);
          if (st == 'done') {
            await status.holdWhile(() async {
              final model = await ref.read(activeNasProvider.notifier).chooseDefaultModel();
              final reg = ref.read(llmRegistryProvider);
              for (var i = 0; model != null && reg.modelByRef(model) == null && i < 20; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 250));
              }
              await ref.read(chatEngineProvider).prewarm(null);
            }());
          } else {
            await status.refresh();
          }
        }
      } catch (e) {
        if (mounted) setState(() => _jobError = '$e');
      }
    });
  }

  Future<void> _runtime(String action) async {
    final c = _client;
    if (c == null) return;
    try {
      final r = await c.runtimeAction('llamacpp', action);
      final id = r['job_id'];
      if (id != null) {
        _watch('$id', 'Installing llama.cpp');
      } else {
        await ref.read(setupStatusProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _jobError = '$e');
    }
  }

  Future<void> _download(Map<String, dynamic> m) async {
    final c = _client;
    if (c == null) return;
    try {
      final id = await c.download(runtime: 'llamacpp', repo: '${m['repo']}', file: '${m['file']}');
      _watch(id, 'Downloading ${m['title'] ?? m['id']}');
    } catch (e) {
      if (mounted) setState(() => _jobError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(setupStatusProvider);
    ref.listen(setupStatusProvider, (prev, next) {
      if (next.step == SetupStep.downloadModel && _catalog == null) _loadCatalog();
      if (next.ready) context.go('/');
    });
    if (s.step == SetupStep.downloadModel && _catalog == null && _catalogError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalog());
    }
    final nur = context.nur;
    final done = <SetupStep>{
      if (s.step.index > SetupStep.unreachable.index) SetupStep.pair,
      if (s.step.index > SetupStep.startLlama.index) SetupStep.installLlama,
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
              children: [
                const Center(child: NurLogo(size: 44)),
                const SizedBox(height: 16),
                const Text(
                  'Set up Nur',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nur chats with AI models that run on your own NAS. Three steps before the first chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nur.muted, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                _Step(
                  n: 1,
                  title: 'Connect Nur Hub',
                  state: done.contains(SetupStep.pair) ? _S.done : (s.step == SetupStep.checking ? _S.working : _S.todo),
                  body: switch (s.step) {
                    SetupStep.checking => 'Checking your NAS...',
                    SetupStep.pair => 'Nur Hub runs on your NAS (see the IP NAS guide). Pair this device with it.',
                    SetupStep.unreachable =>
                      '${s.hubName ?? 'Your NAS'} is not answering at ${s.hubUrl ?? ''}. Check that it is on and on the same network.'
                          '${s.error == null || s.error!.startsWith('Cannot reach') ? '' : '\n${s.error}'}',
                    _ => 'Connected to ${s.hubName ?? 'your NAS'}.',
                  },
                  action: switch (s.step) {
                    SetupStep.pair => FilledButton.icon(
                      onPressed: () => context.push('/onboarding'),
                      icon: const Icon(NurIcons.nas),
                      label: const Text('Connect my NAS'),
                    ),
                    SetupStep.unreachable => OutlinedButton.icon(
                      onPressed: () => ref.read(setupStatusProvider.notifier).refresh(),
                      icon: const Icon(NurIcons.refresh),
                      label: const Text('Try again'),
                    ),
                    _ => null,
                  },
                ),
                _Step(
                  n: 2,
                  title: 'Install llama.cpp on the NAS',
                  state: done.contains(SetupStep.installLlama)
                      ? _S.done
                      : (s.step == SetupStep.installLlama || s.step == SetupStep.startLlama)
                      ? (_jobId != null ? _S.working : _S.todo)
                      : _S.locked,
                  body: s.step == SetupStep.startLlama
                      ? 'llama.cpp is installed but not running.'
                      : 'llama.cpp runs the models. Nur Hub installs it as a Docker container (about 200 MB).',
                  action: _jobId == null && s.step == SetupStep.installLlama
                      ? FilledButton(onPressed: () => _runtime('install'), child: const Text('Install llama.cpp'))
                      : _jobId == null && s.step == SetupStep.startLlama
                      ? FilledButton(onPressed: () => _runtime('start'), child: const Text('Start llama.cpp'))
                      : null,
                ),
                _Step(
                  n: 3,
                  title: 'Download a model',
                  state: s.ready
                      ? _S.done
                      : s.step == SetupStep.warming
                      ? _S.working
                      : s.step == SetupStep.downloadModel
                      ? (_jobId != null ? _S.working : _S.todo)
                      : _S.locked,
                  body:
                      'Only the models that run on this NAS (${s.ram > 0 ? '${(s.ram / 1073741824).toStringAsFixed(1)} GB RAM' : 'its RAM'}) are listed. '
                      'Small models are fast but make mistakes; read the disclaimer.',
                  child: s.step == SetupStep.warming && _jobId != null
                      ? _progressRow(context)
                      : s.step == SetupStep.warming
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('Preparing the model so the first chat is fast...', style: TextStyle(color: nur.muted, fontSize: 13)),
                        )
                      : s.step == SetupStep.downloadModel
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [if (_jobId != null) _progressRow(context), _models(context)],
                        )
                      : null,
                ),
                if (_jobId != null && s.step != SetupStep.downloadModel && s.step != SetupStep.warming) _progressRow(context),
                if (_jobError != null) ...[
                  const SizedBox(height: 10),
                  Text(_jobError!, style: const TextStyle(color: NurColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/disclaimer'),
                    child: Text(
                      'Read the disclaimer',
                      style: TextStyle(decoration: TextDecoration.underline, color: nur.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressRow(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$_jobLabel... ${(_progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: context.nur.muted, fontSize: 13)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 6),
        ),
      ],
    ),
  );

  Widget _models(BuildContext context) {
    if (_catalogError != null) return Text(_catalogError!, style: const TextStyle(color: NurColors.danger, fontSize: 13));
    final list = _catalog;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (list.isEmpty) {
      return Text('No model in the catalog fits this NAS. It needs more free RAM.', style: TextStyle(color: context.nur.muted, fontSize: 13));
    }
    return Column(
      children: [
        for (final m in list)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NurCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${m['title'] ?? m['id']}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (m['recommended'] == true) ...[const SizedBox(width: 8), const StateChip('recommended', color: NurColors.ok)],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatBytes(m['size'] as num?)} · ${m['note'] ?? ''}',
                          style: TextStyle(color: context.nur.muted, fontSize: 12.5, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (m['installed'] == true)
                    const Icon(NurIcons.check, color: NurColors.ok)
                  else
                    FilledButton(onPressed: _jobId == null ? () => _download(m) : null, child: const Text('Download')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _S { todo, working, done, locked }

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.state, required this.body, this.action, this.child});
  final int n;
  final String title;
  final _S state;
  final String body;
  final Widget? action;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final locked = state == _S.locked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: NurCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: state == _S.done ? NurColors.ok : nur.subtle),
                    child: state == _S.done
                        ? const Icon(NurIcons.check, size: 16, color: Colors.white)
                        : state == _S.working
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body.trim(), style: TextStyle(color: nur.muted, fontSize: 13, height: 1.4)),
              if (!locked && action != null) ...[const SizedBox(height: 12), action!],
              if (!locked && child != null) child!,
            ],
          ),
        ),
      ),
    );
  }
}

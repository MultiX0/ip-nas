// NAS dashboard: status, apps (Docker), local models (catalog + Hugging Face), runtimes.
// Phones: one section at a time (pill tabs). Desktop: a multi-column dashboard.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/desktop.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_charts.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import 'nas_hub_client.dart';
import 'nas_service.dart';
import 'nas_widgets.dart';

class NasScreen extends ConsumerStatefulWidget {
  const NasScreen({super.key});
  @override
  ConsumerState<NasScreen> createState() => _NasScreenState();
}

class _NasScreenState extends ConsumerState<NasScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final nas = ref.watch(activeNasProvider);
    final client = nas.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(client?.device?.name ?? 'NAS'),
        actions: [
          if (client != null)
            PopupMenuButton<String>(
              icon: const Icon(NurIcons.more),
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'pair') context.push('/onboarding');
                if (v == 'forget' && await confirmDialog(context, 'Forget this NAS?', 'Nur will stop using it for chats, tools and models. You can pair it again later.', ok: 'Forget', danger: true)) {
                  await ref.read(activeNasProvider.notifier).forget();
                }
              },
              itemBuilder: (c) => [menuRow('pair', NurIcons.pairDevice, 'Pair another NAS'), menuRow('forget', NurIcons.unpin, 'Forget this NAS', danger: true)],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: switch (nas) {
        AsyncLoading() => const _OverviewSkeleton(embedded: false),
        AsyncError(:final error) => EmptyState(icon: NurIcons.error, tone: NurColors.danger, title: 'Could not load the NAS', body: '$error'),
        _ when client == null => EmptyState(
          icon: NurIcons.nas,
          title: 'No NAS connected',
          body: 'Connect your NAS to chat with local models, control apps and search the web privately.',
          action: FilledButton.icon(onPressed: () => context.push('/onboarding'), icon: const Icon(NurIcons.add), label: const Text('Connect my NAS')),
        ),
        _ => LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 980 && isDesktopLayout(context)
              ? _DesktopDashboard(client: client)
              : Column(
                  children: [
                    const SizedBox(height: 4),
                    PillTabs(labels: const ['Overview', 'Apps', 'Models', 'Runtimes'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: switch (_tab) {
                        0 => _Overview(client: client),
                        1 => _Apps(client: client),
                        2 => _Models(client: client),
                        _ => _Runtimes(client: client),
                      },
                    ),
                  ],
                ),
        ),
      },
    );
  }
}

/// Desktop: the stats in one row, then apps, models and runtimes side by side (runtimes below on narrower windows).
class _DesktopDashboard extends StatefulWidget {
  const _DesktopDashboard({required this.client});
  final NasHubClientImpl client;
  @override
  State<_DesktopDashboard> createState() => _DesktopDashboardState();
}

class _DesktopDashboardState extends State<_DesktopDashboard> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return LayoutBuilder(
      builder: (context, box) {
        final three = box.maxWidth >= 1320;
        final panelH = (MediaQuery.sizeOf(context).height - 200).clamp(420.0, 680.0);
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              _Overview(client: client, embedded: true),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Panel(
                      title: 'Apps',
                      icon: NurIcons.apps,
                      height: panelH,
                      child: _Apps(client: client),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Panel(
                      title: 'Models',
                      icon: NurIcons.localModel,
                      height: panelH,
                      child: _Models(client: client),
                    ),
                  ),
                  if (three) ...[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 340,
                      child: _Panel(
                        title: 'Runtimes',
                        icon: NurIcons.runtime,
                        height: panelH,
                        child: _Runtimes(client: client),
                      ),
                    ),
                  ],
                ],
              ),
              if (!three) ...[
                const SizedBox(height: 16),
                _Panel(
                  title: 'Runtimes',
                  icon: NurIcons.runtime,
                  height: 330,
                  child: _Runtimes(client: client),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.height, required this.child});
  final String title;
  final IconData icon;
  final double height;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? NurColors.g950.withValues(alpha: 0.35) : NurColors.g50,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(NurRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 18, 8),
            child: Row(
              children: [
                IconTile(icon, size: 28),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Live system status (polled every 3 s while the app is in the foreground) and the disks.
class _Overview extends StatefulWidget {
  const _Overview({required this.client, this.embedded = false});
  final NasHubClientImpl client;

  /// Desktop dashboard: no own scroll view, stats in one row, disks side by side.
  final bool embedded;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> with WidgetsBindingObserver {
  Map<String, dynamic>? _sys;
  String? _error;
  Timer? _timer;
  bool _busy = false;
  // Recent samples for the sparklines (presentation only; 40 x 3 s = 2 minutes).
  final _cpuHist = <double>[];
  final _rxRate = <double>[];
  num? _lastRx;
  DateTime? _lastAt;

  void _record(Map<String, dynamic> s) {
    void push(List<double> l, double v) {
      l.add(v);
      if (l.length > 40) l.removeAt(0);
    }

    push(_cpuHist, ((s['cpu'] as num?) ?? 0).toDouble());
    final rx = s['net'] is Map ? (s['net'] as Map)['rx'] as num? : null;
    final now = DateTime.now();
    if (rx != null && _lastRx != null && _lastAt != null) {
      final dt = now.difference(_lastAt!).inMilliseconds / 1000;
      if (dt > 0) push(_rxRate, ((rx - _lastRx!) / dt).clamp(0, double.infinity).toDouble());
    }
    _lastRx = rx;
    _lastAt = now;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _timer?.cancel();
    if (s == AppLifecycleState.resumed) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = await widget.client.system();
      if (mounted) {
        setState(() {
          _sys = s;
          _error = null;
          _record(s);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sys;
    if (s == null) {
      final w = _error != null
          ? EmptyState(
              icon: NurIcons.wifiOff,
              tone: NurColors.warn,
              title: 'NAS not reachable',
              body: _error,
              action: OutlinedButton.icon(onPressed: _poll, icon: const Icon(NurIcons.refresh), label: const Text('Try again')),
            )
          : _OverviewSkeleton(embedded: widget.embedded);
      return widget.embedded ? SizedBox(height: _error != null ? 320 : 290, child: w) : w;
    }
    final ramUsed = (s['ram_used'] as num?) ?? 0, ramTotal = (s['ram_total'] as num?) ?? 0;
    final cpu = ((s['cpu'] as num?) ?? 0).toDouble();
    final temp = (s['temp'] as num?)?.toDouble();
    final disks = ((s['disks'] as List?) ?? const []).whereType<Map>().toList();
    final net = s['net'] is Map ? s['net'] as Map : const {};
    final wifi = s['wifi'] is Map ? s['wifi'] as Map : null;
    final children = <Widget>[
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(NurIcons.warning, size: 14, color: NurColors.warn),
              const SizedBox(width: 6),
              Expanded(child: Text('Last update failed: $_error', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NurColors.warn, fontSize: 12.5))),
            ],
          ),
        ),
      LayoutBuilder(
        builder: (c, box) {
          final w = box.maxWidth >= 1000 ? (box.maxWidth - 60) / 6 : (box.maxWidth >= 640 ? (box.maxWidth - 24) / 3 : (box.maxWidth - 12) / 2);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: w,
                child: _StatCard(icon: NurIcons.cpu, label: 'CPU', value: '${cpu.toStringAsFixed(0)}%', fraction: cpu / 100, spark: _cpuHist, sparkMax: 100),
              ),
              SizedBox(
                width: w,
                child: _StatCard(
                  icon: NurIcons.ram,
                  label: 'Memory',
                  value: formatBytes(ramUsed),
                  fraction: ramTotal > 0 ? ramUsed / ramTotal : 0,
                  hint: 'of ${formatBytes(ramTotal)}',
                ),
              ),
              SizedBox(
                width: w,
                child: _StatCard(
                  icon: NurIcons.temperature,
                  label: 'Temperature',
                  value: temp == null ? '-' : '${temp.toStringAsFixed(1)} °C',
                  fraction: temp == null ? null : (temp / 85),
                  ringColor: temp == null ? null : (temp >= 80 ? NurColors.danger : (temp >= 70 ? NurColors.warn : null)),
                  hint: temp == null ? null : (temp >= 80 ? 'Hot, check the fan' : (temp >= 70 ? 'Warm' : 'Normal')),
                ),
              ),
              SizedBox(
                width: w,
                child: _StatCard(icon: NurIcons.uptime, label: 'Uptime', value: formatUptime(s['uptime'] as num?), hint: 'Since the last restart'),
              ),
              SizedBox(
                width: w,
                child: _StatCard(
                  icon: NurIcons.network,
                  label: 'Network',
                  value: '↓ ${formatBytes(net['rx'] as num?)}',
                  spark: _rxRate,
                  hint: _rxRate.isEmpty ? '↑ ${formatBytes(net['tx'] as num?)} sent' : '${formatBytes(_rxRate.last)}/s now · ↑ ${formatBytes(net['tx'] as num?)}',
                ),
              ),
              if (wifi != null)
                SizedBox(
                  width: w,
                  child: _StatCard(icon: NurIcons.wifi, label: 'Wi-Fi', value: '${wifi['ssid'] ?? '-'}', hint: wifi['signal'] == null ? null : 'Signal ${wifi['signal']}'),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 22),
      const Row(
        children: [
          Icon(NurIcons.disk, size: 16),
          SizedBox(width: 8),
          Text('Storage', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
        ],
      ),
      const SizedBox(height: 10),
      if (disks.isEmpty) Text('No disks reported.', style: TextStyle(color: context.nur.muted)),
      if (widget.embedded)
        LayoutBuilder(
          builder: (c, box) {
            final w = box.maxWidth >= 900 ? (box.maxWidth - 24) / 3 : (box.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final d in disks) SizedBox(width: w, child: _disk(d))],
            );
          },
        )
      else
        for (final d in disks) Padding(padding: const EdgeInsets.only(bottom: 10), child: _disk(d)),
    ];
    if (widget.embedded) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
    );
  }

  Widget _disk(Map d) {
    final total = (d['total'] as num?) ?? 0;
    final used = (d['used'] as num?) ?? 0;
    final f = total > 0 ? used / total : 0.0;
    return NurCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(NurIcons.disk, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d['mount'] ?? d['name']}', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${d['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.nur.subtle, fontSize: 11.5)),
                  ],
                ),
              ),
              Text(
                '${(f * 100).round()}%',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: usageColor(context, f.toDouble()), fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          UsageBar(value: f.toDouble(), height: 6),
          const SizedBox(height: 6),
          Text('${formatBytes(used)} used of ${formatBytes(total)} · ${formatBytes(total - used)} free', style: TextStyle(color: context.nur.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.fraction, this.hint, this.spark, this.sparkMax, this.ringColor});
  final IconData icon;
  final String label;
  final String value;
  final double? fraction;
  final String? hint;

  /// Recent values (oldest first) drawn as a sparkline at the bottom.
  final List<double>? spark;
  final double? sparkMax;
  final Color? ringColor;
  @override
  Widget build(BuildContext context) {
    final nur = context.nur;
    final f = fraction;
    final s = spark;
    final hasSpark = s != null && s.length > 1;
    final hintText = hint == null ? null : Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 12));
    return NurCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: SizedBox(
        height: 98,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: nur.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: nur.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        const SizedBox(height: 2),
                        ?hintText,
                      ],
                    ),
                  ),
                  if (f != null)
                    RingGauge(
                      value: f,
                      size: 44,
                      stroke: 4.5,
                      color: ringColor,
                      child: Text(
                        '${(f.clamp(0.0, 1.0) * 100).round()}',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                ],
              ),
            ),
            if (hasSpark) Sparkline(values: s, max: sparkMax, height: 28, color: ringColor ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

/// Placeholder grid shown while the first status arrives.
class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton({required this.embedded});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget card() => Container(
      height: 124,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(NurRadius.card), border: Border.all(color: scheme.outlineVariant)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NurSkeleton(width: 70, height: 10),
          SizedBox(height: 14),
          NurSkeleton(width: 110, height: 18),
          Spacer(),
          NurSkeleton(height: 22, radius: 6),
        ],
      ),
    );
    return SkeletonShimmer(
      child: Padding(
        padding: embedded ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: LayoutBuilder(
          builder: (c, box) {
            final cols = box.maxWidth >= 1000 ? 6 : (box.maxWidth >= 640 ? 3 : 2);
            final w = (box.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [for (var i = 0; i < 6; i++) SizedBox(width: w, child: card())]);
          },
        ),
      ),
    );
  }
}

/// Docker containers on the NAS with start, stop, restart, pause, logs and remove.
class _Apps extends StatefulWidget {
  const _Apps({required this.client});
  final NasHubClientImpl client;
  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.containers();
      r.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      if (mounted) setState(() => (_items = r, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _act(String name, String action) async {
    const confirm = {'stop', 'restart', 'remove', 'pause'};
    if (confirm.contains(action)) {
      final ok = await confirmDialog(
        context,
        '${action[0].toUpperCase()}${action.substring(1)} $name?',
        action == 'remove' ? 'The app container will be deleted. Its data folders on the NAS stay, but you will need to reinstall the app.' : 'Anything using $name will be interrupted for a moment.',
        ok: '${action[0].toUpperCase()}${action.substring(1)}',
        danger: action == 'remove' || action == 'stop',
      );
      if (!ok) return;
    }
    setState(() => _busy.add(name));
    try {
      final r = await widget.client.containerAction(name, action);
      if (mounted) showSnack(context, '${r['message'] ?? (r['ok'] == true ? 'Done' : 'Failed')}');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(name));
      await _load();
    }
  }

  void _logs(String name) {
    showAdaptiveSheet<void>(
      maxWidth: 860,
      context: context,
      isScrollControlled: true,
      builder: (c) => _LogsSheet(client: widget.client, name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return _error != null
          ? EmptyState(
              icon: NurIcons.appsError,
              tone: NurColors.danger,
              title: 'Could not list apps',
              body: _error,
              action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NurIcons.refresh), label: const Text('Try again')),
            )
          : const SkeletonList(cards: true, count: 5);
    }
    if (items.isEmpty) return const EmptyState(icon: NurIcons.apps, title: 'No apps yet', body: 'Apps you install on the NAS (CasaOS, Docker) show up here.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (c, i) {
          final it = items[i];
          final name = '${it['name']}';
          final state = '${it['state'] ?? ''}';
          final color = switch (state) {
            'running' => NurColors.ok,
            'paused' => NurColors.warn,
            'restarting' => NurColors.info,
            'exited' || 'dead' => NurColors.danger,
            _ => null,
          };
          final memUsed = it['mem_used'] as num?, memLimit = it['mem_limit'] as num?;
          return NurCard(
            onTap: () => _logs(name),
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 6, 14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const IconTile(NurIcons.container, size: 38),
                    PositionedDirectional(
                      bottom: -2,
                      end: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: color ?? context.nur.subtle,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StateChip(state.isEmpty ? 'unknown' : state, color: color),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${it['image'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.nur.muted, fontSize: 12.5),
                      ),
                      if (state == 'running') ...[
                        const SizedBox(height: 4),
                        Text(
                          'CPU ${((it['cpu'] as num?) ?? 0).toStringAsFixed(1)}%  ·  RAM ${formatBytes(memUsed)}${memLimit != null ? ' / ${formatBytes(memLimit)}' : ''}',
                          style: TextStyle(color: context.nur.subtle, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_busy.contains(name))
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Actions',
                    icon: const Icon(NurIcons.moreVertical),
                    onSelected: (a) => a == 'logs' ? _logs(name) : _act(name, a),
                    itemBuilder: (c) => [
                      if (state != 'running') menuRow('start', NurIcons.play, 'Start'),
                      if (state == 'running') menuRow('stop', NurIcons.stop, 'Stop'),
                      menuRow('restart', NurIcons.refresh, 'Restart'),
                      if (state == 'running') menuRow('pause', NurIcons.pause, 'Pause'),
                      if (state == 'paused') menuRow('unpause', NurIcons.play, 'Resume'),
                      menuRow('logs', NurIcons.terminal, 'Logs'),
                      const PopupMenuDivider(height: 8),
                      menuRow('remove', NurIcons.delete, 'Remove', danger: true),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LogsSheet extends StatefulWidget {
  const _LogsSheet({required this.client, required this.name});
  final NasHubClientImpl client;
  final String name;
  @override
  State<_LogsSheet> createState() => _LogsSheetState();
}

class _LogsSheetState extends State<_LogsSheet> {
  String? _logs;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await widget.client.containerLogs(widget.name, tail: 300);
      if (mounted) setState(() => (_logs = l, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                const IconTile(NurIcons.terminal, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Logs · ${widget.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (_logs != null) CopyButton(text: () => _logs ?? '', size: 18, box: 36),
                IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(NurIcons.refresh, size: 18)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              decoration: BoxDecoration(
                color: context.nur.codeBg,
                borderRadius: BorderRadius.circular(NurRadius.field),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: _logs == null
                  ? (_error != null
                        ? EmptyState(icon: NurIcons.error, tone: NurColors.danger, title: 'Could not load logs', body: _error)
                        : const SkeletonList(leading: false, dense: true, count: 12))
                  : SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(_logs!.isEmpty ? '(no output)' : _logs!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Installed models, the hub's catalog and Hugging Face search, with download progress.
class _Models extends StatefulWidget {
  const _Models({required this.client});
  final NasHubClientImpl client;
  @override
  State<_Models> createState() => _ModelsState();
}

class _ModelsState extends State<_Models> {
  int _sub = 0;
  List<Map<String, dynamic>>? _local;
  List<Map<String, dynamic>>? _catalog;
  String? _error;
  final Map<String, Map<String, dynamic>> _jobs = {}; // last job status by key (file or name)
  final Map<String, String> _jobIds = {}; // running job id by key
  Timer? _jobTimer;
  // Hugging Face search
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _hf;
  bool _hfBusy = false;
  String? _hfError;

  @override
  void initState() {
    super.initState();
    _load();
    _resumeJobs();
  }

  @override
  void dispose() {
    _jobTimer?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.client.localModels(), widget.client.catalog()]);
      if (mounted) setState(() => (_local = r[0], _catalog = r[1], _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _resumeJobs() async {
    try {
      for (final j in await widget.client.jobs()) {
        final st = '${j['state']}';
        if (st == 'running' || st == 'queued') {
          final key = '${j['title'] ?? j['id']}';
          _jobIds[key] = '${j['id']}';
          _jobs[key] = j;
        }
      }
      if (_jobIds.isNotEmpty) _startJobTimer();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _startJobTimer() {
    _jobTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _pollJobs());
  }

  Future<void> _pollJobs() async {
    if (_jobIds.isEmpty) {
      _jobTimer?.cancel();
      _jobTimer = null;
      return;
    }
    for (final e in _jobIds.entries.toList()) {
      try {
        final j = await widget.client.job(e.value);
        _jobs[e.key] = j;
        final st = '${j['state']}';
        if (st == 'done' || st == 'error' || st == 'cancelled') {
          _jobIds.remove(e.key);
          if (mounted) {
            showSnack(context, st == 'done' ? 'Downloaded ${e.key}' : (st == 'error' ? 'Download failed: ${j['error'] ?? 'unknown error'}' : 'Download cancelled'));
          }
          if (st == 'done') {
            _jobs.remove(e.key);
            unawaited(_load());
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _download({required String key, required String runtime, String? repo, String? file, String? name, num? size, bool fits = true}) async {
    if (!fits && !await confirmDialog(context, 'Too big for this NAS', 'This model needs about ${formatBytes((size ?? 0) + 0.9e9)} of memory. The NAS will probably refuse it.', ok: 'Try anyway')) {
      return;
    }
    try {
      final id = await widget.client.download(runtime: runtime, repo: repo, file: file, name: name);
      setState(() {
        _jobIds[key] = id;
        _jobs[key] = {'state': 'queued', 'progress': 0.0};
      });
      _startJobTimer();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    if (!await confirmDialog(context, 'Delete ${m['id']}?', 'This frees ${formatBytes(m['size'] as num?)} on the NAS. You can download it again later.', ok: 'Delete', danger: true)) {
      return;
    }
    try {
      final r = await widget.client.deleteLocalModel('${m['runtime']}', '${m['id']}');
      if (mounted) showSnack(context, '${r['message'] ?? 'Deleted'}');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
    await _load();
  }

  Future<void> _searchHf() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => (_hfBusy = true, _hfError = null));
    try {
      final r = await widget.client.hfSearch(q);
      if (mounted) setState(() => _hf = r);
    } catch (e) {
      if (mounted) setState(() => _hfError = '$e');
    } finally {
      if (mounted) setState(() => _hfBusy = false);
    }
  }

  void _openRepo(String repo) {
    showAdaptiveSheet<void>(
      maxWidth: 860,
      context: context,
      isScrollControlled: true,
      builder: (c) => _HfFilesSheet(
        client: widget.client,
        repo: repo,
        onDownload: (f) {
          Navigator.pop(c);
          _download(key: '${f['file']}', runtime: 'llamacpp', repo: repo, file: '${f['file']}', size: f['size'] as num?, fits: f['fits'] != false);
          setState(() => _sub = 0);
        },
      ),
    );
  }

  Widget _progress(String key) {
    final j = _jobs[key];
    if (j == null) return const SizedBox.shrink();
    final st = '${j['state']}';
    if (st == 'error') return Text('Failed: ${j['error'] ?? ''}', style: const TextStyle(color: NurColors.danger, fontSize: 12));
    final p = ((j['progress'] as num?) ?? 0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(child: Meter(value: p)),
          const SizedBox(width: 10),
          Text(j['total'] != null && (j['total'] as num) > 0 ? '${(p * 100).toStringAsFixed(0)}% · ${formatBytes(j['bytes'] as num?)}' : st, style: TextStyle(color: context.nur.muted, fontSize: 12)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Cancel',
            icon: const Icon(NurIcons.close, size: 16),
            onPressed: _jobIds[key] == null
                ? null
                : () async {
                    try {
                      await widget.client.cancelJob(_jobIds[key]!);
                    } catch (e) {
                      if (mounted) showSnack(context, '$e');
                    }
                  },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Installed')),
              ButtonSegment(value: 1, label: Text('Get models')),
              ButtonSegment(value: 2, label: Text('Hugging Face')),
            ],
            selected: {_sub},
            onSelectionChanged: (s) => setState(() => _sub = s.first),
          ),
        ),
        Expanded(
          child: _local == null && _sub != 2
              ? (_error != null
                    ? EmptyState(
                        icon: NurIcons.error,
                        tone: NurColors.danger,
                        title: 'Could not load models',
                        body: _error,
                        action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NurIcons.refresh), label: const Text('Try again')),
                      )
                    : const SkeletonList(cards: true, count: 4))
              : switch (_sub) {
                  0 => _installed(),
                  1 => _catalogView(),
                  _ => _hfView(),
                },
        ),
      ],
    );
  }

  Widget _installed() {
    final local = _local!;
    final downloading = _jobs.keys.toList();
    if (local.isEmpty && downloading.isEmpty) {
      return EmptyState(
        icon: NurIcons.localModel,
        title: 'No local models yet',
        body: 'Download a model to chat privately on your NAS, no internet needed.',
        action: FilledButton.icon(onPressed: () => setState(() => _sub = 1), icon: const Icon(NurIcons.download), label: const Text('Get models')),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final k in downloading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NurCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconTile(NurIcons.download, size: 30),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Downloading $k', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ],
                    ),
                    _progress(k),
                  ],
                ),
              ),
            ),
          for (final m in local)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NurCard(
                child: Row(
                  children: [
                    const IconTile(NurIcons.localModel, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['id']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('${m['runtime'] == 'ollama' ? 'Ollama' : 'llama.cpp'} · ${formatBytes(m['size'] as num?)}', style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
                              const SizedBox(width: 8),
                              if (m['loaded'] == true) const StateChip('loaded', color: NurColors.ok),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(tooltip: 'Delete', onPressed: () => _delete(m), icon: const Icon(NurIcons.delete, size: 18)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _catalogView() {
    final cat = _catalog ?? const [];
    final sorted = [...cat]..sort((a, b) => (b['recommended'] == true ? 1 : 0).compareTo(a['recommended'] == true ? 1 : 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final m in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NurCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${m['title'] ?? m['id']}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                      if (m['recommended'] == true) const StateChip('Recommended', color: NurColors.ok),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag(formatBytes(m['size'] as num?)),
                      _Tag('needs ${formatBytes(m['ram_needed'] as num?)} RAM'),
                      if (m['tools'] == true) const _Tag('tools'),
                      if (m['vision'] == true) const _Tag('vision'),
                      for (final l in (m['langs'] as List? ?? const [])) _Tag('$l'),
                    ],
                  ),
                  if ('${m['note'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 8), Text('${m['note']}', style: TextStyle(color: context.nur.muted, fontSize: 12.5))],
                  if (m['fits'] == false) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(NurIcons.warning, size: 15, color: NurColors.warn),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text('Too big for the memory of this NAS', style: TextStyle(color: NurColors.warn, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_jobs.containsKey('${m['file']}'))
                    _progress('${m['file']}')
                  else if (m['installed'] == true)
                    const StateChip('Installed', color: NurColors.ok)
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: () => _download(key: '${m['file']}', runtime: 'llamacpp', repo: '${m['repo']}', file: '${m['file']}', size: m['size'] as num?, fits: m['fits'] != false),
                        icon: const Icon(NurIcons.download, size: 16),
                        label: const Text('Download'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _hfView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchHf(),
            decoration: InputDecoration(
              hintText: 'Search GGUF models on Hugging Face',
              prefixIcon: const Icon(NurIcons.search, size: 18),
              suffixIcon: _hfBusy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ),
        if (_hfError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_hfError!, style: const TextStyle(color: NurColors.danger)),
          ),
        Expanded(
          child: _hf == null
              ? (_hfBusy
                    ? const SkeletonList(cards: true, count: 5)
                    : const EmptyState(icon: NurIcons.explore, title: 'Find any GGUF model', body: 'Try "qwen3 4b", "gemma 3" or "arabic".'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: _hf!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final r = _hf![i];
                    return NurCard(
                      onTap: () => _openRepo('${r['repo']}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r['repo']}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text('↓ ${r['downloads'] ?? 0}  ·  ♥ ${r['likes'] ?? 0}', style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Icon(NurIcons.chevron, size: 18, color: context.nur.subtle),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => NurTag(text);
}

class _HfFilesSheet extends StatefulWidget {
  const _HfFilesSheet({required this.client, required this.repo, required this.onDownload});
  final NasHubClientImpl client;
  final String repo;
  final void Function(Map<String, dynamic> file) onDownload;
  @override
  State<_HfFilesSheet> createState() => _HfFilesSheetState();
}

class _HfFilesSheetState extends State<_HfFilesSheet> {
  List<Map<String, dynamic>>? _files;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.client
        .hfFiles(widget.repo)
        .then(
          (f) {
            if (mounted) setState(() => _files = f);
          },
          onError: (Object e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(widget.repo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Pick a file. Q4_K_M is a good balance of size and quality.', style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
          ),
          Expanded(
            child: _files == null
                ? (_error != null
                      ? EmptyState(icon: NurIcons.error, tone: NurColors.danger, title: 'Could not list files', body: _error)
                      : const SkeletonList(count: 6))
                : _files!.isEmpty
                ? const EmptyState(icon: NurIcons.file, title: 'No GGUF files in this repo')
                : ListView.builder(
                    itemCount: _files!.length,
                    itemBuilder: (c, i) {
                      final f = _files![i];
                      final fits = f['fits'] != false;
                      return ListTile(
                        title: Text('${f['file']}', style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                          fits ? formatBytes(f['size'] as num?) : '${formatBytes(f['size'] as num?)} · too big for this NAS',
                          style: TextStyle(color: fits ? context.nur.muted : NurColors.warn),
                        ),
                        leading: const IconTile(NurIcons.file, size: 34),
                        trailing: IconButton(tooltip: 'Download', icon: const Icon(NurIcons.download, size: 18), onPressed: () => widget.onDownload(f)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// llama.cpp and Ollama on the NAS: install, start and stop.
class _Runtimes extends StatefulWidget {
  const _Runtimes({required this.client});
  final NasHubClientImpl client;
  @override
  State<_Runtimes> createState() => _RuntimesState();
}

class _RuntimesState extends State<_Runtimes> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  final _busy = <String>{};
  final Map<String, Map<String, dynamic>> _jobs = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.runtimes();
      if (mounted) setState(() => (_items = r, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _act(String id, String action) async {
    if (action == 'stop' && !await confirmDialog(context, 'Stop this runtime?', 'Chats using NAS models will stop working until you start it again.', ok: 'Stop')) return;
    setState(() => _busy.add(id));
    try {
      final r = await widget.client.runtimeAction(id, action);
      final jobId = r['job_id'];
      if (jobId != null) {
        _jobs[id] = {'id': '$jobId', 'state': 'running', 'progress': 0.0};
        _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _pollJobs());
      }
      if (mounted) showSnack(context, '${r['message'] ?? 'Done'}');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
      await _load();
    }
  }

  Future<void> _pollJobs() async {
    for (final e in _jobs.entries.toList()) {
      try {
        final j = await widget.client.job('${e.value['id']}');
        _jobs[e.key] = {...j, 'id': e.value['id']};
        final st = '${j['state']}';
        if (st != 'running' && st != 'queued') {
          _jobs.remove(e.key);
          if (mounted) showSnack(context, st == 'done' ? 'Runtime installed' : 'Install failed: ${j['error'] ?? st}');
          unawaited(_load());
        }
      } catch (_) {}
    }
    if (_jobs.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return _error != null
          ? EmptyState(
              icon: NurIcons.error,
              tone: NurColors.danger,
              title: 'Could not load runtimes',
              body: _error,
              action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NurIcons.refresh), label: const Text('Try again')),
            )
          : const SkeletonList(cards: true, count: 2);
    }
    const titles = {'llamacpp': 'llama.cpp', 'ollama': 'Ollama'};
    const blurbs = {'llamacpp': 'Fastest on the Pi. Runs GGUF models from the models folder. Recommended.', 'ollama': 'Easy model library (ollama pull). Uses a bit more memory.'};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NurCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconTile(NurIcons.runtime, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(titles[r['id']] ?? '${r['id']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                        ),
                        StateChip(
                          r['running'] == true ? 'running' : (r['installed'] == true ? 'stopped' : 'not installed'),
                          color: r['running'] == true ? NurColors.ok : (r['installed'] == true ? NurColors.warn : null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(blurbs[r['id']] ?? '', style: TextStyle(color: context.nur.muted, fontSize: 13, height: 1.4)),
                    if (_jobs[r['id']] != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('Installing... ${(((_jobs[r['id']]!['progress'] as num?) ?? 0) * 100).toStringAsFixed(0)}%', style: TextStyle(color: context.nur.muted)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_busy.contains(r['id']))
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Wrap(
                        spacing: 8,
                        children: [
                          if (r['installed'] != true && _jobs[r['id']] == null) FilledButton(onPressed: () => _act('${r['id']}', 'install'), child: const Text('Install')),
                          if (r['installed'] == true && r['running'] != true) FilledButton(onPressed: () => _act('${r['id']}', 'start'), child: const Text('Start')),
                          if (r['running'] == true) OutlinedButton(onPressed: () => _act('${r['id']}', 'stop'), child: const Text('Stop')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

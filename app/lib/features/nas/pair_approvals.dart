// Shows "New device wants to connect" on apps that are already paired with the NAS, so new phones can join
// without a code or a screen on the NAS. Polls the hub every 6 s, only while the app is in the foreground.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/text_dir.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import 'nas_service.dart';

class PairApprovalListener extends ConsumerStatefulWidget {
  const PairApprovalListener({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  ConsumerState<PairApprovalListener> createState() => _PairApprovalListenerState();
}

class _PairApprovalListenerState extends ConsumerState<PairApprovalListener> with WidgetsBindingObserver {
  Timer? _timer;
  final _asked = <String>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _timer?.cancel();
    if (s == AppLifecycleState.resumed) _timer = Timer.periodic(const Duration(seconds: 6), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_showing) return;
    final hub = ref.read(activeNasProvider).value;
    if (hub == null) return;
    List<Map<String, dynamic>> pending;
    try {
      pending = await hub.pendingPairs();
    } catch (_) {
      return; // NAS offline or older hub: try again later
    }
    final next = pending.where((p) => !_asked.contains('${p['id']}')).firstOrNull;
    final ctx = widget.navigatorKey.currentContext;
    if (next == null || ctx == null || !ctx.mounted) return;
    final id = '${next['id']}';
    final name = '${next['device_name'] ?? 'A device'}';
    _asked.add(id);
    _showing = true;
    final ar = Localizations.localeOf(ctx).languageCode == 'ar';
    final approve = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          icon: const IconTile(NurIcons.pairDevice, size: 44),
          title: Text(ar ? 'جهاز جديد يريد الاتصال' : 'New device wants to connect'),
          content: Text(
            ar
                ? '"$name" يطلب الوصول إلى جهاز NAS الخاص بك. وافق فقط إذا كان هذا جهازك أو جهاز شخص تثق به.'
                : '"$name" is asking to use your NAS. Approve only if it is your device or someone you trust.',
            textDirection: textDirOf(name) == TextDirection.rtl || ar ? TextDirection.rtl : TextDirection.ltr,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(ar ? 'رفض' : 'Deny')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ar ? 'موافقة' : 'Approve')),
          ],
        ),
      ),
    );
    _showing = false;
    try {
      await hub.decidePair(id, approve: approve ?? false);
    } catch (e) {
      final m = widget.navigatorKey.currentContext;
      if (m != null && m.mounted) showNurToast(m, 'Could not answer the request: $e', kind: NurToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

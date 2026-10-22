// Pairing with Nur Hub: a welcome page, a search for hubs on the network, tap one, done. There are no codes: the
// first device becomes the owner and later devices wait until an already connected Nur app approves them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/nur_theme.dart';
import '../../core/widgets/nur_icons.dart';
import '../../core/widgets/nur_ui.dart';
import '../../core/widgets/nur_logo.dart';
import 'nas_hub_client.dart';
import 'nas_service.dart';
import 'nas_widgets.dart';

enum _Step { welcome, searching, waiting, done }

const _strings = {
  'en': {
    'welcome': 'Welcome to Nur',
    'tagline': 'Your private AI, running on your own NAS.',
    'start': 'Get started',
    'skip': 'Use cloud models without a NAS',
    'looking': 'Looking for your NAS...',
    'looking_sub': 'Make sure your phone and the NAS are on the same Wi-Fi.',
    'found': 'Tap your NAS',
    'none': 'No NAS found yet.',
    'manual': 'Enter the address manually',
    'retry': 'Search again',
    'wait_title': 'Waiting for approval',
    'wait_sub': 'This NAS already has an owner. Open Nur on a phone that is already connected to it and tap Approve.',
    'denied': 'The request was declined on the other device.',
    'expired': 'The request expired. Tap your NAS to try again.',
    'connect': 'Connect',
    'done': 'You\'re all set',
    'done_sub': 'Nur is connected to your NAS.',
    'model': 'Default model',
    'no_model': 'No model on the NAS yet. Download one in the NAS screen.',
    'open': 'Start chatting',
    'manage': 'Manage models',
    'address': 'NAS address (for example 192.168.1.50)',
    'cancel': 'Cancel',
  },
  'ar': {
    'welcome': 'أهلاً بك في نور',
    'tagline': 'ذكاؤك الاصطناعي الخاص، يعمل على جهاز NAS الخاص بك.',
    'start': 'ابدأ',
    'skip': 'استخدم النماذج السحابية بدون NAS',
    'looking': 'جارٍ البحث عن جهاز NAS...',
    'looking_sub': 'تأكد أن هاتفك وجهاز NAS على نفس شبكة الواي فاي.',
    'found': 'اضغط على جهازك',
    'none': 'لم يتم العثور على جهاز بعد.',
    'manual': 'أدخل العنوان يدوياً',
    'retry': 'ابحث مرة أخرى',
    'wait_title': 'بانتظار الموافقة',
    'wait_sub': 'لهذا الجهاز مالك بالفعل. افتح تطبيق نور على هاتف متصل به واضغط "موافقة".',
    'denied': 'تم رفض الطلب من الجهاز الآخر.',
    'expired': 'انتهت صلاحية الطلب. اضغط على جهازك للمحاولة مجدداً.',
    'connect': 'اتصال',
    'done': 'كل شيء جاهز',
    'done_sub': 'نور متصل الآن بجهاز NAS الخاص بك.',
    'model': 'النموذج الافتراضي',
    'no_model': 'لا يوجد نموذج على الجهاز بعد. حمّل واحداً من شاشة NAS.',
    'open': 'ابدأ المحادثة',
    'manage': 'إدارة النماذج',
    'address': 'عنوان الجهاز (مثلاً 192.168.1.50)',
    'cancel': 'إلغاء',
  },
};

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  final List<DiscoveredHub> _hubs = [];
  StreamSubscription<DiscoveredHub>? _sub;
  bool _searching = false;
  DiscoveredHub? _selected;
  Timer? _poll;
  bool _busy = false;
  String? _error;
  String? _defaultModel;

  /// The app locale follows the `locale` setting (see app.dart), so the toggle below re-renders this screen.
  String _lang(BuildContext context) => Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';

  String t(BuildContext context, String k) => _strings[_lang(context)]![k] ?? k;

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _search() {
    _sub?.cancel();
    setState(() {
      _step = _Step.searching;
      _hubs.clear();
      _searching = true;
      _error = null;
    });
    _sub = discoverHubs().listen(
      (h) {
        if (mounted) setState(() => _hubs.add(h));
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  Future<void> _choose(DiscoveredHub hub) async {
    setState(() => (_busy = true, _error = null, _selected = hub));
    final info = hub.info.isEmpty ? null : hub.info;
    try {
      final notifier = ref.read(activeNasProvider.notifier);
      final r = await notifier.requestPair(hub.baseUrl, info: info);
      if (r.approved) return _finish();
      if (mounted) setState(() => _step = _Step.waiting);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final status = await notifier.checkPair(hub.baseUrl, r.requestId!, info: info);
          if (status == 'pending') return;
          _poll?.cancel();
          if (status == 'approved') return _finish();
          if (mounted) setState(() => (_step = _Step.searching, _error = t(context, status == 'denied' ? 'denied' : 'expired')));
        } catch (_) {/* keep waiting; the network may blink */}
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    _defaultModel = await ref.read(activeNasProvider.notifier).chooseDefaultModel();
    if (mounted) setState(() => _step = _Step.done);
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t(context, 'manual')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: t(context, 'address')),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t(context, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(t(context, 'connect'))),
        ],
      ),
    );
    ctrl.dispose();
    if (addr == null || addr.trim().isEmpty) return;
    final base = normalizeHubUrl(addr);
    setState(() => (_busy = true, _error = null));
    try {
      final info = await NasHubClientImpl.fetchInfo(base);
      if (!mounted) return;
      final hub = DiscoveredHub(name: '${info['name'] ?? 'NAS'}', baseUrl: base, info: info);
      if (!_hubs.any((h) => h.baseUrl == base)) setState(() => _hubs.add(hub));
      await _choose(hub);
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _busy = false));
    }
  }

  void _skip() => context.go('/settings/providers');

  @override
  Widget build(BuildContext context) {
    final lang = _lang(context);
    return Directionality(
      textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(key: ValueKey(_step), child: _body(context, lang)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String lang) {
    final muted = TextStyle(color: context.nur.muted, fontSize: 15, height: 1.4);
    switch (_step) {
      case _Step.welcome:
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'ar', label: Text('عربي'))],
                selected: {lang},
                onSelectionChanged: (v) => ref.read(dbProvider).setSetting('locale', v.first),
              ),
            ),
            const Spacer(),
            const NurLogo(size: 84),
            const SizedBox(height: 28),
            Text(t(context, 'welcome'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 10),
            Text(t(context, 'tagline'), textAlign: TextAlign.center, style: muted),
            const Spacer(),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _search, child: Text(t(context, 'start')))),
            const SizedBox(height: 10),
            TextButton(onPressed: _skip, child: Text(t(context, 'skip'), textAlign: TextAlign.center)),
          ]),
        );
      case _Step.searching:
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: AlignmentDirectional.centerStart, child: IconButton(tooltip: 'Back', onPressed: () => setState(() => _step = _Step.welcome), icon: const BackButtonIcon())),
            const SizedBox(height: 12),
            Text(_hubs.isEmpty ? t(context, 'looking') : t(context, 'found'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(t(context, 'looking_sub'), style: muted),
            const SizedBox(height: 24),
            if (_searching && _hubs.isEmpty) const Center(child: _Pulse()),
            for (final h in _hubs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NurCard(
                  onTap: _busy ? null : () => _choose(h),
                  child: Row(children: [
                    const IconTile(NurIcons.nas, size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(h.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text('${h.info['model'] ?? Uri.parse(h.baseUrl).host}', style: TextStyle(color: context.nur.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    if (_busy && _selected == h)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(NurIcons.chevron, size: 18, color: context.nur.subtle),
                  ]),
                ),
              ),
            if (!_searching && _hubs.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(t(context, 'none'), style: muted)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: NurColors.danger))),
            const Spacer(),
            if (!_searching) OutlinedButton(onPressed: _search, child: Text(t(context, 'retry'))),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _manual, child: Text(t(context, 'manual'))),
            TextButton(onPressed: _skip, child: Text(t(context, 'skip'), textAlign: TextAlign.center)),
          ]),
        );
      case _Step.waiting:
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            const _Pulse(),
            const SizedBox(height: 24),
            Text(t(context, 'wait_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(t(context, 'wait_sub'), textAlign: TextAlign.center, style: muted),
            const Spacer(),
            TextButton(
              onPressed: () {
                _poll?.cancel();
                setState(() => _step = _Step.searching);
              },
              child: Text(t(context, 'cancel')),
            ),
          ]),
        );
      case _Step.done:
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: NurColors.ok.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: const Icon(NurIcons.check, size: 40, color: NurColors.ok),
            ),
            const SizedBox(height: 24),
            Text(t(context, 'done'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(t(context, 'done_sub'), textAlign: TextAlign.center, style: muted),
            const SizedBox(height: 20),
            NurCard(
              child: Row(children: [
                const IconTile(NurIcons.localModel, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(context, 'model'), style: TextStyle(color: context.nur.muted, fontSize: 12.5)),
                    Text(_defaultModel?.split('::').last ?? t(context, 'no_model'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
            const Spacer(),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => context.go('/'), child: Text(t(context, 'open')))),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/nas'), child: Text(t(context, 'manage'))),
          ]),
        );
    }
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return RepaintBoundary(
      child: SizedBox(
        width: 160,
        height: 160,
        child: AnimatedBuilder(
          animation: _c,
          builder: (c, _) => CustomPaint(painter: _PulsePainter(_c.value, color), child: const Center(child: Icon(NurIcons.nas, size: 32))),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
          c,
          30 + p * 50,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: (1 - p) * 0.5));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

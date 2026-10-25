// What Nur needs before a chat can open: a paired Nur Hub that answers right now, llama.cpp installed and running
// on it, and at least one model in its models folder. Read live from the hub's /api/v1/info, never cached or guessed:
// when the hub does not answer, the status says so.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nas/nas_service.dart';

enum SetupStep { checking, pair, unreachable, installLlama, startLlama, downloadModel, warming, ready }

@immutable
class SetupStatus {
  final SetupStep step;
  final String? hubName;
  final String? hubUrl;
  final int ram;
  final String? error;
  const SetupStatus(this.step, {this.hubName, this.hubUrl, this.ram = 0, this.error});
  bool get ready => step == SetupStep.ready;

  /// The step from a hub's /api/v1/info answer.
  static SetupStep stepFromInfo(Map<String, dynamic> info) {
    final s = info['setup'];
    if (s is! Map) return SetupStep.installLlama; // a hub older than 1.2.0 cannot tell, so ask to update it
    if (s['llamacpp_installed'] != true) return SetupStep.installLlama;
    if (s['llamacpp_running'] != true) return SetupStep.startLlama;
    if ((s['models'] as num? ?? 0) <= 0) return SetupStep.downloadModel;
    if (s['warming'] == true) return SetupStep.warming;
    return SetupStep.ready;
  }

  @override
  bool operator ==(Object other) =>
      other is SetupStatus && other.step == step && other.hubName == hubName && other.hubUrl == hubUrl && other.error == error;
  @override
  int get hashCode => Object.hash(step, hubName, hubUrl, error);
}

class SetupStatusNotifier extends Notifier<SetupStatus> {
  Timer? _timer;
  bool _busy = false;
  int _holds = 0;

  /// Keeps the setup screen on "preparing" while [work] runs (the app's own first warm-up after a download), so
  /// the chat opens only once the model has already read Nur's system text.
  Future<void> holdWhile(Future<void> work) async {
    _holds++;
    try {
      await work.timeout(const Duration(minutes: 3));
    } catch (_) {
      // Best effort: a cold first chat is only slower.
    } finally {
      _holds--;
      await refresh();
    }
  }

  @override
  SetupStatus build() {
    ref.listen(activeNasProvider, (_, _) => refresh());
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    Future.microtask(refresh);
    return const SetupStatus(SetupStep.checking);
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final nas = ref.read(activeNasProvider);
      if (nas.isLoading) return;
      final client = nas.value;
      if (client == null) {
        state = const SetupStatus(SetupStep.pair);
        return;
      }
      final d = client.device!;
      try {
        final info = await client.info().timeout(const Duration(seconds: 5));
        var step = SetupStatus.stepFromInfo(info);
        if (step == SetupStep.ready && _holds > 0) step = SetupStep.warming;
        state = SetupStatus(step, hubName: d.name, hubUrl: d.baseUrl, ram: (info['ram'] as num?)?.toInt() ?? 0);
      } catch (e) {
        state = SetupStatus(SetupStep.unreachable, hubName: d.name, hubUrl: d.baseUrl, error: '$e');
      }
    } finally {
      _busy = false;
    }
  }
}

final setupStatusProvider = NotifierProvider<SetupStatusNotifier, SetupStatus>(SetupStatusNotifier.new);

// Keeps background model calls (chat titles, memory extraction, automatic summaries) out of the way of replies the
// user is waiting for. A llama.cpp server on a Pi works on one request at a time, so a background request that is
// running delays the next reply by its whole length.
//
// Foreground work (one chat reply, or a whole voice call) holds a lease. While any lease is held, background calls
// wait, and the ones already running are cancelled when a lease is taken.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/llm.dart';

/// Thrown by a background call that a foreground lease stopped.
class BackgroundCancelled implements Exception {
  const BackgroundCancelled();
  @override
  String toString() => 'Stopped to make room for a reply.';
}

/// A hold on the [ForegroundGate]. Release it when the foreground work ends; releasing again does nothing.
class ForegroundLease {
  ForegroundLease._(this._gate);
  final ForegroundGate _gate;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _gate._release();
  }
}

class ForegroundGate {
  int _holds = 0;
  Completer<void>? _free;
  final _running = <LlmCancelToken>{};

  /// True while a reply or a voice call holds the gate.
  bool get isHeld => _holds > 0;

  /// Background calls running right now.
  int get runningBackground => _running.length;

  /// Holds the gate until the lease is released: running background calls are cancelled, new ones wait.
  ForegroundLease hold() {
    _holds++;
    _free ??= Completer<void>();
    for (final t in _running.toList()) {
      t.cancel();
    }
    return ForegroundLease._(this);
  }

  void _release() {
    if (_holds == 0) return;
    _holds--;
    if (_holds > 0) return;
    final f = _free;
    _free = null;
    f?.complete();
  }

  /// Completes when no lease is held.
  Future<void> whenFree() async {
    while (_free != null) {
      await _free!.future;
    }
  }

  /// Runs background model work: waits until the gate is free, then runs [task] with a token that the next lease
  /// cancels. Throws [BackgroundCancelled] when that happens.
  Future<T> background<T>(Future<T> Function(LlmCancelToken cancel) task) async {
    await whenFree();
    final token = LlmCancelToken();
    _running.add(token);
    try {
      final out = await task(token);
      if (token.isCancelled) throw const BackgroundCancelled();
      return out;
    } catch (e) {
      if (token.isCancelled) throw const BackgroundCancelled();
      rethrow;
    } finally {
      _running.remove(token);
    }
  }
}

final foregroundGateProvider = Provider<ForegroundGate>((ref) => ForegroundGate());

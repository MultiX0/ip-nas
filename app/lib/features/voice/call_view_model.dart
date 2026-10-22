// What the call screen and its widgets read from a voice call (implemented by VoiceCallController).
import 'package:flutter/foundation.dart';

enum CallPhase { connecting, listening, thinking, speaking, ended }

enum ToolKind { nas, web, memory, generic }

abstract class CallViewModel implements Listenable {
  CallPhase get phase;

  /// What the user said last (ASR transcript).
  String get userCaption;

  /// Nur's reply as plain text (directions stripped).
  String get assistantCaption;

  /// How many words of [assistantCaption] have been spoken so far (polled each frame).
  int get revealedWords;

  /// Caption of a running tool ("Checking the NAS..."), null when none.
  String? get tool;
  ToolKind? get toolKind;

  /// A short notice (a recoverable problem, e.g. a TTS hiccup).
  String? get status;

  /// A blocking error (the call cannot continue without the user acting).
  String? get error;
  bool get errorNeedsSettings;
  bool get errorNeedsPermission;

  bool get muted;

  /// Live mic level while listening, 0..1 (polled each frame).
  double get micLevel;

  /// Live output level of Nur's voice, 0..1 (polled each frame).
  double get outLevel;

  /// Time to first audio of the last turn (debug HUD), null when unknown.
  int? get lastTtfaMs;

  void setMuted(bool v);

  /// Barge-in from the UI.
  void interrupt();
}

ToolKind toolKindFor(String tool) {
  final t = tool.toLowerCase();
  // Memory first: memory_search is not a web search.
  if (t.contains('memory') || t.contains('remember')) return ToolKind.memory;
  if (t.contains('search') || t.contains('web')) return ToolKind.web;
  if (t.contains('nas') || t.contains('docker') || t.contains('system') || t.contains('exec') || t.contains('container') || t.contains('disk')) {
    return ToolKind.nas;
  }
  return ToolKind.generic;
}

String toolCaptionFor(ToolKind k) => switch (k) {
  ToolKind.web => 'Searching the web...',
  ToolKind.memory => 'Checking my memory...',
  ToolKind.nas => 'Checking the NAS...',
  ToolKind.generic => 'Working on it...',
};

/// Number of words in a caption (shared by the reveal logic and the caption widget).
int captionWordCount(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0;
  return t.split(_ws).length;
}

final _ws = RegExp(r'\s+');

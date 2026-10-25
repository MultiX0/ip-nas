// Contract used by voice (features/voice) and anything else that needs to talk to the current chat.
// Implemented by features/chat.
import 'llm.dart';

class UserInput {
  final String text;
  final List<LlmImage> images;
  final String? audioPath; // voice message recording kept with the message
  final bool fromVoiceCall; // voice calls ask the model for short, speakable answers
  const UserInput(this.text, {this.images = const [], this.audioPath, this.fromVoiceCall = false});
}

/// Live events of one assistant reply as the user sees it (text only, tools already handled).
sealed class ReplyEvent {
  const ReplyEvent();
}

class ReplyText extends ReplyEvent {
  final String delta;
  const ReplyText(this.delta);
}

class ReplyToolActivity extends ReplyEvent {
  final String toolName; // e.g. "docker_list" - voice UI can say "checking the NAS..."
  const ReplyToolActivity(this.toolName);
}

class ReplyDone extends ReplyEvent {
  final String fullText;
  const ReplyDone(this.fullText);
}

class ReplyError extends ReplyEvent {
  final String message;
  const ReplyError(this.message);
}

abstract class ChatEngine {
  /// Creates a chat if [chatId] is null. Returns the chat id via [onChatId].
  Stream<ReplyEvent> send(String? chatId, UserInput input, {void Function(String chatId)? onChatId});
  void stop(String chatId);

  /// Warms the model for an upcoming turn (call screen opened, composer focused): a 1-token request fills the
  /// llama.cpp prompt cache with the stable prefix, so the real turn only reads the new text. Never throws.
  Future<void> prewarm(String? chatId, {bool fromVoiceCall = false}) async {}
}

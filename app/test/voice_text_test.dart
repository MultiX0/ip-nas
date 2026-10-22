import 'package:flutter_test/flutter_test.dart';
import 'package:nur/features/voice/call_view_model.dart';
import 'package:nur/features/voice/fish_audio.dart';
import 'package:nur/features/voice/speech_text.dart';

List<String> _split(List<String> deltas) {
  final s = SentenceSplitter();
  return [for (final d in deltas) ...s.add(d), ...s.close()];
}

void main() {
  group('markdownToSpeech', () {
    test('drops markdown syntax, links and URLs', () {
      const md = '# Status\n\n**CPU** is at `51` degrees. See [the docs](https://example.com).\n\n- one\n- two';
      expect(markdownToSpeech(md), 'Status. CPU is at 51 degrees. See the docs. one two');
      expect(markdownToSpeech('Open https://example.com/page now'), 'Open now');
    });

    test('drops emoji, which a small model adds even when told not to', () {
      expect(markdownToSpeech('Two plus two equals four! That is simple. 🍎🍌🍇'), 'Two plus two equals four! That is simple.');
      expect(markdownToSpeech('Done 👍🏽, all good 🇯🇴. Press 1️⃣.'), 'Done, all good. Press 1.');
      expect(markdownToSpeech('جهازك بخير 😊'), 'جهازك بخير');
    });

    test('a paragraph break adds no second mark after a question or a tag', () {
      expect(markdownToSpeech('Want me to look it up?\n\nI found a cool fact!'), 'Want me to look it up? I found a cool fact!');
      expect(markdownToSpeech('Here is what I found:\n\nThe moon is far.'), 'Here is what I found: The moon is far.');
      expect(markdownToSpeech('[cheerfully]\n\nThe moon is far.', keepDirections: false), 'The moon is far.');
      expect(markdownToSpeech('هل تريد المزيد؟\n\nالقمر بعيد.'), 'هل تريد المزيد؟ القمر بعيد.');
    });

    test('skips code blocks', () {
      expect(markdownToSpeech('Here:\n```dart\nprint(1);\n```\nDone.'), 'Here: Done.');
    });

    test('keeps Drama 3 directions for the voice, drops them for captions', () {
      const reply = '[warmly] **Done!** Jellyfin is running again.';
      expect(markdownToSpeech(reply), '[warmly] Done! Jellyfin is running again.');
      expect(markdownToSpeech(reply, keepDirections: false), 'Done! Jellyfin is running again.');
    });
  });

  test('stripDirections removes tags and the double spaces they leave', () {
    expect(stripDirections('[warmly] Hello <emphasis>there</emphasis>, friend.'), 'Hello there, friend.');
    expect(stripDirections('Drive two is 90 percent full. [short pause] Want me to check?'), 'Drive two is 90 percent full. Want me to check?');
  });

  test('cleanTranscript removes speaker markers and extra whitespace', () {
    expect(cleanTranscript('<|speaker:0|>hello   there\n'), 'hello there');
  });

  group('SentenceSplitter', () {
    test('returns whole sentences as the reply streams in', () {
      expect(_split(['Hello the', 're. How are', ' you? Fine']), ['Hello there.', 'How are you?', 'Fine']);
    });

    test('splits on Arabic punctuation', () {
      expect(_split(['مرحبا، كيف حالك؟ أنا بخير. ']), ['مرحبا، كيف حالك؟', 'أنا بخير.']);
    });

    test('never speaks code inside fences', () {
      expect(_split(['Run this:\n```bash\nls -la\n```\nDone. ']), ['Run this:', 'Done.']);
    });

    test('a direction on its own line goes with the next sentence', () {
      // Sent alone, Drama 3 turns "[cheerfully]" into a laugh before the answer.
      expect(_split(['[cheerfully]\n', 'Done! Jellyfin is running again.']), ['[cheerfully] Done!', 'Jellyfin is running again.']);
      expect(_split(['[calmly]\n[short pause]\nAll good. ']), ['[calmly] [short pause] All good.']);
      expect(_split(['That was fun. [small laugh]']), ['That was fun.', '[small laugh]']);
    });

    test('sends the first clause early at a comma', () {
      final s = SentenceSplitter();
      expect(s.add('The NAS is healthy and running well, the CPU is at 51 degrees'), ['The NAS is healthy and running well,']);
      expect(s.close(), ['the CPU is at 51 degrees']);
    });
  });

  test('captionWordCount', () {
    expect(captionWordCount('  hello   big world '), 3);
    expect(captionWordCount(''), 0);
  });

  test('toolKindFor picks the call caption for each tool', () {
    expect(toolKindFor('web_search'), ToolKind.web);
    expect(toolKindFor('memory_search'), ToolKind.memory);
    expect(toolKindFor('memory_save'), ToolKind.memory);
    expect(toolKindFor('nas_system_status'), ToolKind.nas);
    expect(toolKindFor('docker_action'), ToolKind.nas);
    expect(toolKindFor('load_skill'), ToolKind.generic);
  });

  test('FishException.messageFor turns status codes into plain words', () {
    expect(FishException.messageFor(401), contains('rejected the API key'));
    expect(FishException.messageFor(402), contains('out of credits'));
    expect(FishException.messageFor(503), 'Fish Audio is having trouble right now (503). Try again shortly.');
    expect(FishException.messageFor(418), 'Fish Audio request failed (418).');
    expect(FishException.messageFor(null, 'No such voice'), 'No such voice');
  });

  test('FishVoice.fromJson reads the voice library format', () {
    final v = FishVoice.fromJson({
      '_id': 'abc',
      'title': 'Nora',
      'languages': ['ar', 'en'],
      'cover_image': 'coverimage/abc',
      'samples': [
        {'audio': 'https://example.com/a.mp3'},
      ],
      'author': {'nickname': 'someone'},
    });
    expect(v.id, 'abc');
    expect(v.languages, ['ar', 'en']);
    expect(v.cover, 'https://public-platform.r2.fish.audio/coverimage/abc');
    expect(v.sampleUrl, 'https://example.com/a.mp3');
    expect(v.author, 'someone');
  });
}

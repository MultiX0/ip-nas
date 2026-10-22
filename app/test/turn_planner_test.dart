import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/chat/engine/chat_engine_impl.dart' show cleanTitle;
import 'package:nur/features/chat/engine/request_shaping.dart';
import 'package:nur/features/context/prompts.dart';
import 'package:nur/features/context/turn_planner.dart';
import 'package:nur/features/tools/tool_formatters.dart';

Map<String, dynamic> _hub({required List<Map<String, dynamic>> disks}) => {
      'cpu': 4.5,
      'ram_used': 1158643712,
      'ram_total': 4245766144,
      'temp': 47.2,
      'uptime': 40089,
      'disks': disks,
    };

const _drives = [
  {'name': 'mmcblk0p2', 'mount': '/', 'used': 11764473856, 'total': 122510082048},
  {'name': 'mmcblk0p1', 'mount': '/boot/firmware', 'used': 78443008, 'total': 528592896},
  {'name': 'sda1', 'mount': '/DATA/HDD1', 'used': 100000000000, 'total': 315000000000},
  {'name': 'sdb1', 'mount': '/media/devmon/HDD2', 'used': 20000000000, 'total': 158000000000},
];

void main() {
  group('disks in status answers', () {
    test('every data drive is reported, the boot partition is not', () {
      final text = formatSystemStatus(systemValues(_hub(disks: _drives)));
      final summary = text.split('\n').first;
      expect(summary, contains('system disk 10% used'));
      expect(summary, contains('HDD1 32% used'));
      expect(summary, contains('HDD2 13% used'));
      expect(summary, isNot(contains('firmware')));
    });

    test('the template answer names the drives by their label', () {
      final values = systemValues(_hub(disks: _drives));
      final en = statusAnswer(values, {'disk'}, 'en');
      expect(en, contains('HDD1: 32% used'));
      expect(en, contains('HDD2: 13% used'));
      expect(en, isNot(contains('/boot')));
      final ar = statusAnswer(values, {'disk'}, 'ar');
      expect(ar, contains('HDD1: 32%'));
      expect(ar, matches(RegExp(r'متاحة من [\d.]+ جيجابايت\)')), reason: 'the total has its unit too');
    });

    test('labels', () {
      expect(diskLabel('/'), 'system disk');
      expect(diskLabel('/mnt/hdd1'), 'hdd1');
      expect(diskLabel('/DATA/HDD2'), 'HDD2');
      expect(reportedDisk('/boot/firmware'), isFalse);
      expect(reportedDisk('/media/devmon/HDD1'), isTrue);
    });
  });

  test('a failed planned tool gets a plain reply in the language of the message', () {
    expect(toolFailedReply('nas_system_status', 'Tool failed: Cannot reach the NAS', 'en'), "I couldn't check the NAS: Cannot reach the NAS.");
    expect(toolFailedReply('docker_list', 'Tool failed: Nur Hub has no access to Docker.', 'en'),
        "I couldn't get the list of apps from the NAS: Nur Hub has no access to Docker.");
    expect(toolFailedReply('docker_logs', 'The NAS answered with HTTP 503: Nur Hub has no access to Docker.', 'en'),
        "I couldn't read the app's logs from the NAS: The NAS answered with HTTP 503: Nur Hub has no access to Docker.");
    expect(toolFailedReply('web_search', '', 'ar'), 'لم أتمكن من البحث في الإنترنت.');
  });

  test('spoken failure replies leave the technical detail to the chat', () {
    const e = "SearXNG refused JSON output. Add 'json' to search.formats in its settings.yml";
    expect(toolFailedReply('web_search', e, 'ar', voice: true), 'لم أتمكن من البحث في الإنترنت. التفاصيل مكتوبة في المحادثة.');
    expect(toolFailedReply('web_search', e, 'en', voice: true), "I couldn't search the web. The details are in the chat.");
  });

  group('advice questions are not live status questions', () {
    test('Arabic', () {
      for (final q in ['ما هي أفضل طريقة لتبريد الراسبيري باي؟', 'كيف أخفض حرارة الجهاز؟', 'هل تنصح بتبريد إضافي للجهاز؟']) {
        final p = planTurn(q);
        expect(p.intent, TurnIntent.chat, reason: q);
        expect(p.calls, isEmpty, reason: q);
      }
    });

    test('English', () {
      for (final q in ['What is the best way to cool my Raspberry Pi?', 'How can I lower the temperature of my NAS?']) {
        expect(planTurn(q).intent, TurnIntent.chat, reason: q);
      }
    });

    test('questions about the current values still read the NAS', () {
      for (final q in ['كم حرارة الجهاز؟', 'كيف الحرارة؟', 'ما هي حرارة المعالج؟', 'How hot is my NAS?']) {
        expect(planTurn(q).intent, TurnIntent.nasStatus, reason: q);
      }
    });
  });

  group('explicit language requests', () {
    test('are recognised in English and Arabic', () {
      expect(asksForLanguage('Say hello in Arabic.'), isTrue);
      expect(asksForLanguage('Translate this to English: shukran'), isTrue);
      expect(asksForLanguage('اكتب لي رسالة بالإنجليزي'), isTrue);
      expect(asksForLanguage('ترجم هذه الجملة'), isTrue);
      expect(asksForLanguage('How is my NAS?'), isFalse);
      expect(asksForLanguage('كيف حال الجهاز؟'), isFalse);
    });

    test('get no language lock', () {
      expect(languageDirective('Say hello in Arabic.'), '');
      expect(languageDirective('How are you?'), '(Reply in English only.)');
      final shaped = shapeMessages([
        const LlmMessage(LlmRole.system, 'sys'),
        const LlmMessage(LlmRole.user, 'Say hello in Arabic.'),
      ], vision: false, small: true);
      expect(shaped.last.content, 'Say hello in Arabic.');
    });
  });

  test('small models get the error note on failed tool results only', () {
    final shaped = shapeMessages([
      const LlmMessage(LlmRole.system, 'sys'),
      const LlmMessage(LlmRole.user, 'How is my NAS?'),
      const LlmMessage(LlmRole.assistant, '', toolCalls: [LlmToolCall(id: 'a', name: 'nas_system_status', argumentsJson: '{}')]),
      const LlmMessage(LlmRole.tool, 'Tool failed: Cannot reach the NAS.', toolCallId: 'a', toolName: 'nas_system_status', isError: true),
      const LlmMessage(LlmRole.assistant, '', toolCalls: [LlmToolCall(id: 'b', name: 'docker_list', argumentsJson: '{}')]),
      const LlmMessage(LlmRole.tool, 'SUMMARY: 3 apps', toolCallId: 'b', toolName: 'docker_list'),
    ], vision: false, small: true);
    final tools = shaped.where((m) => m.role == LlmRole.tool).toList();
    expect(tools[0].content, endsWith(smallModelErrorNote));
    expect(tools[0].isError, isTrue);
    expect(tools[1].content, endsWith(smallModelAnswerNote));
  });

  test('titles lose straight, curly and angle quotes', () {
    expect(cleanTitle('\u201CNAS health check\u201D', 'How is my NAS?'), 'NAS health check');
    expect(cleanTitle('\u00ABحالة الجهاز\u00BB', 'كيف حال الجهاز؟'), 'حالة الجهاز');
    expect(cleanTitle('Title: "RAM usage".', 'How much RAM is free?'), 'RAM usage');
  });

  test('small talk wrapped in curly quotes or an ellipsis is still small talk', () {
    expect(planTurn('\u201Cthanks!\u201D').intent, TurnIntent.thanks);
    expect(planTurn('ok\u2026').intent, TurnIntent.ack);
  });
}

// A model server that stops in the middle of a reply (llama-server killed, connection dropped) has to show up as
// an error with the text so far, not as a finished answer. Live: the reply "Here is the story: A robot named Leo
// loved gadgets but" was saved and spoken as complete.
import 'dart:convert';
import 'dart:io' show HttpException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/core/contracts/llm.dart';
import 'package:nur/features/providers/adapters/anthropic_client.dart';
import 'package:nur/features/providers/adapters/openai_compat_client.dart';

import 'helpers/chat_fakes.dart';

/// Answers every request with [chunks] and then closes the stream, like a server that stops.
class _Canned implements HttpClientAdapter {
  _Canned(this.chunks);
  final List<String> chunks;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody(Stream.fromIterable([for (final c in chunks) Uint8List.fromList(utf8.encode(c))]), 200,
          headers: {Headers.contentTypeHeader: ['text/event-stream']});

  @override
  void close({bool force = false}) {}
}

/// Sends [chunks], then drops the connection, like a proxy whose model server died.
class _Dropped implements HttpClientAdapter {
  _Dropped(this.chunks);
  final List<String> chunks;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Stream<Uint8List> body() async* {
      for (final c in chunks) {
        yield Uint8List.fromList(utf8.encode(c));
      }
      throw const HttpException('Connection closed while receiving data');
    }

    return ResponseBody(body(), 200, headers: {Headers.contentTypeHeader: ['text/event-stream']});
  }

  @override
  void close({bool force = false}) {}
}

const _story = 'Here is the story: A robot named Leo loved gadgets but';

Future<List<LlmEvent>> _run(LlmClient c) =>
    c.chat(const LlmRequest(modelId: 'qwen3.5-2b', messages: [LlmMessage(LlmRole.user, 'Tell me a story.')])).toList();

String _text(List<LlmEvent> e) => e.whereType<TextDelta>().map((d) => d.text).join();

void _expectCutOff(List<LlmEvent> ev) {
  expect(_text(ev), _story, reason: 'the text so far is kept');
  expect(ev.last, isA<ErrorEvent>());
  expect((ev.last as ErrorEvent).message, contains('stopped before it was complete'));
  expect(ev.whereType<DoneEvent>(), isEmpty);
  expect(ev.whereType<ToolCallEvent>(), isEmpty);
}

void main() {
  group('OpenAI-compatible (llama.cpp)', () {
    OpenAiCompatClient client(List<String> chunks) =>
        OpenAiCompatClient(providerId: 'local', baseUrl: 'http://192.168.1.50:8080/v1', preset: 'llamacpp')..dio.httpClientAdapter = _Canned(chunks);
    String data(Map<String, dynamic> j) => 'data: ${jsonEncode(j)}\n\n';
    Map<String, dynamic> delta(Map<String, dynamic> d, [String? finish]) => {
          'choices': [
            {'index': 0, 'delta': d, 'finish_reason': finish}
          ]
        };

    test('no finish_reason and no [DONE]: an error that keeps the text', () async {
      _expectCutOff(await _run(client([data(delta({'content': 'Here is the story: '})), data(delta({'content': 'A robot named Leo loved gadgets but'}))])));
    });

    test('a connection that drops mid-reply gives the same error, not "Unexpected error: HttpException"', () async {
      final c = OpenAiCompatClient(providerId: 'nas', baseUrl: 'http://192.168.1.50:8770/llm/v1', preset: 'nas')
        ..dio.httpClientAdapter = _Dropped([data(delta({'content': _story}))]);
      _expectCutOff(await _run(c));
    });

    test('a tool call cut in half is dropped', () async {
      final ev = await _run(client([
        data(delta({'content': _story})),
        data(delta({
          'tool_calls': [
            {'index': 0, 'id': 'c1', 'function': {'name': 'web_search', 'arguments': '{"que'}}
          ]
        })),
      ]));
      _expectCutOff(ev);
    });

    test('a normal end is not an error', () async {
      final ev = await _run(client([data(delta({'content': _story})), data(delta({}, 'stop')), 'data: [DONE]\n\n']));
      expect(ev.whereType<ErrorEvent>(), isEmpty);
      expect((ev.last as DoneEvent).finishReason, 'stop');
    });

    test('[DONE] without a finish_reason, or a finish_reason without [DONE], is a normal end', () async {
      final a = await _run(client([data(delta({'content': _story})), 'data: [DONE]\n\n']));
      expect(a.whereType<ErrorEvent>(), isEmpty);
      final b = await _run(client([data(delta({'content': _story})), data(delta({}, 'length'))]));
      expect(b.whereType<ErrorEvent>(), isEmpty);
      expect((b.last as DoneEvent).finishReason, 'length');
    });
  });

  group('Anthropic', () {
    AnthropicClient client(List<String> events) =>
        AnthropicClient(providerId: 'anthropic', apiKey: 'your-key-here')..dio.httpClientAdapter = _Canned(events);
    String ev(String type, [Map<String, dynamic> j = const {}]) => 'event: $type\ndata: ${jsonEncode({'type': type, ...j})}\n\n';
    final start = [
      ev('message_start', {
        'message': {'usage': {'input_tokens': 10, 'output_tokens': 1}}
      }),
      ev('content_block_start', {'index': 0, 'content_block': {'type': 'text', 'text': ''}}),
      ev('content_block_delta', {'index': 0, 'delta': {'type': 'text_delta', 'text': _story}}),
    ];

    test('no stop reason and no message_stop: an error that keeps the text', () async {
      _expectCutOff(await _run(client(start)));
    });

    test('a complete stream ends normally', () async {
      final events = await _run(client([
        ...start,
        ev('content_block_stop', {'index': 0}),
        ev('message_delta', {'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 12}}),
        ev('message_stop'),
      ]));
      expect(events.whereType<ErrorEvent>(), isEmpty);
      expect((events.last as DoneEvent).finishReason, 'stop');
    });
  });

  test('in the chat the cut-off reply is a failed message with its text, and the caller gets the error', () async {
    final rig = await ChatRig.create(
      llm: ScriptedLlm((_) => const [TextDelta(_story), ErrorEvent('The reply from 127.0.0.1:8088 stopped before it was complete.')]),
    );
    addTearDown(rig.dispose);
    final t = await rig.send(null, 'Write a short story about a robot.');
    expect(t.errors.single, contains('stopped before it was complete'));
    final last = (await rig.path(t.chatId!)).last;
    expect(last.status, 'error');
    expect(last.content, _story);
  });
}

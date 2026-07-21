import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:right_answer/services/sse_client.dart';

void main() {
  group('SseClient.postJsonStream', () {
    test('parses chunk/done events split across multiple network reads', () async {
      // The full SSE body for a chunk + chunk + done sequence, chopped into
      // arbitrary byte windows to simulate a real streamed HTTP response
      // where event boundaries don't line up with read boundaries.
      const body =
          'event: chunk\n'
          'data: {"delta":"## Hea"}\n\n'
          'event: chunk\n'
          'data: {"delta":"ding\\n\\n**bo"}\n\n'
          'event: chunk\n'
          'data: {"delta":"ld**"}\n\n'
          'event: done\n'
          'data: {"sources":[],"subjectId":"s1","subjectName":"Math","chapterId":"c1","chapterName":"Algebra","servedFrom":"live"}\n\n';

      final bytes = utf8.encode(body);
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 7) {
        chunks.add(bytes.sublist(i, (i + 7).clamp(0, bytes.length)));
      }

      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable(chunks),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final events = await SseClient.postJsonStream(
        uri: Uri.parse('https://example.test/stream'),
        headers: const {'Content-Type': 'application/json'},
        body: const {'question': 'hi'},
        client: mockClient,
      ).toList();

      expect(events.map((e) => e.event).toList(), [
        'chunk',
        'chunk',
        'chunk',
        'done',
      ]);
      expect(events[0].data['delta'], '## Hea');
      expect(events[1].data['delta'], 'ding\n\n**bo');
      expect(events[2].data['delta'], 'ld**');
      expect(events[3].data['sources'], isEmpty);
      expect(events[3].data['subjectName'], 'Math');
    });

    test('non-200 status yields a single httpStatus error event', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(jsonEncode({
              'error': {'message': 'bad question'},
            })),
          ]),
          400,
        );
      });

      final events = await SseClient.postJsonStream(
        uri: Uri.parse('https://example.test/stream'),
        headers: const {},
        body: const {},
        client: mockClient,
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.event, 'error');
      expect(events.single.data['kind'], 'httpStatus');
      expect(events.single.data['statusCode'], 400);
      expect(events.single.data['message'], 'bad question');
    });

    test('a thrown connection error yields a connection error event', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        throw const SocketException('nope');
      });

      final events = await SseClient.postJsonStream(
        uri: Uri.parse('https://example.test/stream'),
        headers: const {},
        body: const {},
        client: mockClient,
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.event, 'error');
      expect(events.single.data['kind'], 'connection');
    });

    test('a genuine server-sent error event passes through with no kind', () async {
      const body = 'event: error\ndata: {"message":"boom"}\n\n';
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode(body)]),
          200,
        );
      });

      final events = await SseClient.postJsonStream(
        uri: Uri.parse('https://example.test/stream'),
        headers: const {},
        body: const {},
        client: mockClient,
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.event, 'error');
      expect(events.single.data['message'], 'boom');
      expect(events.single.data.containsKey('kind'), isFalse);
    });

    test('a malformed data line does not throw and is surfaced as raw', () async {
      const body = 'event: chunk\ndata: not json\n\n';
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode(body)]),
          200,
        );
      });

      final events = await SseClient.postJsonStream(
        uri: Uri.parse('https://example.test/stream'),
        headers: const {},
        body: const {},
        client: mockClient,
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.data['raw'], 'not json');
    });
  });
}

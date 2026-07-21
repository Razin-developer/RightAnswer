import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A single parsed Server-Sent-Events frame: `event: <event>\ndata: <json>`.
///
/// `data` is always a decoded JSON map. If the server sent something that
/// wasn't a JSON object (malformed data, or a non-JSON payload), the raw
/// text is preserved under the `raw` key instead of throwing, so a single
/// bad frame never crashes the stream.
class SseEvent {
  final String event;
  final Map<String, dynamic> data;

  const SseEvent({required this.event, required this.data});

  @override
  String toString() => 'SseEvent(event: $event, data: $data)';
}

/// Minimal hand-rolled SSE client for POST-initiated event streams (plain
/// `EventSource` only supports GET, so we can't use it here).
///
/// Handles:
///  - Non-200 responses (surfaced as a synthetic `error` event carrying the
///    HTTP status so callers can classify it the same way as the
///    non-streaming path does).
///  - Connection failures (timeout / socket / client exceptions) — also
///    surfaced as a synthetic `error` event, tagged `kind: connection` so
///    callers can tell it apart from a genuine application-level error the
///    server chose to send.
///  - Mid-stream idle stalls, via [idleTimeout].
class SseClient {
  SseClient._();

  static const String _kindConnection = 'connection';
  static const String _kindHttpStatus = 'httpStatus';

  /// POSTs [body] as JSON to [uri] and yields parsed SSE events as they
  /// arrive, in order. Never throws — every failure mode is surfaced as an
  /// `error` SseEvent so callers can handle everything from one place.
  /// [client] is injectable for testing (a real request never has to leave
  /// the process to verify the parsing/error-handling logic); production
  /// callers omit it and get a fresh [http.Client] per call.
  static Stream<SseEvent> postJsonStream({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(seconds: 45),
    http.Client? client,
  }) async* {
    final ownedClient = client == null;
    final effectiveClient = client ?? http.Client();
    try {
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final streamedResponse = await effectiveClient.send(request).timeout(
        connectTimeout,
      );

      if (streamedResponse.statusCode != 200) {
        String message =
            'The server returned an error (${streamedResponse.statusCode}).';
        try {
          final rawBody = await streamedResponse.stream
              .transform(utf8.decoder)
              .join()
              .timeout(connectTimeout);
          final decoded = jsonDecode(rawBody);
          if (decoded is Map<String, dynamic>) {
            message =
                (decoded['error'] is Map
                    ? (decoded['error']['message'] as String?)
                    : null) ??
                decoded['message'] as String? ??
                message;
          }
        } catch (_) {
          // Non-JSON error body — fall back to the generic message.
        }
        yield SseEvent(
          event: 'error',
          data: {
            'message': message,
            'kind': _kindHttpStatus,
            'statusCode': streamedResponse.statusCode,
          },
        );
        return;
      }

      var buffer = '';
      final byteStream = streamedResponse.stream
          .transform(utf8.decoder)
          .timeout(idleTimeout);

      await for (final chunk in byteStream) {
        buffer += chunk;
        var sepIndex = buffer.indexOf('\n\n');
        while (sepIndex != -1) {
          final rawEvent = buffer.substring(0, sepIndex);
          buffer = buffer.substring(sepIndex + 2);
          final parsed = _parseEvent(rawEvent);
          if (parsed != null) yield parsed;
          sepIndex = buffer.indexOf('\n\n');
        }
      }

      // A trailing frame without a final blank-line separator (some servers
      // omit it on the very last write before closing the connection).
      final trailing = _parseEvent(buffer);
      if (trailing != null) yield trailing;
    } on TimeoutException {
      yield const SseEvent(
        event: 'error',
        data: {
          'message': 'The connection timed out. Please try again.',
          'kind': _kindConnection,
        },
      );
    } on SocketException {
      yield const SseEvent(
        event: 'error',
        data: {
          'message': 'No internet connection. Check your network and try again.',
          'kind': _kindConnection,
        },
      );
    } on http.ClientException {
      yield const SseEvent(
        event: 'error',
        data: {
          'message': 'Could not reach the backend. Please try again shortly.',
          'kind': _kindConnection,
        },
      );
    } catch (_) {
      yield const SseEvent(
        event: 'error',
        data: {
          'message': 'The connection was interrupted. Please try again.',
          'kind': _kindConnection,
        },
      );
    } finally {
      // Only close a client we created ourselves — an injected (test-owned)
      // client's lifecycle belongs to its caller.
      if (ownedClient) effectiveClient.close();
    }
  }

  /// Parses one `event:`/`data:` frame (already split on the blank-line
  /// separator). Returns null for empty/whitespace-only frames (e.g. SSE
  /// keep-alive comments or a trailing empty buffer).
  static SseEvent? _parseEvent(String rawEvent) {
    if (rawEvent.trim().isEmpty) return null;

    var eventType = 'message';
    final dataLines = <String>[];
    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
      // Other fields (id:, retry:, comments starting with ':') are ignored —
      // not part of this backend's contract.
    }
    if (dataLines.isEmpty) return null;

    final dataStr = dataLines.join('\n');
    try {
      final decoded = jsonDecode(dataStr);
      if (decoded is Map) {
        return SseEvent(
          event: eventType,
          data: decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
      return SseEvent(event: eventType, data: {'value': decoded});
    } catch (_) {
      return SseEvent(event: eventType, data: {'raw': dataStr});
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const _timeout = Duration(seconds: 30);

  String get _base => AppConfig.apiUrl;

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await AuthService.instance.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Runs an HTTP call and turns every failure mode — timeout, no
  /// connection, a server response that isn't JSON (a proxy error page, an
  /// empty body from an unmatched route) — into a single catchable
  /// [ApiException] instead of letting raw platform exceptions
  /// (SocketException, TimeoutException, FormatException) escape to
  /// callers that don't know how to handle them.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'The server took too long to respond.');
    } on SocketException {
      throw const ApiException(
        0,
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw const ApiException(0, 'Could not reach the server.');
    } on HandshakeException {
      throw const ApiException(0, 'A secure connection could not be made.');
    }
  }

  Map<String, dynamic> _parse(http.Response resp) {
    final Map<String, dynamic> body;
    try {
      final decoded = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      // A non-JSON body (nginx/proxy error page, an unmatched route with no
      // handler, a truncated response) — surface the status code with a
      // generic message rather than letting the parse error itself escape.
      throw ApiException(resp.statusCode, 'Request failed (${resp.statusCode})');
    }

    if (resp.statusCode >= 400) {
      final error = body['error'];
      final message = error is String
          ? error
          : (error is Map ? error['message'] as String? : null) ??
                'Request failed (${resp.statusCode})';
      throw ApiException(resp.statusCode, message);
    }
    // The Rust API wraps every response as { success, data }. Unwrap so
    // callers work with the actual payload instead of the envelope.
    final data = body['data'];
    if (body.containsKey('success') && data is Map<String, dynamic>) {
      return data;
    }
    return body;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final resp = await _send(
      () async => http.get(Uri.parse('$_base$path'), headers: await _headers()),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final resp = await _send(
      () async => http.post(
        Uri.parse('$_base$path'),
        headers: await _headers(auth: auth),
        body: jsonEncode(body),
      ),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _send(
      () async => http.put(
        Uri.parse('$_base$path'),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final resp = await _send(
      () async => http.delete(Uri.parse('$_base$path'), headers: await _headers()),
    );
    return _parse(resp);
  }

  /// Upload a file with optional metadata JSON field.
  Future<Map<String, dynamic>> uploadFile(
    String path,
    File file, {
    String fieldName = 'file',
    Map<String, String>? fields,
  }) async {
    final resp = await _send(() async {
      final token = await AuthService.instance.getToken();
      final req = http.MultipartRequest('POST', Uri.parse('$_base$path'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
      if (fields != null) req.fields.addAll(fields);
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
    return _parse(resp);
  }

  /// Download raw bytes (for ZIP content share).
  Future<List<int>> downloadBytes(String url) async {
    final resp = await _send(() async {
      final token = await AuthService.instance.getToken();
      return http.get(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': '*/*',
        },
      );
    });
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, 'Download failed');
    }
    return resp.bodyBytes;
  }
}

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

  Map<String, dynamic> _parse(http.Response resp) {
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw ApiException(
        resp.statusCode,
        (body['error'] as String?) ?? 'Request failed (${resp.statusCode})',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final resp = await http.get(
      Uri.parse('$_base$path'),
      headers: await _headers(),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final resp = await http.post(
      Uri.parse('$_base$path'),
      headers: await _headers(auth: auth),
      body: jsonEncode(body),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.put(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _parse(resp);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final resp = await http.delete(
      Uri.parse('$_base$path'),
      headers: await _headers(),
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
    final token = await AuthService.instance.getToken();
    final req = http.MultipartRequest('POST', Uri.parse('$_base$path'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      await http.MultipartFile.fromPath(fieldName, file.path),
    );
    if (fields != null) req.fields.addAll(fields);
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    return _parse(resp);
  }

  /// Download raw bytes (for ZIP content share).
  Future<List<int>> downloadBytes(String url) async {
    final token = await AuthService.instance.getToken();
    final resp = await http.get(
      Uri.parse(url),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': '*/*',
      },
    );
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, 'Download failed');
    }
    return resp.bodyBytes;
  }
}

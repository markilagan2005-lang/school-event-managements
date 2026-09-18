import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiHttpException implements Exception {
  const ApiHttpException(
    this.statusCode,
    this.body, {
    this.decodedBody,
  });

  final int statusCode;
  final String body;
  final Map<String, dynamic>? decodedBody;

  @override
  String toString() {
    if (body.isEmpty) return 'Request failed ($statusCode)';
    return body;
  }
}

class TransientHttpStatusException implements Exception {
  const TransientHttpStatusException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Transient HTTP status: $statusCode';
}

class ApiClient {
  ApiClient(String baseUrl) : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;
  // Render free instances can take ~50s to wake from sleep.
  static const Duration _timeout = Duration(seconds: 70);

  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim().replaceAll('`', '').replaceAll('"', '').replaceAll("'", '');
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) {
      return url;
    }
    return '$url/api';
  }

  static Map<String, dynamic>? _tryDecodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{')) return null;
    try {
      return jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static bool _isLocalOrLanUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('10.0.2.2') ||
        lower.contains('192.168.') ||
        lower.contains('172.16.') ||
        lower.contains('172.17.') ||
        lower.contains('172.18.') ||
        lower.contains('172.19.') ||
        lower.contains('172.20.') ||
        lower.contains('172.21.') ||
        lower.contains('172.22.') ||
        lower.contains('172.23.') ||
        lower.contains('172.24.') ||
        lower.contains('172.25.') ||
        lower.contains('172.26.') ||
        lower.contains('172.27.') ||
        lower.contains('172.28.') ||
        lower.contains('172.29.') ||
        lower.contains('172.30.') ||
        lower.contains('172.31.');
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _runWithRetry(() {
      return http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getJsonList(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _runWithRetry(() {
      return http
          .get(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getJsonMap(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _runWithRetry(() {
      return http
          .get(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteJson(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _runWithRetry(() {
      return http
          .delete(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _runWithRetry(() {
      return http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  }

  static bool _isTransientNetworkError(Object e) {
    if (e is TransientHttpStatusException) return true;
    if (e is TimeoutException || e is SocketException) return true;
    if (e is http.ClientException) {
      final m = e.message.toLowerCase();
      return m.contains('failed host lookup') || m.contains('connection closed') || m.contains('connection reset');
    }
    final s = e.toString().toLowerCase();
    return s.contains('failed host lookup') || s.contains('connection refused');
  }

  static const List<Duration> _retryBackoffs = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  Future<http.Response> _runWithRetry(Future<http.Response> Function() action) async {
    const totalAttempts = 4;
    Object? lastError;
    for (var i = 0; i < totalAttempts; i++) {
      if (i > 0) {
        final delay = _retryBackoffs[i];
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
      try {
        final res = await action();
        if (res.statusCode == 502 || res.statusCode == 503) {
          lastError = TransientHttpStatusException(res.statusCode);
          continue;
        }
        return res;
      } catch (e) {
        lastError = e;
        if (!_isTransientNetworkError(e)) rethrow;
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, StackTrace.current);
    }
    throw StateError('Retry loop exhausted without a result');
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _normalizeBaseUrl(url));
  }

  static String _finalSanitizeUrl(String url, String fallbackUrl) {
    final production = _normalizeBaseUrl(apiBaseUrlDefault);
    final u = _normalizeBaseUrl(url);
    final lower = u.toLowerCase();
    if (lower.contains('onrender.com')) return u;
    if (!lower.startsWith('https://')) return production;
    if (_isLocalOrLanUrl(u)) return production;
    if (u.isEmpty) return production;
    return u;
  }

  static Future<String> getBaseUrl({String fallback = apiBaseUrlDefault}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final fallbackUrl = _normalizeBaseUrl(fallback);
    final production = _normalizeBaseUrl(apiBaseUrlDefault);
    if (lockServerSettings) {
      await prefs.setString('api_base_url', production);
      await prefs.reload();
      return production;
    }
    final saved = prefs.getString('api_base_url');
    if (saved == null || saved.trim().isEmpty) {
      return _finalSanitizeUrl(fallbackUrl, production);
    }

    var savedUrl = _normalizeBaseUrl(saved);

    if (_isLocalOrLanUrl(savedUrl)) {
      savedUrl = production;
      await prefs.setString('api_base_url', savedUrl);
    }

    return _finalSanitizeUrl(savedUrl, production);
  }
}

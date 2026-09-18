import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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

  static HttpClient _makePermissiveHttpClient() {
    final hc = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = _timeout
      ..maxConnectionsPerHost = 6
      ..autoUncompress = true
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return hc;
  }

  static Future<String?> _resolveViaCloudflareDoh(String host, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final hc = _makePermissiveHttpClient();
      try {
        final req = await hc.getUrl(Uri.parse('https://1.1.1.1/dns-query?name=${Uri.encodeQueryComponent(host)}&type=A')).timeout(timeout);
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close().timeout(timeout);
        if (resp.statusCode != 200) return null;
        final body = await resp.transform(utf8.decoder).join().timeout(timeout);
        final j = jsonDecode(body);
        if (j is! Map<String, dynamic>) return null;
        final answers = j['Answer'] as List<dynamic>?;
        if (answers == null || answers.isEmpty) return null;
        for (final a in answers) {
          if (a is Map<String, dynamic>) {
            final t = a['type'];
            final d = a['data']?.toString();
            if (t == 1 && d != null && d.trim().isNotEmpty) {
              return d.trim();
            }
          }
        }
        return null;
      } finally {
        hc.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  static bool _isTransientNetworkError(Object e) {
    if (e is TransientHttpStatusException) return true;
    if (e is TimeoutException || e is SocketException) return true;
    if (e is http.ClientException) {
      final m = e.message.toLowerCase();
      return m.contains('failed host lookup') ||
          m.contains('connection closed') ||
          m.contains('connection reset') ||
          m.contains('connection refused') ||
          m.contains('temporary failure in name resolution') ||
          m.contains('name or service not known') ||
          m.contains('host not found');
    }
    final s = e.toString().toLowerCase();
    return s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('temporary failure in name resolution') ||
        s.contains('name or service not known') ||
        s.contains('host not found');
  }

  static const List<Duration> _retryBackoffs = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 25),
  ];

  static const int _totalAttempts = 5;

  static String? _cachedRenderIp;
  static DateTime? _cachedRenderIpExpires;

  Future<http.Response> _doCall({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int>? bodyBytes,
    required int attemptIndex,
    required bool lastErrorWasSocket,
  }) async {
    IOClient? io;
    HttpClient? raw;
    try {
      Uri target = Uri.parse('$baseUrl$path');
      final extra = <String, String>{};

      if (attemptIndex >= 1 && lastErrorWasSocket) {
        final prodNorm = _normalizeBaseUrl(apiBaseUrlDefault);
        final prodHost = Uri.parse(prodNorm.replaceFirst(RegExp(r'/api$'), '')).host;
        if (target.host.toLowerCase() == prodHost.toLowerCase()) {
          String? ip = _cachedRenderIp;
          final now = DateTime.now();
          if (ip == null || _cachedRenderIpExpires == null || now.isAfter(_cachedRenderIpExpires!)) {
            ip = await _resolveViaCloudflareDoh(prodHost);
            if (ip != null) {
              _cachedRenderIp = ip;
              _cachedRenderIpExpires = now.add(const Duration(minutes: 5));
            }
          }
          if (ip != null) {
            final replaced = target.replace(host: ip);
            target = replaced;
            extra['host'] = prodHost;
          }
        }
      }

      raw = _makePermissiveHttpClient();
      io = IOClient(raw);

      final reqHdrs = <String, String>{
        ...headers,
        ...extra,
      };

      Future<http.Response> future;
      switch (method) {
        case 'POST':
          future = io.post(target, headers: reqHdrs, body: bodyBytes);
          break;
        case 'PATCH':
          future = io.patch(target, headers: reqHdrs, body: bodyBytes);
          break;
        case 'DELETE':
          future = io.delete(target, headers: reqHdrs);
          break;
        case 'GET':
        default:
          future = io.get(target, headers: reqHdrs);
          break;
      }

      return await future.timeout(_timeout);
    } finally {
      try {
        io?.close();
      } catch (_) {}
      try {
        raw?.close(force: true);
      } catch (_) {}
    }
  }

  Future<http.Response> _runWithRetry({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    List<int>? bodyBytes,
  }) async {
    Object? lastError;
    var lastWasSocket = false;
    for (var i = 0; i < _totalAttempts; i++) {
      if (i > 0 && i < _retryBackoffs.length) {
        final delay = _retryBackoffs[i];
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
      try {
        final res = await _doCall(
          method: method,
          path: path,
          headers: headers,
          bodyBytes: bodyBytes,
          attemptIndex: i,
          lastErrorWasSocket: lastWasSocket,
        );
        if (res.statusCode == 502 || res.statusCode == 503) {
          lastError = TransientHttpStatusException(res.statusCode);
          lastWasSocket = false;
          continue;
        }
        return res;
      } catch (e) {
        lastError = e;
        lastWasSocket = e is SocketException ||
            (e is http.ClientException &&
                (e.message.toLowerCase().contains('host lookup') ||
                    e.message.toLowerCase().contains('name resolution') ||
                    e.message.toLowerCase().contains('name or service not known') ||
                    e.message.toLowerCase().contains('host not found')));
        if (!_isTransientNetworkError(e)) rethrow;
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, StackTrace.current);
    }
    throw StateError('Retry loop exhausted without a result');
  }

  Future<http.Response> _run(String method, String path, {Map<String, dynamic>? bodyJson, String? token}) async {
    final headers = <String, String>{
      if (bodyJson != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final bodyBytes = bodyJson == null ? null : utf8.encode(jsonEncode(bodyJson));
    return _runWithRetry(
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final res = await _run('POST', path, bodyJson: body, token: token);
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
    final res = await _run('GET', path, token: token);
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
    final res = await _run('GET', path, token: token);
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
    final res = await _run('DELETE', path, token: token);
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
    final res = await _run('PATCH', path, bodyJson: body, token: token);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiHttpException(
        res.statusCode,
        res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body,
        decodedBody: _tryDecodeJson(res.body),
      );
    }
    return res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
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

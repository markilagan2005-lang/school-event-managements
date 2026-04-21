import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiClient {
  ApiClient(String baseUrl) : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;
  static const Duration _timeout = Duration(seconds: 8);

  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) {
      return url;
    }
    return '$url/api';
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getJsonList(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http
        .get(
          uri,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body);
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> deleteJson(String path, {String? token}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http
        .delete(
          uri,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(res.body.isEmpty ? 'Request failed (${res.statusCode})' : res.body);
    }
    return res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _normalizeBaseUrl(url));
  }

  static Future<String> getBaseUrl({String fallback = apiBaseUrlDefault}) async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeBaseUrl(prefs.getString('api_base_url') ?? fallback);
  }
}

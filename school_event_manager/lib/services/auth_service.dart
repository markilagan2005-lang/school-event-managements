import 'dart:convert';
import 'dart:async';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static const String _userKey = 'current_user';
  static const String _tokenKey = 'auth_token';

  static AuthFailure _authFailureFromServerError(Object e) {
    final raw = e.toString();
    if (e is TimeoutException) {
      return const AuthFailure(AuthFailureCode.unknown, 'Cannot connect to server');
    }
    if (raw.contains('SocketException') ||
        raw.toLowerCase().contains('failed host lookup') ||
        raw.toLowerCase().contains('connection refused')) {
      return const AuthFailure(AuthFailureCode.unknown, 'Cannot connect to server');
    }
    if (raw.contains('Request failed (404)')) {
      return const AuthFailure(AuthFailureCode.unknown, 'Server URL is wrong');
    }
    if (raw.toLowerCase().contains('<!doctype html') || raw.toLowerCase().contains('<html')) {
      return const AuthFailure(AuthFailureCode.unknown, 'Server route not found');
    }
    final idx = raw.indexOf('{');
    if (idx != -1) {
      final jsonStr = raw.substring(idx);
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map && decoded['error'] != null) {
          final msg = decoded['error'].toString();
          if (msg.toLowerCase().contains('username already exists') || msg.toLowerCase().contains('username exists')) {
            return const AuthFailure(AuthFailureCode.usernameExists, 'Username already exists');
          }
          if (msg.toLowerCase().contains('username not found')) {
            return const AuthFailure(AuthFailureCode.usernameNotFound, 'Username not found');
          }
          if (msg.toLowerCase().contains('wrong password')) {
            return const AuthFailure(AuthFailureCode.wrongPassword, 'Wrong password');
          }
          return AuthFailure(AuthFailureCode.unknown, msg);
        }
      } catch (_) {}
    }
    return const AuthFailure(AuthFailureCode.unknown, 'Login failed');
  }

  static Future<User?> register(
    String username,
    String password,
    String role, {
    String? fullName,
    String? studentId,
    String? course,
    String? section,
  }) async {
    try {
      final res = await ApiService.register(
        username,
        password,
        role,
        fullName: fullName,
        studentId: studentId,
        course: course,
        section: section,
      );
      final userJson = res['user'] as Map<String, dynamic>?;
      if (userJson == null) return null;
      final user = User.fromJson(userJson);
      final token = res['token']?.toString() ?? '';
      if (token.isEmpty) {
        final pendingMsg = (res['message']?.toString().trim().isNotEmpty ?? false)
            ? res['message'].toString().trim()
            : 'Account created. Wait for admin verification.';
        throw AuthFailure(AuthFailureCode.unknown, pendingMsg);
      }
      return user;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      final failure = _authFailureFromServerError(e);
      throw AuthFailure(
        failure.code,
        failure.message.isNotEmpty ? failure.message : 'Cannot connect to server',
      );
    }
  }

  static Future<User?> login(String username, String password) async {
    try {
      final res = await ApiService.login(username, password);
      final userJson = res['user'] as Map<String, dynamic>?;
      if (userJson == null) return null;
      final user = User.fromJson(userJson);
      if (user.role == 'faculty' && !user.isApproved) {
        await logout();
        throw const AuthFailure(
          AuthFailureCode.unknown,
          'Faculty account is pending admin approval',
        );
      }
      return user;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      final failure = _authFailureFromServerError(e);
      throw AuthFailure(
        failure.code,
        failure.message.isNotEmpty ? failure.message : 'Cannot connect to server',
      );
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
  }

  static Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      await prefs.remove(_userKey);
      return null;
    }
    final userJsonStr = prefs.getString(_userKey);
    if (userJsonStr == null) return null;
    final userMap = jsonDecode(userJsonStr) as Map<String, dynamic>;
    return User.fromJson(userMap);
  }

  static Future<User?> refreshCurrentUserFromServer() async {
    final userMap = await ApiService.getMe();
    return User.fromJson(userMap);
  }

  static bool get isLoggedIn => false;
}

enum AuthFailureCode { usernameExists, usernameNotFound, wrongPassword, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message);

  final AuthFailureCode code;
  final String message;

  @override
  String toString() => message;
}

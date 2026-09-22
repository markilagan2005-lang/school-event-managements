import 'dart:convert';
import 'dart:async';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'api_client.dart';

class OtpResult {
  const OtpResult({
    required this.ok,
    this.message,
  });

  final bool ok;
  final String? message;
}

class AuthService {
  static const String _userKey = 'current_user';
  static const String _tokenKey = 'auth_token';

  static Future<AuthFailure> _authFailureFromServerError(Object e) async {
    final raw = e.toString();
    Map<String, dynamic>? decoded;
    if (e is ApiHttpException) {
      decoded = e.decodedBody;
    } else {
      final idx = raw.indexOf('{');
      if (idx != -1) {
        final jsonStr = raw.substring(idx);
        try {
          final maybe = jsonDecode(jsonStr);
          if (maybe is Map<String, dynamic>) decoded = maybe;
        } catch (_) {}
      }
    }
    final messageCode = decoded?['messageCode']?.toString();
    final serverMessage = decoded?['message']?.toString().trim();
    final serverError = decoded?['error']?.toString().trim();
    final email = decoded?['email']?.toString();
    final username = decoded?['username']?.toString();
    final expiresInMs = decoded?['expiresInMs'] as int?;
    final emailSent = decoded?['emailSent'] == true;
    final emailError = decoded?['emailError']?.toString();

    final baseForError = (await ApiClient.getBaseUrl()).replaceFirst(RegExp(r'/api$'), '');
    if (e is TimeoutException) {
      return AuthFailure(AuthFailureCode.unknown, 'Cannot connect to server (timeout). URL: $baseForError');
    }
    if (raw.contains('SocketException') ||
        raw.toLowerCase().contains('failed host lookup') ||
        raw.toLowerCase().contains('connection refused')) {
      return AuthFailure(AuthFailureCode.unknown, 'Cannot connect to server. Check WiFi/Data. URL: $baseForError');
    }
    if (raw.contains('Request failed (404)')) {
      return const AuthFailure(AuthFailureCode.unknown, 'Server URL is wrong');
    }
    if (raw.toLowerCase().contains('<!doctype html') || raw.toLowerCase().contains('<html')) {
      return const AuthFailure(AuthFailureCode.unknown, 'Server route not found');
    }

    final errorMessage = (serverMessage ?? '').isNotEmpty ? serverMessage! : (serverError ?? '');

    if (messageCode == 'EMAIL_VERIFICATION_REQUIRED') {
      return AuthFailure(
        AuthFailureCode.emailVerificationRequired,
        errorMessage.isEmpty ? 'Enter the 6-digit code we emailed you.' : errorMessage,
        messageCode: messageCode,
        email: email,
        username: username,
        expiresInMs: expiresInMs,
        emailSent: emailSent,
        emailError: emailError,
      );
    }
    if (messageCode == 'PENDING_ADMIN_APPROVAL') {
      return AuthFailure(
        AuthFailureCode.unknown,
        errorMessage.isEmpty ? 'Faculty account is pending admin approval.' : errorMessage,
        messageCode: messageCode,
        email: email,
        username: username,
      );
    }

    if (errorMessage.isNotEmpty) {
      final lower = errorMessage.toLowerCase();
      if (lower.contains('username already exists') || lower.contains('username exists')) {
        return const AuthFailure(AuthFailureCode.usernameExists, 'Username already exists');
      }
      if (lower.contains('username not found')) {
        return const AuthFailure(AuthFailureCode.usernameNotFound, 'Username not found');
      }
      if (lower.contains('wrong password')) {
        return const AuthFailure(AuthFailureCode.wrongPassword, 'Wrong password');
      }
      return AuthFailure(AuthFailureCode.unknown, errorMessage, messageCode: messageCode);
    }
    return const AuthFailure(AuthFailureCode.unknown, 'Login failed');
  }

  static Future<(bool ok, String? message, Map<String, dynamic>? meta)> sendRegistrationOtp(String email) async {
    try {
      final res = await ApiService.sendRegistrationOtp(email);
      final meta = <String, dynamic>{
        if (res['ref'] != null) 'ref': res['ref'],
        if (res['email'] != null) 'email': res['email'],
        if (res['expiresInMs'] != null) 'expiresInMs': res['expiresInMs'],
        if (res['emailSent'] != null) 'emailSent': res['emailSent'],
        if (res['emailError'] != null) 'emailError': res['emailError'],
      };
      final msg = res['message']?.toString().trim();
      return (true, (msg ?? '').isEmpty ? null : msg, meta);
    } catch (e) {
      String? detail;
      if (e is ApiHttpException) {
        final decoded = e.decodedBody;
        final m = decoded?['message']?.toString().trim();
        final err = decoded?['error']?.toString().trim();
        if ((m ?? '').isNotEmpty) {
          detail = m;
        } else if ((err ?? '').isNotEmpty) {
          detail = err;
        } else if (e.statusCode == 404) {
          detail = 'Server has not been updated yet. Push latest code to Render and redeploy (or run local node server.js if testing locally).';
        } else if (e.statusCode >= 500) {
          detail = 'Server error. Check Render logs for JWT_SECRET or runtime crashes, then wait 1-2 minutes and retry.';
        } else if (e.statusCode == 429) {
          detail = 'Please wait ~60 seconds before requesting a new verification code.';
        } else {
          detail = 'Server responded HTTP ${e.statusCode}. Retry in a few seconds.';
        }
      } else {
        final raw = e.toString().toLowerCase();
        final url = (await ApiClient.getBaseUrl()).replaceFirst(RegExp(r'/api$'), '');
        if (raw.contains('socketexception') ||
            raw.contains('failed host lookup') ||
            raw.contains('connection refused') ||
            raw.contains('connection reset')) {
          detail = 'Cannot reach server. Make sure you have Internet. If testing locally, start node server.js and set API_BASE_URL to your PC IP (for Android emulator use 10.0.2.2:3000). (URL: $url)';
        } else if (e is TimeoutException) {
          detail = 'Server took too long to reply. Render free tier sleeps after inactivity — wait 30-60 seconds and try again. (URL: $url)';
        }
      }
      return (false, detail ?? 'Could not send verification code. Try again.', null);
    }
  }

  static Future<(User? user, Map<String, dynamic>? meta)> register(
    String username,
    String password,
    String role, {
    String? fullName,
    String? studentId,
    String? course,
    String? section,
    String? email,
    String? registrationOtp,
    String? registrationOtpRef,
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
        email: email,
        registrationOtp: registrationOtp,
        registrationOtpRef: registrationOtpRef,
      );
      final messageCode = res['messageCode']?.toString();
      final meta = <String, dynamic>{
        'message': res['message']?.toString(),
        if (messageCode != null) 'messageCode': messageCode,
        if (res['username'] != null) 'username': res['username'],
        if (res['email'] != null) 'email': res['email'],
        if (res['expiresInMs'] != null) 'expiresInMs': res['expiresInMs'],
        if (res['emailSent'] != null) 'emailSent': res['emailSent'],
        if (res['emailError'] != null) 'emailError': res['emailError'],
      };
      final userJson = res['user'] as Map<String, dynamic>?;
      if (userJson == null) {
        return (null, meta);
      }
      final user = User.fromJson(userJson);
      final token = res['token']?.toString() ?? '';
      if (token.isEmpty) {
        return (null, meta);
      }
      return (user, meta);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      final failure = await _authFailureFromServerError(e);
      throw AuthFailure(
        failure.code,
        failure.message.isNotEmpty ? failure.message : 'Cannot connect to server',
        messageCode: failure.messageCode,
        email: failure.email,
        username: failure.username,
        expiresInMs: failure.expiresInMs,
        emailSent: failure.emailSent,
        emailError: failure.emailError,
      );
    }
  }

  static Future<(User? user, Map<String, dynamic>? meta)> login(String username, String password, {String loginMode = 'auto'}) async {
    try {
      final res = await ApiService.login(username, password, loginMode: loginMode);
      final userJson = res['user'] as Map<String, dynamic>?;
      if (userJson == null) return (null, null);
      final user = User.fromJson(userJson);
      if (user.role == 'faculty' && !user.isApproved) {
        await logout();
        throw const AuthFailure(
          AuthFailureCode.unknown,
          'Faculty account is pending admin approval',
          messageCode: 'PENDING_ADMIN_APPROVAL',
        );
      }
      return (user, null);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      final failure = await _authFailureFromServerError(e);
      throw AuthFailure(
        failure.code,
        failure.message.isNotEmpty ? failure.message : 'Cannot connect to server',
        messageCode: failure.messageCode,
        email: failure.email,
        username: failure.username,
        expiresInMs: failure.expiresInMs,
        emailSent: failure.emailSent,
        emailError: failure.emailError,
      );
    }
  }

  static Future<OtpResult> verifyOtp({
    String? username,
    String? email,
    required String code,
  }) async {
    try {
      await ApiService.verifyOtp(
        username: username,
        email: email,
        code: code,
      );
      return const OtpResult(ok: true);
    } catch (e) {
      final msg = _humanReadableMessage(e, fallback: 'Invalid code. Please try again or tap Resend code.');
      return OtpResult(ok: false, message: msg);
    }
  }

  static Future<(bool ok, String? message, Map<String, dynamic>? meta)> resendOtp({
    String? username,
    String? email,
  }) async {
    try {
      final res = await ApiService.resendOtp(username: username, email: email);
      final message = res['message']?.toString().trim();
      final meta = <String, dynamic>{
        if (res['messageCode'] != null) 'messageCode': res['messageCode'],
        if (res['email'] != null) 'email': res['email'],
        if (res['expiresInMs'] != null) 'expiresInMs': res['expiresInMs'],
        if (res['emailSent'] != null) 'emailSent': res['emailSent'],
        if (res['emailError'] != null) 'emailError': res['emailError'],
      };
      return (true, message, meta);
    } catch (e) {
      return (false, _humanReadableMessage(e, fallback: 'Could not send a new code. Please try again.'), null);
    }
  }

  static String _humanReadableMessage(Object e, {required String fallback}) {
    if (e is AuthFailure) return e.message;
    final raw = e.toString();
    Map<String, dynamic>? decoded;
    if (e is ApiHttpException) {
      decoded = e.decodedBody;
    } else {
      final idx = raw.indexOf('{');
      if (idx != -1) {
        try {
          final maybe = jsonDecode(raw.substring(idx));
          if (maybe is Map<String, dynamic>) decoded = maybe;
        } catch (_) {}
      }
    }
    if (decoded != null) {
      final m = decoded['message']?.toString().trim();
      final err = decoded['error']?.toString().trim();
      if ((m ?? '').isNotEmpty) return m!;
      if ((err ?? '').isNotEmpty) return err!;
    }
    if (raw.toLowerCase().contains('socketexception') ||
        raw.toLowerCase().contains('failed host lookup') ||
        raw.toLowerCase().contains('connection refused') ||
        e is TimeoutException) {
      return 'Cannot connect to server.';
    }
    return fallback;
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

enum AuthFailureCode {
  usernameExists,
  usernameNotFound,
  wrongPassword,
  emailVerificationRequired,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(
    this.code,
    this.message, {
    this.messageCode,
    this.email,
    this.username,
    this.expiresInMs,
    this.emailSent,
    this.emailError,
  });

  final AuthFailureCode code;
  final String message;
  final String? messageCode;
  final String? email;
  final String? username;
  final int? expiresInMs;
  final bool? emailSent;
  final String? emailError;

  @override
  String toString() => message;
}

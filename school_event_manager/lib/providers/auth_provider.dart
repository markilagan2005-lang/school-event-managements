import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class SendOtpResult {
  const SendOtpResult({
    required this.ok,
    this.message,
    this.ref,
    this.email,
    this.expiresInMs,
    this.emailSent = false,
  });

  final bool ok;
  final String? message;
  final String? ref;
  final String? email;
  final int? expiresInMs;
  final bool emailSent;
}

class AuthActionResult {
  const AuthActionResult({
    this.errorMessage,
    this.messageCode,
    this.email,
    this.username,
    this.expiresInMs,
    this.emailSent,
    this.emailError,
    this.succeeded = false,
  });

  final String? errorMessage;
  final String? messageCode;
  final String? email;
  final String? username;
  final int? expiresInMs;
  final bool? emailSent;
  final String? emailError;
  final bool succeeded;

  bool get isEmailVerificationRequired =>
      messageCode == 'EMAIL_VERIFICATION_REQUIRED';
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?> >((ref) => AuthNotifier());

class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthNotifier() : super(const AsyncValue.data(null)) {
    _loadUser();
  }

  String _cleanError(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  Future<void> _loadUser() async {
    state = const AsyncValue.loading();
    try {
      final user = await AuthService.getCurrentUser();
      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
    }
  }

  Future<AuthActionResult> login(String username, String password, {String loginMode = 'auto'}) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = const AsyncValue.data(null);
      return const AuthActionResult(errorMessage: 'Enter username and password');
    }
    state = const AsyncValue.loading();
    try {
      final (user, _) = await AuthService.login(username, password, loginMode: loginMode);
      if (user != null) {
        state = AsyncValue.data(user);
        return const AuthActionResult(succeeded: true);
      } else {
        state = const AsyncValue.data(null);
        return const AuthActionResult(errorMessage: 'Invalid username or password');
      }
    } on AuthFailure catch (e) {
      state = const AsyncValue.data(null);
      return AuthActionResult(
        errorMessage: e.message,
        messageCode: e.messageCode,
        email: e.email,
        username: e.username,
        expiresInMs: e.expiresInMs,
        emailSent: e.emailSent,
        emailError: e.emailError,
      );
    } catch (e) {
      state = const AsyncValue.data(null);
      return AuthActionResult(errorMessage: _cleanError(e));
    }
  }

  Future<SendOtpResult> sendRegistrationOtp(String email) async {
    if (email.trim().isEmpty) {
      return const SendOtpResult(ok: false, message: 'Enter your Gmail address first.');
    }
    final (ok, message, meta) = await AuthService.sendRegistrationOtp(email);
    return SendOtpResult(
      ok: ok,
      message: message,
      ref: meta?['ref']?.toString(),
      email: meta?['email']?.toString(),
      expiresInMs: meta?['expiresInMs'] as int?,
      emailSent: meta?['emailSent'] == true,
    );
  }

  Future<AuthActionResult> register(
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
    if (username.trim().isEmpty || password.isEmpty) {
      state = const AsyncValue.data(null);
      return AuthActionResult(
        errorMessage:
            role == 'student' ? 'Enter email and password' : 'Enter username and password',
      );
    }
    state = const AsyncValue.loading();
    try {
      final (user, meta) = await AuthService.register(
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
      final messageCode = meta?['messageCode']?.toString();
      final mEmail = meta?['email']?.toString();
      final mUsername = meta?['username']?.toString();
      final mExpiresInMs = meta?['expiresInMs'] as int?;
      final mEmailSent = meta?['emailSent'] == true;
      final mEmailError = meta?['emailError']?.toString();
      if (user != null) {
        state = AsyncValue.data(user);
        return AuthActionResult(
          succeeded: true,
          messageCode: messageCode,
          email: mEmail,
          username: mUsername,
          expiresInMs: mExpiresInMs,
          emailSent: mEmailSent,
          emailError: mEmailError,
        );
      } else {
        state = const AsyncValue.data(null);
        final msg = meta?['message']?.toString();
        return AuthActionResult(
          errorMessage: (msg ?? '').isEmpty ? 'Registration failed' : msg,
          messageCode: messageCode,
          email: mEmail,
          username: mUsername,
          expiresInMs: mExpiresInMs,
          emailSent: mEmailSent,
          emailError: mEmailError,
        );
      }
    } on AuthFailure catch (e) {
      state = const AsyncValue.data(null);
      return AuthActionResult(
        errorMessage: e.message,
        messageCode: e.messageCode,
        email: e.email,
        username: e.username,
        expiresInMs: e.expiresInMs,
        emailSent: e.emailSent,
        emailError: e.emailError,
      );
    } catch (e) {
      state = const AsyncValue.data(null);
      return AuthActionResult(errorMessage: _cleanError(e));
    }
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await AuthService.logout();
      state = const AsyncValue.data(null);
    } catch (e) {
      state = const AsyncValue.data(null);
    }
  }

  Future<String?> refreshCurrentUser() async {
    try {
      final user = await AuthService.refreshCurrentUserFromServer();
      state = AsyncValue.data(user);
      if (user != null && user.role == 'faculty' && !user.isApproved) {
        return 'Still waiting for admin approval';
      }
      return null;
    } catch (e) {
      if (e is AuthFailure) return e.message;
      return _cleanError(e);
    }
  }
}

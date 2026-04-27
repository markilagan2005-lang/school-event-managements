import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

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

  Future<String?> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = const AsyncValue.data(null);
      return 'Enter username and password';
    }
    state = const AsyncValue.loading();
    try {
      final user = await AuthService.login(username, password);
      if (user != null) {
        state = AsyncValue.data(user);
        return null;
      } else {
        state = const AsyncValue.data(null);
        return 'Invalid username or password';
      }
    } catch (e) {
      state = const AsyncValue.data(null);
      if (e is AuthFailure) {
        return e.message;
      }
      return _cleanError(e);
    }
  }

  Future<String?> register(
    String username,
    String password,
    String role, {
    String? fullName,
    String? studentId,
    String? course,
    String? section,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = const AsyncValue.data(null);
      return 'Enter username and password';
    }
    state = const AsyncValue.loading();
    try {
      final user = await AuthService.register(
        username,
        password,
        role,
        fullName: fullName,
        studentId: studentId,
        course: course,
        section: section,
      );
      if (user != null) {
        state = AsyncValue.data(user);
        return null;
      } else {
        state = const AsyncValue.data(null);
        return 'Registration failed';
      }
    } catch (e) {
      state = const AsyncValue.data(null);
      if (e is AuthFailure) {
        return e.message;
      }
      return _cleanError(e);
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

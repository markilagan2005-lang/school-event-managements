import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/attendee.dart';
import '../models/attendance.dart';
import 'api_client.dart';

class ApiService {
  static DateTime _toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return _toLocal(parsed);
  }

  static String _toServerIso(DateTime dt) => dt.toUtc().toIso8601String();

  static Future<ApiClient> _client() async {
    final base = await ApiClient.getBaseUrl();
    return ApiClient(base);
  }

  static Future<Map<String, dynamic>> sendRegistrationOtp(String email) async {
    final c = await _client();
    return c.postJson('/send-registration-otp', {
      'email': email.trim(),
    });
  }

  static Future<Map<String, dynamic>> register(
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
    final c = await _client();
    final res = await c.postJson('/register', {
      'username': username,
      'password': password,
      'role': role,
      if (fullName != null) 'fullName': fullName,
      if (studentId != null) 'studentId': studentId,
      if (course != null) 'course': course,
      if (section != null) 'section': section,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (registrationOtp != null && registrationOtp.trim().isNotEmpty)
        'registrationOtp': registrationOtp.trim(),
      if (registrationOtpRef != null && registrationOtpRef.trim().isNotEmpty)
        'registrationOtpRef': registrationOtpRef.trim(),
    });
    final prefs = await SharedPreferences.getInstance();
    final token = res['token']?.toString();
    if (token != null && token.isNotEmpty && res['user'] != null) {
      await prefs.setString('auth_token', token);
      await prefs.setString('current_user', jsonEncode(res['user']));
    } else {
      await prefs.remove('auth_token');
      await prefs.remove('current_user');
    }
    return res;
  }

  static Future<void> verifyEmail(String token) async {
    final c = await _client();
    await c.getJsonMap('/verify-email?token=$token');
  }

  static Future<Map<String, dynamic>> verifyOtp({
    String? username,
    String? email,
    required String code,
  }) async {
    final c = await _client();
    return c.postJson('/verify-otp', {
      if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      'code': code.trim(),
    });
  }

  static Future<Map<String, dynamic>> resendOtp({
    String? username,
    String? email,
  }) async {
    final c = await _client();
    return c.postJson('/resend-otp', {
      if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    });
  }

  static Future<Map<String, dynamic>> login(String username, String password, {String loginMode = 'auto'}) async {
    final c = await _client();
    final res = await c.postJson('/login', {
      'username': username,
      'password': password,
      'loginMode': loginMode,
    });
    final prefs = await SharedPreferences.getInstance();
    final token = res['token']?.toString();
    final user = res['user'];
    if (token != null && token.isNotEmpty && user != null) {
      await prefs.setString('auth_token', token);
      await prefs.setString('current_user', jsonEncode(user));
    } else {
      await prefs.remove('auth_token');
      await prefs.remove('current_user');
      if (res['message'] != null && res['message'].toString().trim().isNotEmpty) {
        throw Exception(res['message'].toString().trim());
      }
      if (res['error'] != null && res['error'].toString().trim().isNotEmpty) {
        throw Exception(res['error'].toString().trim());
      }
    }
    return res;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) {
      throw Exception('Not logged in');
    }
    final res = await c.getJsonMap('/me', token: token);
    final user = res['user'];
    if (user is! Map<String, dynamic>) {
      throw Exception('Invalid /me response');
    }
    await prefs.setString('current_user', jsonEncode(user));
    return user;
  }

  static Future<Map<String, dynamic>> resetPassword(String username, String newPassword) async {
    final c = await _client();
    return c.postJson('/reset-password', {
      'username': username,
      'newPassword': newPassword,
    });
  }

  static Future<List<Event>> getEvents() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final list = await c.getJsonList('/events', token: token);
    return list.map((e) {
      final attendees = (e['attendees'] as List<dynamic>? ?? [])
          .map((a) => Attendee.fromJson(a as Map<String, dynamic>))
          .toList();
      return Event(
        id: e['id'] ?? '',
        name: e['name'] ?? '',
        date: _parseDateTime(e['date']) ?? DateTime.now(),
        status: e['status'] ?? 'open',
        startAt: _parseDateTime(e['startAt']),
        endAt: _parseDateTime(e['endAt']),
        description: e['description']?.toString() ?? '',
        posterImageUrl: e['posterImageUrl']?.toString() ?? '',
        attendees: attendees,
      );
    }).toList();
  }

  static Future<Event> addEvent(
    String name,
    DateTime date, {
    DateTime? startAt,
    DateTime? endAt,
    String status = 'open',
    String description = '',
    String posterImageUrl = '',
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await c.postJson(
      '/events',
      {
        'name': name,
        'date': _toServerIso(date),
        'status': status,
        if (startAt != null) 'startAt': _toServerIso(startAt),
        if (endAt != null) 'endAt': _toServerIso(endAt),
        'description': description,
        'posterImageUrl': posterImageUrl,
      },
      token: token,
    );
    return Event(
      id: res['id'] ?? '',
      name: res['name'] ?? '',
      date: _parseDateTime(res['date']) ?? DateTime.now(),
      status: res['status'] ?? status,
      startAt: _parseDateTime(res['startAt']) ?? startAt,
      endAt: _parseDateTime(res['endAt']) ?? endAt,
      description: res['description']?.toString() ?? description,
      posterImageUrl: res['posterImageUrl']?.toString() ?? posterImageUrl,
      attendees: const [],
    );
  }

  static Future<Event> updateEvent(
    String id, {
    String? name,
    DateTime? date,
    String? status,
    DateTime? startAt,
    DateTime? endAt,
    String? description,
    String? posterImageUrl,
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await c.postJson(
      '/events/$id',
      {
        if (name != null) 'name': name,
        if (date != null) 'date': _toServerIso(date),
        if (status != null) 'status': status,
        'startAt': startAt == null ? null : _toServerIso(startAt),
        'endAt': endAt == null ? null : _toServerIso(endAt),
        if (description != null) 'description': description,
        if (posterImageUrl != null) 'posterImageUrl': posterImageUrl,
      },
      token: token,
    );
    return Event.fromJson(res);
  }

  static Future<void> deleteEvent(String id) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.deleteJson('/events/$id', token: token);
  }

  static Future<void> addAttendee(String eventId, String name, String studentId) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.postJson('/events/$eventId/attendees', {'name': name, 'studentId': studentId}, token: token);
  }

  static Future<List<AttendanceRecord>> getAttendance() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final list = await c.getJsonList('/attendance', token: token);
    return list.map((r) => AttendanceRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  static Future<AttendanceRecord> markAttendance(String eventId, {String? facultyId}) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await c.postJson(
      '/attendance',
      {
        'eventId': eventId,
        if (facultyId != null) 'facultyId': facultyId,
      },
      token: token,
    );
    return AttendanceRecord.fromJson(res);
  }

  static Future<List<Map<String, dynamic>>> getFaculty() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final list = await c.getJsonList('/faculty', token: token);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> clearAttendance() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.deleteJson('/attendance', token: token);
  }

  static Future<void> deleteAttendanceRecord(String id) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.deleteJson('/attendance/$id', token: token);
  }

  static Future<void> deleteMyAttendance() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.deleteJson('/attendance/me', token: token);
  }

  static Future<List<Map<String, dynamic>>> getUsers() async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final list = await c.getJsonList('/users', token: token);
    return list.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createUser(
    String username,
    String password,
    String role, {
    String? fullName,
    String? studentId,
    String? course,
    String? section,
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return c.postJson(
      '/users',
      {
        'username': username,
        'password': password,
        'role': role,
        if (fullName != null) 'fullName': fullName,
        if (studentId != null) 'studentId': studentId,
        if (course != null) 'course': course,
        if (section != null) 'section': section,
      },
      token: token,
    );
  }

  static Future<void> deleteUser(String id) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    await c.deleteJson('/users/$id', token: token);
  }

  static Future<Map<String, dynamic>> updateUser(
    String userId, {
    String? id,
    String? username,
    String? password,
    String? role,
    bool? isApproved,
    String? fullName,
    String? studentId,
    String? course,
    String? section,
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return c.patchJson(
      '/users/$userId',
      {
        if (id != null) 'id': id,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (role != null) 'role': role,
        if (isApproved != null) 'isApproved': isApproved,
        if (fullName != null) 'fullName': fullName,
        if (studentId != null) 'studentId': studentId,
        if (course != null) 'course': course,
        if (section != null) 'section': section,
      },
      token: token,
    );
  }

  static Future<Map<String, dynamic>> adminResetUserPassword(
    String userId,
    String newPassword,
  ) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return c.postJson(
      '/users/$userId/reset-password',
      {'newPassword': newPassword},
      token: token,
    );
  }
}

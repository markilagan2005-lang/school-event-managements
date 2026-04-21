import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/attendee.dart';
import '../models/attendance.dart';
import 'api_client.dart';

class ApiService {
  static Future<ApiClient> _client() async {
    final base = await ApiClient.getBaseUrl();
    return ApiClient(base);
  }

  static Future<Map<String, dynamic>> register(
    String username,
    String password,
    String role, {
    String? fullName,
    String? studentId,
    String? course,
    String? section,
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
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', res['token'] as String);
    await prefs.setString('current_user', jsonEncode(res['user']));
    return res;
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final c = await _client();
    final res = await c.postJson('/login', {'username': username, 'password': password});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', res['token'] as String);
    await prefs.setString('current_user', jsonEncode(res['user']));
    return res;
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
        date: DateTime.tryParse(e['date'] ?? '') ?? DateTime.now(),
        status: e['status'] ?? 'open',
        startAt: e['startAt'] == null ? null : DateTime.tryParse(e['startAt'].toString()),
        endAt: e['endAt'] == null ? null : DateTime.tryParse(e['endAt'].toString()),
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
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await c.postJson(
      '/events',
      {
        'name': name,
        'date': date.toIso8601String(),
        'status': status,
        if (startAt != null) 'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt.toIso8601String(),
      },
      token: token,
    );
    return Event(
      id: res['id'] ?? '',
      name: res['name'] ?? '',
      date: DateTime.tryParse(res['date'] ?? '') ?? DateTime.now(),
      status: res['status'] ?? status,
      startAt: res['startAt'] == null ? startAt : DateTime.tryParse(res['startAt'].toString()),
      endAt: res['endAt'] == null ? endAt : DateTime.tryParse(res['endAt'].toString()),
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
  }) async {
    final c = await _client();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await c.postJson(
      '/events/$id',
      {
        if (name != null) 'name': name,
        if (date != null) 'date': date.toIso8601String(),
        if (status != null) 'status': status,
        'startAt': startAt?.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
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
}

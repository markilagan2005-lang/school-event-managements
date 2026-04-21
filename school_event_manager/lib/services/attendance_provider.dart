import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/attendance.dart';
import '../utils/uuid.dart';
import 'data_service.dart';
import '../config.dart';
import 'api_service.dart';

final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AsyncValue<List<AttendanceRecord>>>((ref) => AttendanceNotifier(ref));

class AttendanceNotifier extends StateNotifier<AsyncValue<List<AttendanceRecord>>> {
  final Ref ref;

  AttendanceNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadAttendance();
  }

  String _cleanError(Object e) {
    final raw = e.toString();
    final s = raw.startsWith('Exception: ') ? raw.substring('Exception: '.length) : raw;
    final idx = s.indexOf('{');
    if (idx != -1) {
      try {
        final decoded = jsonDecode(s.substring(idx));
        if (decoded is Map && decoded['error'] != null) {
          return decoded['error'].toString();
        }
      } catch (_) {}
    }
    return s;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> loadAttendance() async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final attendance = token == null ? await DataService.getAttendance() : await ApiService.getAttendance();
      state = AsyncValue.data(attendance);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<String> markAttendance(
    String eventId,
    String eventName,
    String studentId,
    String studentName,
    String userId, {
    String? facultyId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        final rec = await ApiService.markAttendance(eventId, facultyId: facultyId);
        await loadAttendance();
        final checkIn = rec.checkInAt ?? rec.timestamp;
        if (rec.status == 'in') {
          final expectedOut = checkIn.add(const Duration(minutes: attendanceTimeoutMinutes));
          final teacher = rec.checkedInByFacultyName.isEmpty ? '' : ' • ${rec.checkedInByFacultyName}';
          return 'Checked in$teacher. Expected out: ${expectedOut.toLocal()}';
        }
        final out = rec.checkOutAt ?? now;
        final teacher = rec.checkedOutByFacultyName.isEmpty ? '' : ' • ${rec.checkedOutByFacultyName}';
        return 'Checked out$teacher: ${out.toLocal()}';
      }

      final existing = await DataService.getAttendance();
      final open = existing.where((r) {
        if (r.eventId != eventId || r.studentId != studentId) return false;
        if (r.checkOutAt != null) return false;
        final checkIn = r.checkInAt ?? r.timestamp;
        return _sameDay(checkIn, now);
      }).cast<AttendanceRecord?>().firstWhere((r) => r != null, orElse: () => null);

      final record = AttendanceRecord(
        id: Uuid.v4(),
        eventId: eventId,
        eventName: eventName,
        studentId: studentId,
        studentName: studentName,
        status: open == null ? 'in' : 'out',
        timestamp: now,
        checkInAt: now,
        checkOutAt: null,
        userId: userId,
      );
      await DataService.addAttendance(record);
      await loadAttendance();
      if (open == null) {
        final expectedOut = now.add(const Duration(minutes: attendanceTimeoutMinutes));
        return 'Checked in. Expected out: ${expectedOut.toLocal()}';
      }
      return 'Checked out: ${now.toLocal()}';
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return _cleanError(e);
    }
  }
}

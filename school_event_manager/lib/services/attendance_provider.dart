import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/attendance.dart';
import '../models/event.dart';
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

  static String _clockLabel(DateTime dt) {
    final local = dt.toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $meridiem';
  }

  AttendanceRecord? _findOpenRecord(
    Iterable<AttendanceRecord> records,
    String eventId,
    String studentId,
    DateTime now,
  ) {
    for (final r in records) {
      if (r.eventId != eventId || r.studentId != studentId) continue;
      if (r.checkOutAt != null) continue;
      final checkIn = r.checkInAt ?? r.timestamp;
      if (_sameDay(checkIn, now)) return r;
    }
    return null;
  }

  // Mirrors the server-side scheduling rules: time in only from the scheduled
  // start, time out only from the scheduled end.
  String? _timingError(Event? event, {required bool isCheckOut, required DateTime now}) {
    if (event == null) return null;
    if (isCheckOut) {
      final end = event.endAt;
      if (end != null && now.isBefore(end)) {
        return 'You can only time out at ${_clockLabel(end)} or later.';
      }
      return null;
    }
    final start = event.startAt;
    if (start != null && now.isBefore(start)) {
      return 'You can only time in at ${_clockLabel(start)} or later.';
    }
    return null;
  }

  bool _isLateCheckIn(Event? event, DateTime now) {
    final start = event?.startAt;
    if (start == null) return false;
    return now.isAfter(start.add(const Duration(minutes: 15)));
  }

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

  Future<Event?> _lookupEvent(String eventId, {required bool online}) async {
    try {
      if (online) {
        final events = await ApiService.getEvents();
        final found = events.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
        return found;
      }
      final offline = await DataService.getEvents();
      final found = offline.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
      return found;
    } catch (_) {
      return null;
    }
  }

  String? _courseEligibilityError(Event event, String studentCourse) {
    final sc = studentCourse.trim();
    if (event.allCourses) return null;
    final allowed = event.courses.map((c) => c.trim()).where((c) => c.isNotEmpty).toSet();
    if (allowed.isEmpty) {
      return 'This event has no courses assigned. Ask an admin to configure it.';
    }
    if (sc.isEmpty) {
      return 'Your account has no course assigned. Ask an admin to set your course before scanning.';
    }
    if (!allowed.contains(sc)) {
      final sorted = allowed.toList()..sort();
      return 'This event is only for ${sorted.join(', ')}. Your course ($sc) cannot scan this QR.';
    }
    return null;
  }

  Future<String> markAttendance(
    String eventId,
    String eventName,
    String studentId,
    String studentName,
    String userId, {
    String? facultyId,
    required String studentCourse,
  }) async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final online = token != null;
      final event = await _lookupEvent(eventId, online: online);
      if (event != null) {
        final err = _courseEligibilityError(event, studentCourse);
        if (err != null) {
          state = AsyncValue.error(Exception(err), StackTrace.current);
          return err;
        }
      }

      // An open same-day record means this scan is a time-out, otherwise a time-in.
      final cached = state.value ?? const <AttendanceRecord>[];
      final open = _findOpenRecord(cached, eventId, studentId, now);
      final timingErr = _timingError(event, isCheckOut: open != null, now: now);
      if (timingErr != null) {
        state = AsyncValue.data(cached);
        return timingErr;
      }

      if (online) {
        final rec = await ApiService.markAttendance(eventId, facultyId: facultyId);
        await loadAttendance();
        final checkIn = rec.checkInAt ?? rec.timestamp;
        if (rec.checkOutAt == null) {
          final expectedOut = rec.expectedOutAt ??
              event?.endAt ??
              checkIn.add(const Duration(minutes: attendanceTimeoutMinutes));
          final teacher = rec.checkedInByFacultyName.isEmpty ? '' : ' • ${rec.checkedInByFacultyName}';
          final late = rec.isLate ? ' • LATE' : '';
          return 'Checked in$late$teacher. Expected out: ${expectedOut.toLocal()}';
        }
        final out = rec.checkOutAt ?? now;
        final teacher = rec.checkedOutByFacultyName.isEmpty ? '' : ' • ${rec.checkedOutByFacultyName}';
        return 'Checked out$teacher: ${out.toLocal()}';
      }

      final existing = await DataService.getAttendance();
      final offlineOpen = _findOpenRecord(existing, eventId, studentId, now);
      final isCheckOut = offlineOpen != null;
      final late = !isCheckOut && _isLateCheckIn(event, now);

      final record = AttendanceRecord(
        id: Uuid.v4(),
        eventId: eventId,
        eventName: eventName,
        studentId: studentId,
        studentName: studentName,
        studentCourse: studentCourse,
        status: isCheckOut ? 'out' : 'in',
        isLate: late,
        expectedOutAt: isCheckOut ? null : event?.endAt,
        timestamp: now,
        checkInAt: now,
        checkOutAt: null,
        userId: userId,
      );
      await DataService.addAttendance(record);
      await loadAttendance();
      if (!isCheckOut) {
        final expectedOut = event?.endAt ??
            now.add(const Duration(minutes: attendanceTimeoutMinutes));
        final lateSuffix = late ? ' • LATE' : '';
        return 'Checked in$lateSuffix. Expected out: ${expectedOut.toLocal()}';
      }
      return 'Checked out: ${now.toLocal()}';
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return _cleanError(e);
    }
  }
}

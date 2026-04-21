import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../models/attendee.dart';
import '../models/event.dart';
import '../models/attendance.dart';

class DataService {
  static Box<String>? _usersBox;
  static Box<String>? _eventsBox;
  static Box<String>? _attendanceBox;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    _usersBox = await Hive.openBox<String>('users');
    _eventsBox = await Hive.openBox<String>('events');
    _attendanceBox = await Hive.openBox<String>('attendance');
  }

  static Future<List<User>> getUsers() async {
    final box = _usersBox!;
    final users = <User>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        users.add(User.fromJson(json));
      }
    }
    return users;
  }

  static Future<void> addUser(User user) async {
    final box = _usersBox!;
    await box.add(jsonEncode(user.toJson()));
  }

  static Future<void> updateUser(User user) async {
    final box = _usersBox!;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) {
        continue;
      }
      final json = jsonDecode(value) as Map<String, dynamic>;
      final existing = User.fromJson(json);
      if (existing.id == user.id) {
        await box.put(key, jsonEncode(user.toJson()));
        break;
      }
    }
  }

  static Future<void> deleteUser(String id) async {
    final box = _usersBox!;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) {
        continue;
      }
      final json = jsonDecode(value) as Map<String, dynamic>;
      final user = User.fromJson(json);
      if (user.id == id) {
        await box.delete(key);
        break;
      }
    }
  }

  static Future<List<Event>> getEvents() async {
    final box = _eventsBox!;
    final events = <Event>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        events.add(Event.fromJson(json));
      }
    }
    return events;
  }

  static Future<void> addEvent(Event event) async {
    final box = _eventsBox!;
    await box.add(jsonEncode(event.toJson()));
  }

  static Future<void> deleteEvent(String id) async {
    final box = _eventsBox!;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) {
        continue;
      }
      final json = jsonDecode(value) as Map<String, dynamic>;
      final event = Event.fromJson(json);
      if (event.id == id) {
        await box.delete(key);
        break;
      }
    }
  }

  static Future<void> addAttendee(String eventId, Attendee attendee) async {
    final events = await getEvents();
    final event = events.firstWhere((e) => e.id == eventId);
    event.attendees.add(attendee);
    await deleteEvent(eventId);
    await addEvent(event);
  }

  static Future<List<AttendanceRecord>> getAttendance() async {
    final box = _attendanceBox!;
    final attendance = <AttendanceRecord>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        final json = jsonDecode(value) as Map<String, dynamic>;
        attendance.add(AttendanceRecord.fromJson(json));
      }
    }
    return attendance;
  }

  static Future<void> addAttendance(AttendanceRecord record) async {
    final box = _attendanceBox!;
    final now = DateTime.now();
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) {
        continue;
      }
      final json = jsonDecode(value) as Map<String, dynamic>;
      final existing = AttendanceRecord.fromJson(json);
      final checkIn = existing.checkInAt ?? existing.timestamp;
      final sameDay = checkIn.year == now.year && checkIn.month == now.month && checkIn.day == now.day;
      if (sameDay && existing.eventId == record.eventId && existing.studentId == record.studentId) {
        if (existing.checkOutAt == null) {
          final updated = AttendanceRecord(
            id: existing.id,
            eventId: existing.eventId,
            eventName: existing.eventName,
            studentId: existing.studentId,
            studentName: existing.studentName,
            status: 'out',
            timestamp: existing.timestamp,
            checkInAt: checkIn,
            checkOutAt: now,
            userId: existing.userId,
          );
          await box.put(key, jsonEncode(updated.toJson()));
        }
        return;
      }
    }
    await box.add(
      jsonEncode(
        AttendanceRecord(
          id: record.id,
          eventId: record.eventId,
          eventName: record.eventName,
          studentId: record.studentId,
          studentName: record.studentName,
          status: 'in',
          timestamp: record.timestamp,
          checkInAt: record.timestamp,
          checkOutAt: null,
          userId: record.userId,
        ).toJson(),
      ),
    );
  }

  static Future<Map<String, dynamic>> getStats() async {
    final attendance = await getAttendance();
    final today = DateTime.now();
    final todayAttendance = attendance.where((a) => 
      a.timestamp.year == today.year && 
      a.timestamp.month == today.month &&
      a.timestamp.day == today.day
    ).length;
    return {
      'total': attendance.length,
      'today': todayAttendance,
    };
  }
}

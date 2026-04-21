import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/attendee.dart';
import '../utils/uuid.dart';
import 'data_service.dart';
import 'api_service.dart';

final eventProvider = StateNotifierProvider<EventNotifier, AsyncValue<List<Event>>>((ref) => EventNotifier(ref));

class EventNotifier extends StateNotifier<AsyncValue<List<Event>>> {
  final Ref ref;

  EventNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadEvents();
  }

  Future<void> loadEvents() async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final events = token == null ? await DataService.getEvents() : await ApiService.getEvents();
      state = AsyncValue.data(events);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<Event?> addEvent(
    String name,
    DateTime date, {
    DateTime? startAt,
    DateTime? endAt,
    String status = 'open',
  }) async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        final event = Event(
          id: Uuid.v4(),
          name: name,
          date: date,
          status: status,
          startAt: startAt,
          endAt: endAt,
        );
        await DataService.addEvent(event);
        await loadEvents();
        return event;
      } else {
        final created = await ApiService.addEvent(name, date, startAt: startAt, endAt: endAt, status: status);
        await loadEvents();
        return created;
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<Event?> updateEvent(
    String id, {
    String? name,
    DateTime? date,
    String? status,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        final events = await DataService.getEvents();
        final idx = events.indexWhere((e) => e.id == id);
        if (idx == -1) return null;
        final current = events[idx];
        final next = Event(
          id: current.id,
          name: name ?? current.name,
          date: date ?? current.date,
          status: status ?? current.status,
          startAt: startAt,
          endAt: endAt,
          attendees: current.attendees,
        );
        await DataService.deleteEvent(id);
        await DataService.addEvent(next);
        await loadEvents();
        return next;
      } else {
        final updated = await ApiService.updateEvent(
          id,
          name: name,
          date: date,
          status: status,
          startAt: startAt,
          endAt: endAt,
        );
        await loadEvents();
        return updated;
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<void> deleteEvent(String id) async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        await DataService.deleteEvent(id);
      } else {
        await ApiService.deleteEvent(id);
      }
      await loadEvents();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> addAttendee(String eventId, String name, String studentId) async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        final attendee = Attendee(name: name, studentId: studentId);
        await DataService.addAttendee(eventId, attendee);
      } else {
        await ApiService.addAttendee(eventId, name, studentId);
      }
      await loadEvents();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

import 'attendee.dart';

class Event {
  final String id;
  final String name;
  final DateTime date;
  final String status; // draft | open | closed
  final DateTime? startAt;
  final DateTime? endAt;
  final String description;
  final String posterImageUrl;
  List<Attendee> attendees;

  Event({
    required this.id,
    required this.name,
    required this.date,
    this.status = 'open',
    this.startAt,
    this.endAt,
    this.description = '',
    this.posterImageUrl = '',
    this.attendees = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'status': status,
    'startAt': startAt?.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'description': description,
    'posterImageUrl': posterImageUrl,
    'attendees': attendees.map((a) => a.toJson()).toList(),
  };

  static DateTime _toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  static DateTime? _parse(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return _toLocal(parsed);
  }

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    date: _parse(json['date']) ?? DateTime.now(),
    status: json['status'] ?? 'open',
    startAt: _parse(json['startAt']),
    endAt: _parse(json['endAt']),
    description: json['description']?.toString() ?? '',
    posterImageUrl: json['posterImageUrl']?.toString() ?? '',
    attendees: (json['attendees'] as List<dynamic>?)
        ?.map((a) => Attendee.fromJson(a as Map<String, dynamic>))
        .toList() ?? [],
  );
}

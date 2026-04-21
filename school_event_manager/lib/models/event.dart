import 'attendee.dart';

class Event {
  final String id;
  final String name;
  final DateTime date;
  final String status; // draft | open | closed
  final DateTime? startAt;
  final DateTime? endAt;
  List<Attendee> attendees;

  Event({
    required this.id,
    required this.name,
    required this.date,
    this.status = 'open',
    this.startAt,
    this.endAt,
    this.attendees = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'status': status,
    'startAt': startAt?.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'attendees': attendees.map((a) => a.toJson()).toList(),
  };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
    status: json['status'] ?? 'open',
    startAt: json['startAt'] == null ? null : DateTime.tryParse(json['startAt'].toString()),
    endAt: json['endAt'] == null ? null : DateTime.tryParse(json['endAt'].toString()),
    attendees: (json['attendees'] as List<dynamic>?)
        ?.map((a) => Attendee.fromJson(a as Map<String, dynamic>))
        .toList() ?? [],
  );
}

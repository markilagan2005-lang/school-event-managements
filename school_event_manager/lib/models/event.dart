import 'attendee.dart';

class Event {
  final String id;
  final String name;
  final DateTime date;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final String description;
  final String posterImageUrl;
  final String location;
  final bool isCategory;
  final String? parentId;
  final bool allCourses;
  final List<String> courses;
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
    this.location = '',
    this.isCategory = false,
    this.parentId,
    this.allCourses = true,
    this.courses = const [],
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
    'location': location,
    'isCategory': isCategory,
    'parentId': parentId,
    'allCourses': allCourses,
    'courses': List<String>.from(courses),
    'attendees': attendees.map((a) => a.toJson()).toList(),
  };

  Event copyWith({
    String? id,
    String? name,
    DateTime? date,
    String? status,
    DateTime? startAt,
    DateTime? endAt,
    String? description,
    String? posterImageUrl,
    String? location,
    bool? isCategory,
    String? parentId,
    bool? clearParentId = false,
    bool? allCourses,
    List<String>? courses,
    List<Attendee>? attendees,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      status: status ?? this.status,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      description: description ?? this.description,
      posterImageUrl: posterImageUrl ?? this.posterImageUrl,
      location: location ?? this.location,
      isCategory: isCategory ?? this.isCategory,
      parentId: clearParentId == true ? null : (parentId ?? this.parentId),
      allCourses: allCourses ?? this.allCourses,
      courses: courses ?? this.courses,
      attendees: attendees ?? this.attendees,
    );
  }

  static DateTime _toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  static DateTime? _parse(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return _toLocal(parsed);
  }

  static List<String> _parseCourses(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: true);
  }

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    date: _parse(json['date']) ?? DateTime.now(),
    status: json['status']?.toString() ?? 'open',
    startAt: _parse(json['startAt']),
    endAt: _parse(json['endAt']),
    description: json['description']?.toString() ?? '',
    posterImageUrl: json['posterImageUrl']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    isCategory: json['isCategory'] == true,
    parentId: (json['parentId']?.toString().isNotEmpty == true) ? json['parentId'].toString() : null,
    allCourses: json['allCourses'] == true || json['allCourses'] == null,
    courses: _parseCourses(json['courses']),
    attendees: (json['attendees'] as List<dynamic>?)
        ?.map((a) => Attendee.fromJson(a as Map<String, dynamic>))
        .toList() ?? [],
  );
}

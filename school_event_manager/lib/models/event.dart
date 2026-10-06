import 'attendee.dart';

class Event {
  static const List<String> _canonicalCourses = [
    'Bachelor of Science in Criminology',
    'Bachelor of Science in Information System',
    'Bachelor of Science in Psychology',
    'Bachelor of Science in Accounting Information System',
    'Bachelor of Secondary Education',
    'Bachelor of Science in Accountancy',
  ];
  static final Set<String> _canonicalCoursesSet = Set<String>.unmodifiable(_canonicalCourses);

  static bool _coursesEqualCanonicalFullSet(Iterable<String> list) {
    if (list.length != _canonicalCourses.length) return false;
    final set = list is Set<String> ? list : list.toSet();
    return set.length == _canonicalCourses.length &&
        set.containsAll(_canonicalCoursesSet);
  }

  static List<String> _sanitizeCourses(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final rawItem in raw) {
      final s = rawItem.trim();
      if (s.isEmpty) continue;
      if (!_canonicalCoursesSet.contains(s)) continue;
      if (seen.contains(s)) continue;
      seen.add(s);
      out.add(s);
    }
    return List<String>.unmodifiable(out);
  }

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
    bool allCourses = true,
    List<String> courses = const [],
    this.attendees = const [],
  })  : courses = List<String>.unmodifiable(_sanitizeCourses(courses)),
        allCourses = _coursesEqualCanonicalFullSet(courses) ? true : (allCourses == true && courses.isEmpty);

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
    final nextCourses = courses ?? this.courses;
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
      courses: nextCourses,
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

  static bool _parseBool(dynamic raw, {bool nullDefault = true}) {
    if (raw == null) return nullDefault;
    if (raw is bool) return raw;
    if (raw is num) return raw == 1;
    if (raw is String) {
      final s = raw.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return nullDefault;
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
    allCourses: _parseBool(json['allCourses'], nullDefault: true),
    courses: _parseCourses(json['courses']),
    attendees: (json['attendees'] as List<dynamic>?)
        ?.map((a) => Attendee.fromJson(a as Map<String, dynamic>))
        .toList() ?? [],
  );
}

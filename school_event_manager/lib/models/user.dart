class User {
  final String id;
  final String username;
  String password;
  final String role; // 'admin' or 'student'
  final bool isApproved;
  final String fullName;
  final String studentId;
  final String professorId;
  final String studentType;
  final String course;
  final List<String> courses;
  final String section;
  final List<String> handledCourses;

  User({
    required this.id,
    required this.username,
    required this.password,
    required this.role,
    this.isApproved = true,
    this.fullName = '',
    this.studentId = '',
    this.professorId = '',
    this.studentType = 'regular',
    this.course = '',
    this.courses = const [],
    this.section = '',
    this.handledCourses = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'password': password,
    'role': role,
    'isApproved': isApproved,
    'fullName': fullName,
    'studentId': studentId,
    'professorId': professorId,
    'studentType': studentType,
    'course': course,
    'courses': List<String>.from(courses),
    'section': section,
    'handledCourses': List<String>.from(handledCourses),
  };

  factory User.fromJson(Map<String, dynamic> json) {
    // Canonical handledCourses format on the wire = FULL degree names
    // ("Bachelor of Science in Psychology", ...). During a short window after the
    // new registration dashboard shipped, the client accidentally sent SHORT codes
    // ("BSP", "BSC", ...) which the server silently dropped. The server now coerces
    // both formats → full names at write time, but any records already persisted
    // in Mongo with short codes are normalized on client read here for safety.
    const kShortToFull = <String, String>{
      'BSC': 'Bachelor of Science in Criminology',
      'BSIS': 'Bachelor of Science in Information System',
      'BSP': 'Bachelor of Science in Psychology',
      'BSAIS': 'Bachelor of Science in Accounting Information System',
      'BSED': 'Bachelor of Secondary Education',
      'BSA': 'Bachelor of Science in Accountancy',
      'BSCE': 'Bachelor of Science in Civil Engineering',
      'BSBA': 'Bachelor of Science in Business Administration',
      'CAD': 'Communication Arts Division',
    };
    const kFullSet = <String>{
      'Bachelor of Science in Criminology',
      'Bachelor of Science in Information System',
      'Bachelor of Science in Psychology',
      'Bachelor of Science in Accounting Information System',
      'Bachelor of Secondary Education',
      'Bachelor of Science in Accountancy',
      'Bachelor of Science in Civil Engineering',
      'Bachelor of Science in Business Administration',
      'Communication Arts Division',
    };
    List<String> parsedStudentCourses;
    final rawCourses = json['courses'];
    if (rawCourses is List) {
      final seen = <String>{};
      final out = <String>[];
      for (final entry in rawCourses) {
        if (entry is! String) continue;
        final s = entry.trim();
        if (!kFullSet.contains(s) || seen.contains(s)) continue;
        seen.add(s);
        out.add(s);
      }
      parsedStudentCourses = out;
    } else {
      final singleCourse = (json['course'] ?? '').toString().trim();
      parsedStudentCourses = kFullSet.contains(singleCourse) ? <String>[singleCourse] : const [];
    }
    List<String> parsedList;
    final raw = json['handledCourses'];
    if (raw is List) {
      final seen = <String>{};
      final out = <String>[];
      for (final entry in raw) {
        if (entry is! String) continue;
        final s = entry.trim();
        if (s.isEmpty) continue;
        final full = kShortToFull[s] ?? (kFullSet.contains(s) ? s : null);
        if (full == null) continue;
        if (seen.contains(full)) continue;
        seen.add(full);
        out.add(full);
      }
      parsedList = out;
    } else {
      parsedList = const [];
    }
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      role: json['role'] ?? '',
      isApproved: (json['role'] ?? '') == 'faculty'
          ? json['isApproved'] == true
          : (json['isApproved'] == false ? false : true),
      fullName: json['fullName'] ?? '',
      studentId: json['studentId'] ?? '',
      professorId: json['professorId'] ?? '',
      studentType: json['studentType'] == 'irregular' ? 'irregular' : 'regular',
      course: json['course'] ?? '',
      courses: parsedStudentCourses,
      section: json['section'] ?? '',
      handledCourses: parsedList,
    );
  }

  List<String> get effectiveStudentCourses {
    if (courses.isNotEmpty) return List<String>.from(courses);
    final single = course.trim();
    return single.isEmpty ? const [] : <String>[single];
  }

  bool get isIrregularStudent => role == 'student' && studentType == 'irregular';

  User copyWith({
    String? id,
    String? username,
    String? password,
    String? role,
    bool? isApproved,
    String? fullName,
    String? studentId,
    String? professorId,
    String? studentType,
    String? course,
    List<String>? courses,
    String? section,
    List<String>? handledCourses,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      fullName: fullName ?? this.fullName,
      studentId: studentId ?? this.studentId,
      professorId: professorId ?? this.professorId,
      studentType: studentType ?? this.studentType,
      course: course ?? this.course,
      courses: courses ?? List<String>.from(this.courses),
      section: section ?? this.section,
      handledCourses: handledCourses ?? List<String>.from(this.handledCourses),
    );
  }
}

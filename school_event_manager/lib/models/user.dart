class User {
  final String id;
  final String username;
  String password;
  final String role; // 'admin' or 'student'
  final bool isApproved;
  final String fullName;
  final String studentId;
  final String course;
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
    this.course = '',
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
    'course': course,
    'section': section,
    'handledCourses': List<String>.from(handledCourses),
  };

  factory User.fromJson(Map<String, dynamic> json) {
    List<String> parsedList;
    final raw = json['handledCourses'];
    if (raw is List) {
      parsedList = raw.whereType<String>().toList();
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
      course: json['course'] ?? '',
      section: json['section'] ?? '',
      handledCourses: parsedList,
    );
  }

  User copyWith({
    String? id,
    String? username,
    String? password,
    String? role,
    bool? isApproved,
    String? fullName,
    String? studentId,
    String? course,
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
      course: course ?? this.course,
      section: section ?? this.section,
      handledCourses: handledCourses ?? List<String>.from(this.handledCourses),
    );
  }
}

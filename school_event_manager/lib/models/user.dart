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
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
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
  );
}

class User {
  final String id;
  final String username;
  String password;
  final String role; // 'admin' or 'student'
  final String fullName;
  final String studentId;
  final String course;
  final String section;

  User({
    required this.id,
    required this.username,
    required this.password,
    required this.role,
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
    fullName: json['fullName'] ?? '',
    studentId: json['studentId'] ?? '',
    course: json['course'] ?? '',
    section: json['section'] ?? '',
  );
}

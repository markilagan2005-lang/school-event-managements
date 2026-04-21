class AttendanceRecord {
  final String id;
  final String eventId;
  final String eventName;
  final String studentId;
  final String studentName;
  final String studentCourse;
  final String studentSection;
  final String status;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final DateTime timestamp;
  final String userId;
  final String checkedInByFacultyId;
  final String checkedInByFacultyName;
  final String checkedOutByFacultyId;
  final String checkedOutByFacultyName;

  AttendanceRecord({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.studentId,
    required this.studentName,
    this.studentCourse = '',
    this.studentSection = '',
    this.status = 'present',
    this.checkInAt,
    this.checkOutAt,
    required this.timestamp,
    required this.userId,
    this.checkedInByFacultyId = '',
    this.checkedInByFacultyName = '',
    this.checkedOutByFacultyId = '',
    this.checkedOutByFacultyName = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'eventName': eventName,
        'studentId': studentId,
        'studentName': studentName,
        'studentCourse': studentCourse,
        'studentSection': studentSection,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        'checkInAt': checkInAt?.toIso8601String(),
        'checkOutAt': checkOutAt?.toIso8601String(),
        'userId': userId,
        'checkedInByFacultyId': checkedInByFacultyId,
        'checkedInByFacultyName': checkedInByFacultyName,
        'checkedOutByFacultyId': checkedOutByFacultyId,
        'checkedOutByFacultyName': checkedOutByFacultyName,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id: json['id'] ?? '',
        eventId: json['eventId'] ?? '',
        eventName: json['eventName'] ?? '',
        studentId: json['studentId'] ?? '',
        studentName: json['studentName'] ?? '',
        studentCourse: json['studentCourse'] ?? '',
        studentSection: json['studentSection'] ?? '',
        status: json['status'] ?? 'present',
        timestamp: DateTime.tryParse(json['timestamp'] ?? json['checkInAt'] ?? '') ?? DateTime.now(),
        checkInAt: DateTime.tryParse(json['checkInAt'] ?? json['timestamp'] ?? ''),
        checkOutAt: DateTime.tryParse(json['checkOutAt'] ?? ''),
        userId: json['userId'] ?? '',
        checkedInByFacultyId: json['checkedInByFacultyId'] ?? '',
        checkedInByFacultyName: json['checkedInByFacultyName'] ?? '',
        checkedOutByFacultyId: json['checkedOutByFacultyId'] ?? '',
        checkedOutByFacultyName: json['checkedOutByFacultyName'] ?? '',
      );
}

class Attendee {
  final String name;
  final String studentId;

  Attendee({
    required this.name,
    required this.studentId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'studentId': studentId,
  };

  factory Attendee.fromJson(Map<String, dynamic> json) => Attendee(
    name: json['name'] ?? '',
    studentId: json['studentId'] ?? '',
  );
}

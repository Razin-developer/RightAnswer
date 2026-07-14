class Subject {
  final String id;
  final String name;
  final DateTime createdAt;

  Subject({required this.id, required this.name, required this.createdAt});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Subject.fromMap(Map<String, dynamic> map) => Subject(
    id: map['id'] as String,
    name: map['name'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}

import 'package:cloud_firestore/cloud_firestore.dart';

class Doctor {
  final String id;
  final String name;
  final String email;
  final String specialization;
  final String role;
  final String password;
  final DateTime createdAt;

  Doctor({
    required this.id,
    required this.name,
    required this.email,
    required this.specialization,
    required this.role,
    this.password = '',
    required this.createdAt,
  });

  factory Doctor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Doctor(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      specialization: data['specialization'] ?? 'General Practitioner',
      role: data['role'] ?? 'doctor',
      password: data['password'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'specialization': specialization,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; 
import 'package:flutter/material.dart';

class OfflineService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- 1. DASHBOARD DATA (Semesters & Courses) ---
  static Future<void> saveSemesters(List<Semester> list) async {
    final jsonList = list.map((s) => {'id': s.id, 'name': s.name}).toList();
    await _prefs.setString('offline_semesters', jsonEncode(jsonList));
  }

  static Future<List<Semester>> getSemesters() async {
    final String? encoded = _prefs.getString('offline_semesters');
    if (encoded == null) return [];
    final List<dynamic> decoded = jsonDecode(encoded);
    return decoded.map((j) => Semester(id: j['id'], name: j['name'])).toList();
  }

  static Future<void> saveCourses(String semesterId, List<Course> list) async {
    final jsonList = list.map((c) => {
      'id': c.id, 'code': c.code, 'name': c.name,
      'section': c.section, 'instructorId': c.instructorId,
      'instructorName': c.instructorName, 'semesterId': c.semesterId,
      'themeColor': c.themeColor.value,
      'enrolledStudentIds': c.enrolledStudentIds
    }).toList();
    await _prefs.setString('offline_courses_$semesterId', jsonEncode(jsonList));
  }

  static Future<List<Course>> getCourses(String semesterId) async {
    final String? encoded = _prefs.getString('offline_courses_$semesterId');
    if (encoded == null) return [];
    final List<dynamic> decoded = jsonDecode(encoded);
    return decoded.map((j) => Course(
      id: j['id'], code: j['code'], name: j['name'],
      section: j['section'], instructorId: j['instructorId'],
      instructorName: j['instructorName'], semesterId: j['semesterId'],
      themeColor: Color(j['themeColor']),
    )..enrolledStudentIds = List<String>.from(j['enrolledStudentIds'])).toList();
  }

  // --- 2. CLASSWORKS ---
  static Future<void> saveClassworks(String courseId, List<Classwork> list) async {
    final jsonList = list.map((item) {
      return {
        'id': item.id,
        'courseId': item.courseId,
        'title': item.title,
        'description': item.description,
        'type': item.type.index,
        'dueDate': item.dueDate?.toIso8601String(),
        'postedDate': item.postedDate.toIso8601String(),
        'score': item.score,
        'isCompleted': item.isCompleted,
        // NEW: Save Attachments
        'attachmentUrls': item.attachmentUrls, 
        'questions': item.questions.map((q) => {
          'id': q.id, 'text': q.text, 'type': q.type.index,
          'options': q.options, 'correctOptionIndex': q.correctOptionIndex,
        }).toList(),
      };
    }).toList();

    await _prefs.setString('offline_classworks_$courseId', jsonEncode(jsonList));
  }

  static Future<List<Classwork>> getClassworks(String courseId) async {
    final String? encoded = _prefs.getString('offline_classworks_$courseId');
    if (encoded == null) return [];
    final List<dynamic> decoded = jsonDecode(encoded);

    return decoded.map((json) {
      List<Question> questions = [];
      if (json['questions'] != null) {
        questions = (json['questions'] as List).map((q) {
          return Question(
            id: q['id'], text: q['text'], type: QuestionType.values[q['type']],
            options: List<String>.from(q['options']), correctOptionIndex: q['correctOptionIndex'],
          );
        }).toList();
      }

      return Classwork(
        id: json['id'],
        courseId: json['courseId'],
        title: json['title'],
        description: json['description'] ?? '',
        type: ClassworkType.values[json['type']],
        dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
        postedDate: DateTime.parse(json['postedDate']),
        score: json['score'],
        isCompleted: json['isCompleted'] ?? false,
        attachmentUrls: List<String>.from(json['attachmentUrls'] ?? []), // RESTORE FILES
        questions: questions,
      );
    }).toList();
  }
}
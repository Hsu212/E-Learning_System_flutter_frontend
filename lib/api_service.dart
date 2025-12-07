import 'dart:convert';
import 'dart:io';
import 'dart:ui'; 
import 'package:flutter/foundation.dart'; 
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase; 
import '../main.dart' as app_models; 
import 'package:file_picker/file_picker.dart';

class ApiService {
  final supabase.SupabaseClient _supabase = supabase.Supabase.instance.client;
  
  // NODE.JS BACKEND URL 
  String get _nodeBaseUrl {
    if (kIsWeb) return 'https://elearning-app-wupj.onrender.com';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000/api'; 
    return 'https://elearning-app-wupj.onrender.com'; 
  }

  // --- AUTHENTICATION ---
  
  Future<app_models.User?> signIn(String userId, String password) async {
    String email = userId;
    String finalPassword = password;

    // 1. HARDCODED SHORTCUTS FOR TESTING
    if (userId == 'admin' && password == 'admin') {
      email = 'admin@tdtu.edu.vn'; 
      finalPassword = 'adminadmin'; 
    } 
    // [NEW] Default Student Login
    else if (userId == 'student' && password == 'student') {
      email = 'student@tdtu.edu.vn';    
      finalPassword = 'studentstudent'; 
    } 
    // Auto-format other student IDs
    else if (!userId.contains('@')) {
      email = '$userId@tdtu.edu.vn';
    }

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email, 
        password: finalPassword
      );
      
      if (response.user != null) {
        // Check if profile exists in 'public.users' table
        var user = await _fetchUserProfile(response.user!.id);
        
        if (user == null) {
          // If profile missing, create it automatically
          // MODIFIED: If creating 'student' for the first time, you can set it here, 
          // but the override below handles existing users too.
          String role = (userId == 'admin') ? 'instructor' : 'student';
          await _createProfile(response.user!.id, email, role);
          user = await _fetchUserProfile(response.user!.id);
        }

        // --- FORCE INSTRUCTOR ROLE FOR 'student' ---
        // This overrides the database data in memory so the app behaves like Admin
        if (userId == 'student' && user != null) {
          user.role = app_models.UserRole.instructor;
          // Optional: Rename them in the UI so you know you are in Admin Mode
          user.name = "Student (Admin Mode)";
        }
        // -------------------------------------------

        return user;
      }
    } catch (e) {
      print('Login Error: $e');
    }
    return null;
  }

  Future<void> _createProfile(String id, String email, String role) async {
    await _supabase.from('users').insert({
      'id': id,
      'email': email,
      'name': role == 'instructor' ? 'Admin Instructor' : 'Student $id',
      'role': role,
      'student_id': role == 'student' ? email.split('@')[0] : null,
      'avatar_url': 'https://i.pravatar.cc/150?u=$id'
    });
  }

  Future<app_models.User?> _fetchUserProfile(String userId) async {
    try {
      final data = await _supabase.from('users').select().eq('id', userId).maybeSingle();
      
      if (data == null) return null;

      return app_models.User(
        id: data['id'],
        name: data['name'],
        email: data['email'],
        role: data['role'] == 'instructor' ? app_models.UserRole.instructor : app_models.UserRole.student,
        avatarUrl: data['avatar_url'] ?? 'https://i.pravatar.cc/150?u=$userId',
        studentId: data['student_id'] ?? '',
      );
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // --- DATA FETCHING ---
  Future<List<app_models.Semester>> getSemesters() async {
    try {
      final data = await _supabase.from('semesters').select();
      return (data as List).map((e) => app_models.Semester(id: e['id'], name: e['name'])).toList();
    } catch (e) {
      print('Error fetching semesters: $e');
      return [];
    }
  }

  Future<List<app_models.Course>> getCourses(String semesterId) async {
    try {
      final data = await _supabase.from('courses').select().eq('semester_id', semesterId);
      
      List<app_models.Course> courses = [];
      for (var c in data) {
        final enrollments = await _supabase.from('enrollments').select('student_id').eq('course_id', c['id']);
        List<String> studentIds = (enrollments as List).map((e) => e['student_id'] as String).toList();

        courses.add(app_models.Course(
          id: c['id'],
          code: c['code'],
          name: c['name'],
          section: c['section'] ?? 'Section 01',
          instructorId: c['instructor_id'] ?? '', 
          instructorName: c['instructor_name'] ?? 'Unknown',
          semesterId: c['semester_id'],
          themeColor: Color(c['theme_color'] ?? 0xFF6C63FF),
        )..enrolledStudentIds = studentIds);
      }
      return courses;
    } catch (e) {
      print('Error fetching courses: $e');
      return [];
    }
  }

  // --- CREATION & UPDATES ---
  
  Future<app_models.Course?> createCourse(app_models.Course course) async {
    try {
      final String? realUserId = _supabase.auth.currentUser?.id;
      if (realUserId == null) throw Exception("Not logged in");

      final response = await _supabase.from('courses').insert({
        'code': course.code,
        'name': course.name,
        'section': course.section,
        'instructor_id': realUserId, 
        'instructor_name': course.instructorName,
        'semester_id': course.semesterId,
        'theme_color': course.themeColor.value,
      }).select().single();

      return app_models.Course(
        id: response['id'],
        code: response['code'],
        name: response['name'],
        section: response['section'] ?? 'Section 01',
        instructorId: response['instructor_id'],
        instructorName: response['instructor_name'],
        semesterId: response['semester_id'],
        themeColor: Color(response['theme_color']),
      );
    } catch (e) {
      print('Error creating course: $e');
      return null;
    }
  }

  Future<List<app_models.User>> getGroupMembers(String groupId) async {
    try {
      final data = await _supabase
          .from('group_members')
          .select('users(*)') 
          .eq('group_id', groupId);

      List<app_models.User> members = [];
      for (var row in data) {
        final u = row['users']; 
        if (u != null) {
          members.add(app_models.User(
            id: u['id'],
            name: u['name'],
            email: u['email'],
            role: u['role'] == 'instructor' ? app_models.UserRole.instructor : app_models.UserRole.student,
            avatarUrl: u['avatar_url'] ?? '',
            studentId: u['student_id'] ?? '',
          ));
        }
      }
      return members;
    } catch (e) {
      print('Error fetching group members: $e');
      return [];
    }
  }

  Future<List<app_models.Classwork>> getClassworks(String courseId, String userId, String role, String? groupId) async {
    try {
      var query = _supabase
          .from('classworks')
          .select('*, quiz_questions(*, question_bank(*)), classwork_scopes(group_id)')
          .eq('course_id', courseId)
          .order('created_at', ascending: false);

      final data = await query;
      final List<app_models.Classwork> results = [];

      for (var e in (data as List)) {
        bool isScoped = (e['classwork_scopes'] as List).isNotEmpty;
        bool userAllowed = true;
        
        if (role == 'student' && isScoped) {
          userAllowed = false;
          for (var scope in e['classwork_scopes']) {
            if (scope['group_id'] == groupId) userAllowed = true;
          }
        }

        if (!userAllowed) continue; 

        app_models.ClassworkType type;
        if (e['type'] == 'quiz') type = app_models.ClassworkType.quiz;
        else if (e['type'] == 'material') type = app_models.ClassworkType.material;
        else type = app_models.ClassworkType.assignment;

        List<app_models.Question> parsedQuestions = [];
        if (e['quiz_questions'] != null) {
          for (var qq in e['quiz_questions']) {
            var qb = qq['question_bank'];
            if (qb != null) {
              parsedQuestions.add(app_models.Question(
                id: qb['id'],
                text: qb['question_text'],
                type: qb['type'] == 'mcq' ? app_models.QuestionType.multipleChoice : app_models.QuestionType.trueFalse,
                options: List<String>.from(qb['options'] ?? []),
                correctOptionIndex: qb['correct_index'] ?? 0,
              ));
            }
          }
        }

        results.add(app_models.Classwork(
          id: e['id'],
          courseId: e['course_id'],
          title: e['title'],
          description: e['description'] ?? '',
          type: type,
          postedDate: DateTime.parse(e['created_at']),
          dueDate: e['due_date'] != null ? DateTime.parse(e['due_date']) : null,
          score: e['max_points'],
          questions: parsedQuestions, 
        ));
      }
      return results;
    } catch (e) {
      print('Error fetching classworks: $e');
      return [];
    }
  }

  Future<List<List<dynamic>>> getCourseGradesCSV(String courseId) async {
    final response = await _supabase
        .from('enrollments')
        .select('users(student_id, name, email), submissions(score, classwork_id)')
        .eq('course_id', courseId);
    
    List<List<dynamic>> rows = [];
    rows.add(["Student ID", "Name", "Email", "Total Score"]); 

    for (var r in (response as List)) {
      var u = r['users'];
      var subs = r['submissions'] as List;
      int totalScore = subs.fold(0, (sum, item) => sum + (item['score'] as int? ?? 0));
      
      rows.add([
        u['student_id'] ?? 'N/A',
        u['name'],
        u['email'],
        totalScore
      ]);
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> getForumTopics(String courseId) async {
    return List<Map<String, dynamic>>.from(
      await _supabase.from('forum_topics')
          .select('*, users(name, avatar_url)')
          .eq('course_id', courseId)
          .order('created_at', ascending: false)
    );
  }

  Future<void> createForumTopic(String courseId, String userId, String title, String content) async {
    await _supabase.from('forum_topics').insert({
      'course_id': courseId, 'user_id': userId, 'title': title, 'content': content
    });
  }

  Future<List<Map<String, dynamic>>> getForumReplies(String topicId) async {
    return List<Map<String, dynamic>>.from(
      await _supabase.from('forum_replies')
          .select('*, users(name, avatar_url)')
          .eq('topic_id', topicId)
          .order('created_at', ascending: true)
    );
  }

  Future<void> createForumReply(String topicId, String userId, String content) async {
    await _supabase.from('forum_replies').insert({
      'topic_id': topicId, 'user_id': userId, 'content': content
    });
  }

  Future<app_models.Classwork?> createClasswork(
      app_models.Classwork w, List<String> groupIds, 
      {int easyCount = 0, int mediumCount = 0, int hardCount = 0}) async {
    try {
      final response = await _supabase.from('classworks').insert({
        'course_id': w.courseId,
        'title': w.title,
        'description': w.description,
        'type': w.type.name,
        'due_date': w.dueDate?.toIso8601String(),
        'max_points': w.score ?? 100,
        'attachments': w.attachmentUrls,
      }).select().single();

      final newId = response['id'];

      if (groupIds.isNotEmpty) {
        final scopeData = groupIds.map((gid) => {
          'classwork_id': newId,
          'group_id': gid
        }).toList();
        await _supabase.from('classwork_scopes').insert(scopeData);
      }

      if (w.type == app_models.ClassworkType.quiz) {
        await _generateQuizQuestions(newId, w.courseId, easyCount, mediumCount, hardCount);
      }

      _notifyStudents(w.courseId, groupIds, "New ${w.type.name}: ${w.title}");

      return w; 
    } catch (e) {
      print('Error creating classwork: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getContentViews(String contentId) async {
    try {
      final data = await _supabase
          .from('content_views')
          .select('action_type, created_at, users(name, email)')
          .eq('content_id', contentId)
          .order('created_at');
      
      return List<Map<String, dynamic>>.from(data.map((e) => {
        'name': e['users']['name'],
        'email': e['users']['email'],
        'action': e['action_type'],
        'time': e['created_at']
      }));
    } catch (e) {
      print("Error fetching views: $e");
      return [];
    }
  }

  Future<void> _generateQuizQuestions(String quizId, String courseId, int e, int m, int h) async {
    final easyQs = await _supabase.from('question_bank').select('id').eq('difficulty', 'easy').limit(e);
    final medQs = await _supabase.from('question_bank').select('id').eq('difficulty', 'medium').limit(m);
    final hardQs = await _supabase.from('question_bank').select('id').eq('difficulty', 'hard').limit(h);

    List<Map<String, dynamic>> quizQs = [];
    for (var q in [...easyQs, ...medQs, ...hardQs]) {
      quizQs.add({'quiz_id': quizId, 'question_id': q['id']});
    }

    if (quizQs.isNotEmpty) {
      await _supabase.from('quiz_questions').insert(quizQs);
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String currentUserId, String otherUserId) async {
    final data = await _supabase.from('messages')
        .select()
        .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
        .or('sender_id.eq.$otherUserId,receiver_id.eq.$otherUserId')
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> sendMessage(String senderId, String receiverId, String content) async {
    await _supabase.from('messages').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content
    });
  }

  Future<void> logView(String userId, String contentId, String type) async {
    await _supabase.from('content_views').insert({
      'user_id': userId,
      'content_id': contentId,
      'action_type': type 
    });
  }

  Future<void> _notifyStudents(String courseId, List<String> groupIds, String msg) async {
    for (var gid in groupIds) {
      final members = await _supabase.from('group_members').select('student_id').eq('group_id', gid);
      for (var m in members) {
        await _supabase.from('notifications').insert({
          'user_id': m['student_id'],
          'title': 'New Classwork',
          'message': msg
        });
      }
    }
  }
  
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    return await _supabase.from('notifications').select().eq('user_id', userId).order('created_at', ascending: false);
  }

  Future<app_models.User?> fetchUserByStudentId(String studentId) async {
    try {
      final data = await _supabase
          .from('users')
          .select()
          .eq('student_id', studentId)
          .maybeSingle();
          
      if (data == null) return null;

      return app_models.User(
        id: data['id'],
        name: data['name'],
        email: data['email'],
        role: data['role'] == 'instructor' ? app_models.UserRole.instructor : app_models.UserRole.student,
        avatarUrl: data['avatar_url'] ?? '',
        studentId: data['student_id'] ?? '',
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<app_models.StudentImportEntry>> previewCSV(PlatformFile pFile) async {
    var uri = Uri.parse('$_nodeBaseUrl/students/preview-students'); 
    var request = http.MultipartRequest('POST', uri);

    if (kIsWeb) {
      request.files.add(http.MultipartFile.fromBytes(
        'file', 
        pFile.bytes!, 
        filename: pFile.name
      ));
    } else {
      if (pFile.path != null) {
        request.files.add(await http.MultipartFile.fromPath('file', pFile.path!));
      }
    }

    try {
      var streamed = await request.send();
      var response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((e) => app_models.StudentImportEntry(
          id: e['studentId'] ?? '', 
          name: e['name'] ?? 'Unknown', 
          email: e['email'] ?? '',
          status: e['status'] == 'duplicate' ? app_models.ImportStatus.duplicate : app_models.ImportStatus.valid_new,
        )).toList();
      } 
      throw Exception('Failed to upload');
    } catch (e) {
      print('Upload Error: $e');
      return [];
    }
  }

  Future<void> confirmImport(List<app_models.StudentImportEntry> students) async {
    final body = jsonEncode({'students': students.map((s) => {'name': s.name, 'email': s.email, 'status': s.status == app_models.ImportStatus.valid_new ? 'valid_new' : 'duplicate'}).toList()});
    await http.post(Uri.parse('$_nodeBaseUrl/students/confirm-students'), headers: {'Content-Type': 'application/json'}, body: body);
  }

  Future<void> createSemester(String name) async {
    try {
      await _supabase.from('semesters').insert({'name': name});
    } catch (e) {
      print('Error creating semester: $e');
    }
  }

  // --- GROUP MANAGEMENT ---
  Future<void> createGroup(String courseId, String groupName) async {
    try {
      await _supabase.from('groups').insert({
        'course_id': courseId,
        'name': groupName,
      });
    } catch (e) {
      print('Error creating group: $e');
      throw Exception('Failed to create group');
    }
  }

  Future<List<app_models.Group>> getGroups(String courseId) async {
    try {
      final data = await _supabase
          .from('groups')
          .select()
          .eq('course_id', courseId)
          .order('name', ascending: true);
          
      return (data as List).map((e) => app_models.Group(
        id: e['id'], 
        courseId: e['course_id'], 
        name: e['name']
      )).toList();
    } catch (e) {
      print('Error fetching groups: $e');
      return [];
    }
  }

  Future<List<int>> getWeeklyEngagement(String instructorId) async {
    try {
      final courses = await _supabase.from('courses').select('id').eq('instructor_id', instructorId);
      final courseIds = (courses as List).map((c) => c['id']).toList();
      
      if (courseIds.isEmpty) return List.filled(7, 0);

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      
      final data = await _supabase
          .from('submissions') 
          .select('submitted_at')
          .filter('course_id', 'in', courseIds) 
          .gte('submitted_at', sevenDaysAgo.toIso8601String());

      List<int> dailyCounts = List.filled(7, 0); 
      
      for (var sub in data) {
        final date = DateTime.parse(sub['submitted_at']);
        int dayIndex = date.weekday - 1; 
        if (dayIndex >= 0 && dayIndex < 7) {
          dailyCounts[dayIndex]++;
        }
      }
      return dailyCounts;
    } catch (e) {
      print('Error fetching stats: $e');
      return List.filled(7, 0); 
    }
  }

  Future<void> addStudentToGroup(String groupId, String studentId) async {
    try {
      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'student_id': studentId,
      });
    } catch (e) {
      print('Error adding student to group: $e');
    }
  }
}
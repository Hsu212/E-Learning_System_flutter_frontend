import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart'; 
import 'dart:async';
import 'dart:math';
import 'dart:io';
import './api_service.dart'; 
import './offline_service.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart'; 
import './material_detail_screen.dart';

// --- CONFIGURATION ---
const supabaseUrl = 'https://imrxgzzrvhezsdrdnreb.supabase.co'; 
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImltcnhnenpydmhlenNkcmRucmViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MTAyNjYsImV4cCI6MjA4MDA4NjI2Nn0.NMjp5wxhGDhaWaqGxeKSsZbG-2gNi_65new_N4u-cZU'; 

// --- THEME & COLORS ---
class AppColors {
  static const primary = Color(0xFF1967D2); // Google Blue
  static const secondary = Color(0xFF188038); // Google Green
  static const bg = Color(0xFFF8F9FA); // Off-white background
  static const surface = Colors.white;
  static const textDark = Color(0xFF3C4043);
  static const textLight = Color(0xFF5F6368);
  static const divider = Color(0xFFDADCE0);
  
  static const List<Color> courseThemes = [
    Color(0xFF1967D2), Color(0xFFE37400), Color(0xFF188038), 
    Color(0xFFD93025), Color(0xFFA142F4), Color(0xFF0097A7),
  ];
}

// --- MODELS ---
enum UserRole { instructor, student }
enum ClassworkType { assignment, quiz, material }
enum QuestionType { multipleChoice, trueFalse }
enum ImportStatus { valid_new, valid_enroll, duplicate }
enum SortOption { recent, nameAZ, code }

class User {
  String id;
  String name;
  UserRole role;
  String avatarUrl;
  String email;
  String studentId;

  User({
    required this.id, required this.name, required this.role,
    required this.avatarUrl, required this.email, this.studentId = '',
  });
}

class Group {
  final String id;
  final String courseId;
  final String name;
  Group({required this.id, required this.courseId, required this.name});
}

class Course {
  final String id;
  final String code;
  final String name;
  final String section;
  final String instructorId; 
  final String instructorName;
  final String semesterId;
  final int sessions; 
  final Color themeColor;
  DateTime? lastAccessed;
  List<String> enrolledStudentIds = [];
  double progress;

  Course({
    required this.id, required this.code, required this.name,
    this.section = 'Section 01', this.instructorId = '',
    required this.instructorName, required this.semesterId,
    this.sessions = 15, this.progress = 0.0,
    this.themeColor = AppColors.primary,
    this.lastAccessed,
  });
}

class Question {
  final String id;
  final String text;
  final QuestionType type;
  final List<String> options;
  final int correctOptionIndex;

  Question({
    required this.id, required this.text, required this.type,
    required this.options, required this.correctOptionIndex,
  });
}

class Classwork {
  final String id;
  final String courseId;
  final String title;
  final String description;
  final ClassworkType type;
  final DateTime? dueDate;
  final DateTime postedDate;
  final List<String> assignedGroupIds; 
  
  final bool allowLateSubmission;
  final int maxAttempts;
  final List<String> allowedFileFormats;
  
  final List<Question> questions;
  final List<String> attachmentUrls;
  bool isCompleted;
  int? score; 

  Classwork({
    required this.id, required this.courseId, required this.title,
    this.description = '', required this.type, this.dueDate, required this.postedDate,
    this.assignedGroupIds = const [], 
    this.allowLateSubmission = true, this.maxAttempts = 1, this.allowedFileFormats = const [],
    this.questions = const [], this.attachmentUrls = const [],
    this.isCompleted = false, this.score,
  });
}

class Announcement {
  final String id;
  final String courseId;
  final String authorName;
  final String avatarUrl;
  final String content;
  final DateTime date;
  final List<Comment> comments; 
  final List<String> visibleToGroupIds; 
  
  Announcement({
    required this.id, required this.courseId, required this.authorName,
    required this.avatarUrl, required this.content, required this.date,
    this.comments = const [], this.visibleToGroupIds = const [],
  });
}

class Comment {
  final String authorName;
  final String avatarUrl;
  final String text;
  final DateTime date;
  Comment({required this.authorName, required this.avatarUrl, required this.text, required this.date});
}

class Semester {
  final String id;
  final String name;
  Semester({required this.id, required this.name});
}

class StudentImportEntry {
  final String id;
  final String name;
  final String email;
  final ImportStatus status;
  StudentImportEntry({required this.id, required this.name, required this.email, required this.status});
}

// --- PROVIDERS ---
class AppState extends ChangeNotifier {
  final ApiService? apiService; 
  
  User? currentUser;
  String currentSemesterId = ''; 
  bool isDarkMode = false;
  bool _isLoading = false; 
  bool get isLoading => _isLoading;
  
  List<Course> _courses = [];
  List<Classwork> _classworks = [];
  List<Announcement> _announcements = [];
  List<Semester> _semesters = [];
  List<Group> _groups = []; 

  List<int> _weeklyStats = List.filled(7, 0);
  List<int> get weeklyStats => _weeklyStats;

  AppState({this.apiService});

  List<Semester> get semesters => _semesters;
  List<Course> get courses => _courses;

  // --- AUTHENTICATION ---
  Future<bool> login(String id, String password) async {
    // FIXED: REMOVED THE FAKE LOCAL LOGIN.
    // We now force all logins (even admin) to go through ApiService.
    // ApiService handles the mapping of "admin" -> "admin@tdtu.edu.vn".
    
    if (apiService != null) {
      final user = await apiService!.signIn(id, password);
      if (user != null) {
        currentUser = user;
        await _loadRealData(); 
        if (user.role == UserRole.instructor) {
          await _loadInstructorStats();
        }
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  Future<void> _loadRealData() async {
     _isLoading = true;
     notifyListeners();
     
     if (apiService != null) {
      try {
        // 1. Fetch Semesters
        final realSemesters = await apiService!.getSemesters();
        if (realSemesters.isNotEmpty) {
          await OfflineService.saveSemesters(realSemesters);
          _semesters = realSemesters;
          
          // Default to first semester if none selected
          if (currentSemesterId.isEmpty) {
            currentSemesterId = realSemesters.first.id;
          }
          
          // 2. Fetch Courses for that Semester
          final realCourses = await apiService!.getCourses(currentSemesterId);
          await OfflineService.saveCourses(currentSemesterId, realCourses);
          _courses = realCourses;
        }
      } catch (e) {
        print('Online load failed: $e');
        // Fallback to Offline
        _semesters = await OfflineService.getSemesters();
        if (_semesters.isNotEmpty && currentSemesterId.isEmpty) currentSemesterId = _semesters.first.id;
        _courses = await OfflineService.getCourses(currentSemesterId);
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadInstructorStats() async {
    if (apiService != null && currentUser != null) {
      _weeklyStats = await apiService!.getWeeklyEngagement(currentUser!.id);
      notifyListeners();
    }
  }

  // --- SWITCH SEMESTER ---
  void setSemester(String id) {
    currentSemesterId = id;
    if (apiService != null) {
      _isLoading = true;
      notifyListeners();
      apiService!.getCourses(id).then((courses) {
        _courses = courses;
        _isLoading = false;
        notifyListeners();
      });
    }
  }

  Future<void> loadGroupsForCourse(String courseId) async {
    if (apiService != null) {
      _groups = await apiService!.getGroups(courseId);
      notifyListeners();
    }
  }
  
  List<Group> get courseGroups => _groups;

  void logout() { 
    currentUser = null; 
    _courses = []; 
    notifyListeners(); 
  }

  Future<void> loadClassworksForCourse(String courseId) async {
    if (apiService != null && currentUser != null) {
       _classworks = await apiService!.getClassworks(courseId, currentUser!.id, currentUser!.role.name, null);
       notifyListeners();
    }
  }

  void toggleTheme(bool val) { isDarkMode = val; notifyListeners(); }

  // Filter courses based on user role and current semester
  List<Course> get myCourses {
    var semesterCourses = _courses.where((c) => c.semesterId == currentSemesterId).toList();
    
    // For instructor, show only courses they teach
    if (currentUser?.role == UserRole.instructor) {
      return semesterCourses.where((c) => c.instructorId == currentUser!.id).toList();
    }
    
    // For students, show courses they are enrolled in
    // Note: The ApiService populates enrolledStudentIds with IDs. 
    return semesterCourses.where((c) => c.enrolledStudentIds.contains(currentUser!.id)).toList();
  }

  List<Classwork> getUpcomingTasks() {
    final now = DateTime.now();
    return _classworks.where((w) => w.dueDate != null && w.dueDate!.isAfter(now) && !w.isCompleted).toList();
  }
  
  List<Announcement> getAnnouncements(String courseId) => _announcements.where((a) => a.courseId == courseId).toList();
  List<Classwork> getClasswork(String courseId) => _classworks.where((c) => c.courseId == courseId).toList();

  void addAnnouncement(Announcement a) {
    _announcements.insert(0, a);
    notifyListeners();
  }

  Future<void> addClasswork(Classwork w) async {
    _classworks.add(w); 
    notifyListeners();
  }

  // Quiz Submission Logic
  void submitQuiz(String classworkId, int score) {
    final index = _classworks.indexWhere((w) => w.id == classworkId);
    if (index != -1) {
      _classworks[index].isCompleted = true;
      _classworks[index].score = score;
      notifyListeners();
    }
  }
  
  Future<void> addCourse(Course c) async {
    if (apiService != null) {
      final newCourse = await apiService!.createCourse(c);
      if (newCourse != null) {
        _courses.add(newCourse);
      }
    }
    notifyListeners();
  }
  
  void updateCourseAccess(String id) {}
}

// --- MAIN APP ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await OfflineService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => ApiService()),
        ChangeNotifierProxyProvider<ApiService, AppState>(
          create: (_) => AppState(apiService: null),
          update: (_, api, prev) => AppState(apiService: api)..currentUser = prev?.currentUser,
        ),
      ],
      child: const ModernLearningApp(),
    ),
  );
}

class ModernLearningApp extends StatelessWidget {
  const ModernLearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Classroom',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: state.isDarkMode ? const Color(0xFF202124) : AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary, 
          brightness: state.isDarkMode ? Brightness.dark : Brightness.light,
          surface: state.isDarkMode ? const Color(0xFF303134) : AppColors.surface,
        ),
        textTheme: GoogleFonts.robotoTextTheme(
          state.isDarkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme
        ).copyWith(
          titleLarge: GoogleFonts.openSans(fontWeight: FontWeight.w500),
          titleMedium: GoogleFonts.openSans(fontWeight: FontWeight.w500),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: AppColors.divider.withOpacity(0.5))),
          color: state.isDarkMode ? const Color(0xFF303134) : Colors.white,
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: state.isDarkMode ? const Color(0xFF202124) : AppColors.surface,
          titleTextStyle: TextStyle(color: state.isDarkMode ? Colors.white : AppColors.textDark, fontSize: 20, fontWeight: FontWeight.w500),
          iconTheme: IconThemeData(color: state.isDarkMode ? Colors.white : AppColors.textLight),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: state.isDarkMode ? const Color(0xFF202124) : AppColors.surface,
          elevation: 0,
          indicatorColor: AppColors.primary.withOpacity(0.1),
        )
      ),
      home: state.currentUser == null ? const LoginScreen() : const MainContainer(),
    );
  }
}

// --- LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController(); 
  final _passCtrl = TextEditingController();
  bool _loading = false;

  void _doLogin() async {
    setState(() => _loading = true);
    bool success = await context.read<AppState>().login(_idCtrl.text, _passCtrl.text);
    setState(() => _loading = false);
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login Failed. Check credentials or connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network('https://upload.wikimedia.org/wikipedia/commons/5/59/Google_Classroom_Logo.png', height: 80, errorBuilder: (_,__,___)=>const Icon(Icons.class_, size: 80, color: AppColors.primary)),
              const SizedBox(height: 20),
              Text('Google Classroom', style: GoogleFonts.openSans(fontSize: 28, color: AppColors.textDark)),
              const SizedBox(height: 8),
              const Text('Manage your classes and assignments', style: TextStyle(color: AppColors.textLight)),
              const SizedBox(height: 48),
              TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'Email or User ID', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
              const SizedBox(height: 32),
              SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _loading ? null : _doLogin, child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Sign In'))),
            ],
          ),
        ),
      ),
    );
  }
}

// --- MAIN CONTAINER ---
class MainContainer extends StatefulWidget {
  const MainContainer({super.key});
  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _idx = 0;
  
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser!;
    final isStudent = user.role == UserRole.student;

    final List<Widget> screens = [
      const DashboardScreen(), 
      if (isStudent) const StudentProgressScreen() else const ModernCalendarScreen(), 
      const AdvancedSettingsScreen(),
    ];

    return Scaffold(
      body: screens[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.class_outlined), selectedIcon: Icon(Icons.class_), label: 'Classes'),
          NavigationDestination(
            icon: Icon(isStudent ? Icons.task_alt : Icons.calendar_today_outlined), 
            selectedIcon: Icon(isStudent ? Icons.task : Icons.calendar_today), 
            label: isStudent ? 'To-Do' : 'Calendar'
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// --- DASHBOARD ---
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.currentUser == null) return const SizedBox();
    
    final user = state.currentUser!;
    final isInstructor = user.role == UserRole.instructor;
    List<Course> safeCourses = [];
    try { safeCourses = state.myCourses; } catch (e) { /**/ }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: (){}),
        // [Requirement: Semester Switcher]
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: state.currentSemesterId.isNotEmpty ? state.currentSemesterId : null,
            icon: const Icon(Icons.arrow_drop_down, color: AppColors.textDark),
            style: GoogleFonts.openSans(color: AppColors.textDark, fontSize: 22, fontWeight: FontWeight.w500),
            hint: const Text("Select Semester"),
            onChanged: (val) => state.setSemester(val!),
            items: state.semesters.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: AppColors.textLight), onPressed: () => _showAddMenu(context, state)),
          Padding(padding: const EdgeInsets.only(right: 16, left: 8), child: CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl), radius: 16)),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1.0), child: Container(color: AppColors.divider, height: 1.0)),
      ),
      body: state.isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : CustomScrollView(
          slivers: [
            if (isInstructor) SliverToBoxAdapter(child: _buildInstructorSummary(context, safeCourses)),

            if (safeCourses.isEmpty)
              const SliverFillRemaining(child: Center(child: Text("No classes found.\nSelect a valid semester or create a course.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight))))
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400, childAspectRatio: 1.1, mainAxisSpacing: 16, crossAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ModernCourseCard(course: safeCourses[index], isInstructor: isInstructor),
                    childCount: safeCourses.length,
                  ),
                ),
              ),
          ],
        ),
    );
  }

  Widget _buildInstructorSummary(BuildContext context, List<Course> courses) {
    int totalStudents = courses.fold(0, (sum, c) => sum + c.enrolledStudentIds.length);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Semester Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric('Courses', courses.length.toString()),
                _metric('Students', totalStudents.toString()),
                _metric('Active', '85%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
      Text(label, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
    ]);
  }

  void _showAddMenu(BuildContext context, AppState state) {
    showModalBottomSheet(context: context, builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      if (state.currentUser!.role == UserRole.instructor)
        ListTile(leading: const Icon(Icons.add_box_outlined), title: const Text('Create class'), onTap: (){ Navigator.pop(ctx); _showCreateCourse(context); }),
      ListTile(leading: const Icon(Icons.login), title: const Text('Join class'), onTap: (){ Navigator.pop(ctx); }),
    ]));
  }

   void _showCreateCourse(BuildContext context) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    int sessions = 15;
    
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('Create Class'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Class name (required)')),
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Section')),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: sessions,
              decoration: const InputDecoration(labelText: 'Sessions'),
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 Sessions')),
                DropdownMenuItem(value: 15, child: Text('15 Sessions')),
              ],
              onChanged: (v) => setState(() => sessions = v!),
            )
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () async {
              Navigator.pop(ctx);
              final user = context.read<AppState>().currentUser!;
              await context.read<AppState>().addCourse(Course(
                id: '', code: '101', name: nameCtrl.text,
                instructorId: user.id, instructorName: user.name,
                semesterId: context.read<AppState>().currentSemesterId,
                section: codeCtrl.text, sessions: sessions,
                themeColor: AppColors.courseThemes[Random().nextInt(AppColors.courseThemes.length)]
              ));
            }, child: const Text('Create'))
          ],
        );
      }
    ));
  }
}

class StudentProgressScreen extends StatelessWidget {
  const StudentProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<AppState>().getUpcomingTasks();
    return Scaffold(
      appBar: AppBar(title: const Text('To-Do')),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              labelColor: AppColors.primary,
              indicatorColor: AppColors.primary,
              tabs: [Tab(text: 'Assigned'), Tab(text: 'Missing'), Tab(text: 'Done')]
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTaskList(tasks), // Assigned
                  const Center(child: Text("No missing work!")), // Missing (Placeholder)
                  const Center(child: Text("No completed work yet")), // Done (Placeholder)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<Classwork> tasks) {
    if (tasks.isEmpty) return const Center(child: Text("No work due", style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.transparent, child: Icon(Icons.assignment, color: AppColors.primary)),
          title: Text(task.title),
          subtitle: Text(task.dueDate != null ? 'Due ${DateFormat('MMM d').format(task.dueDate!)}' : 'No due date'),
          trailing: Text('${task.score ?? 100} pts', style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }
}

class ModernCourseCard extends StatelessWidget {
  final Course course;
  final bool isInstructor;
  const ModernCourseCard({super.key, required this.course, required this.isInstructor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<AppState>().updateCourseAccess(course.id);
        Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)));
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: course.themeColor,
                  image: const DecorationImage(image: NetworkImage("https://gstatic.com/classroom/themes/img_code.jpg"), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black38, BlendMode.darken)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Expanded(child: Text(course.name, style: GoogleFonts.openSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      const Icon(Icons.more_vert, color: Colors.white),
                    ]),
                    Text(course.section, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(isInstructor ? '${course.enrolledStudentIds.length} Students' : course.instructorName, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseDetailScreen extends StatefulWidget {
  final Course course;
  const CourseDetailScreen({super.key, required this.course});
  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadClassworksForCourse(widget.course.id);
      context.read<AppState>().loadGroupsForCourse(widget.course.id); 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            title: Text(widget.course.name, style: GoogleFonts.openSans(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: AppColors.textLight),
            actions: [
               IconButton(icon: const Icon(Icons.chat_bubble_outline), tooltip: "Course Forum", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForumScreen(courseId: widget.course.id)))),
               IconButton(icon: const Icon(Icons.info_outline), onPressed: (){}),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: TabBar(
                controller: _tabController,
                labelColor: widget.course.themeColor,
                unselectedLabelColor: AppColors.textLight,
                indicatorColor: widget.course.themeColor,
                indicatorWeight: 3,
                tabs: const [Tab(text: 'Stream'), Tab(text: 'Classwork'), Tab(text: 'People')],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _StreamTab(course: widget.course),
            _ClassworkTab(course: widget.course),
            _PeopleTab(course: widget.course),
          ],
        ),
      ),
    );
  }
}

// --- FORUM (FIXED: Uses Real API) ---
class ForumScreen extends StatefulWidget {
  final String courseId;
  const ForumScreen({super.key, required this.courseId});
  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Discussion Forum")),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add), 
        onPressed: () => _showAddTopic(context),
      ),
      body: FutureBuilder(
        future: context.read<AppState>().apiService!.getForumTopics(widget.courseId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final topics = snapshot.data as List<Map<String, dynamic>>;
          
          if (topics.isEmpty) return const Center(child: Text("No discussions yet."));

          return ListView.separated(
            itemCount: topics.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final t = topics[index];
              return ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(t['users']['avatar_url'] ?? 'https://i.pravatar.cc/150')),
                title: Text(t['title']),
                subtitle: Text("By ${t['users']['name']}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                   // Navigate to replies
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showAddTopic(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("New Topic"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Title")),
        TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: "Content"), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        FilledButton(onPressed: () async {
          final user = context.read<AppState>().currentUser!;
          await context.read<AppState>().apiService!.createForumTopic(widget.courseId, user.id, titleCtrl.text, contentCtrl.text);
          Navigator.pop(ctx);
          setState(() {}); // Refresh
        }, child: const Text("Post"))
      ],
    ));
  }
}

class _StreamTab extends StatelessWidget {
  final Course course;
  const _StreamTab({required this.course});

  @override
  Widget build(BuildContext context) {
    final announcements = context.watch<AppState>().getAnnouncements(course.id);
    final user = context.watch<AppState>().currentUser!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 100, margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(color: course.themeColor, borderRadius: BorderRadius.circular(8), image: const DecorationImage(image: NetworkImage("https://gstatic.com/classroom/themes/img_code.jpg"), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black12, BlendMode.darken))),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(course.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(course.section, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
        ),

        GestureDetector(
          onTap: () => _showAnnounceDialog(context),
          child: Container(
            margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]),
            child: Row(children: [
              CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl), radius: 20),
              const SizedBox(width: 16),
              const Text('Announce something to your class', style: TextStyle(color: AppColors.textLight, fontSize: 14)),
            ]),
          ),
        ),
        
        ...announcements.map((a) => _AnnouncementCard(announcement: a)),
      ],
    );
  }
  
  void _showAnnounceDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final groups = context.read<AppState>().courseGroups;
    final selectedGroups = <String>{};

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('Announce'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Share with class', border: OutlineInputBorder()), maxLines: 3),
              const SizedBox(height: 16),
              const Text("Post to:", style: TextStyle(fontWeight: FontWeight.bold)),
              if (groups.isEmpty) const Text("All Students (No groups created)", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ...groups.map((g) => CheckboxListTile(
                title: Text(g.name),
                value: selectedGroups.contains(g.id),
                onChanged: (v) => setState(() => v! ? selectedGroups.add(g.id) : selectedGroups.remove(g.id)),
              ))
            ]),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (ctrl.text.isEmpty) return;
              final a = Announcement(
                id: 'a${Random().nextInt(999)}', courseId: course.id, authorName: 'Me',
                avatarUrl: 'https://i.pravatar.cc/150', content: ctrl.text, date: DateTime.now(),
                visibleToGroupIds: selectedGroups.toList(), 
              );
              context.read<AppState>().addAnnouncement(a);
              Navigator.pop(ctx);
            }, child: const Text('Post'))
          ],
        );
      }
    ));
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  const _AnnouncementCard({required this.announcement});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          leading: CircleAvatar(backgroundImage: NetworkImage(announcement.avatarUrl)),
          title: Text(announcement.authorName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          subtitle: Text(DateFormat('MMM d').format(announcement.date)),
          trailing: const Icon(Icons.more_vert, size: 20),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(announcement.content)),
        if (announcement.visibleToGroupIds.isNotEmpty)
           Padding(padding: const EdgeInsets.only(left: 16, bottom: 8), child: Text("Visible to ${announcement.visibleToGroupIds.length} groups", style: const TextStyle(fontSize: 10, color: Colors.blue))),
        const Divider(height: 1),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16), child: Text('Add class comment...', style: TextStyle(color: AppColors.textLight, fontSize: 12))),
      ]),
    );
  }
}

class _ClassworkTab extends StatefulWidget {
  final Course course;
  const _ClassworkTab({required this.course});
  @override
  State<_ClassworkTab> createState() => _ClassworkTabState();
}

class _ClassworkTabState extends State<_ClassworkTab> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final works = context.watch<AppState>().getClasswork(widget.course.id)
      .where((w) => w.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final isInstructor = context.watch<AppState>().currentUser!.role == UserRole.instructor;

    return Scaffold(
      floatingActionButton: isInstructor ? FloatingActionButton(
        backgroundColor: Colors.white, foregroundColor: widget.course.themeColor,
        child: const Icon(Icons.add),
        onPressed: () => _showCreateSheet(context),
      ) : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search topics', border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: works.isEmpty 
              ? const Center(child: Text("No classwork yet", style: TextStyle(color: AppColors.textLight)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: works.length,
                  itemBuilder: (context, index) {
                    final w = works[index];
                    IconData icon = w.type == ClassworkType.assignment ? Icons.assignment_outlined : (w.type == ClassworkType.quiz ? Icons.quiz_outlined : Icons.book_outlined);
                    return InkWell(
                      onTap: () {
                         if (w.type == ClassworkType.assignment) Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(work: w)));
                         else if (w.type == ClassworkType.material) Navigator.push(context, MaterialPageRoute(builder: (_) => MaterialDetailScreen(material: w)));
                         else if (w.type == ClassworkType.quiz) Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(quiz: w)));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5))),
                        child: Row(children: [
                          CircleAvatar(backgroundColor: widget.course.themeColor.withOpacity(0.1), child: Icon(icon, color: widget.course.themeColor, size: 24)),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(w.title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: AppColors.textDark)),
                            if (w.dueDate != null) Text('Due ${DateFormat('MMM d').format(w.dueDate!)}', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(context: context, builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.assignment_outlined), title: const Text('Assignment'), onTap: () { Navigator.pop(ctx); _create(context, ClassworkType.assignment); }),
      ListTile(leading: const Icon(Icons.quiz_outlined), title: const Text('Quiz'), onTap: () { Navigator.pop(ctx); _create(context, ClassworkType.quiz); }),
      ListTile(leading: const Icon(Icons.book_outlined), title: const Text('Material'), onTap: () { Navigator.pop(ctx); _create(context, ClassworkType.material); }),
    ]));
  }

  void _create(BuildContext context, ClassworkType type) {
    final titleCtrl = TextEditingController();
    bool allowLate = true;
    final groups = context.read<AppState>().courseGroups;
    final selectedGroups = <String>{};

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text('New ${type.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              if (type == ClassworkType.assignment || type == ClassworkType.quiz) ...[
                SwitchListTile(title: const Text("Allow Late Turn-in"), value: allowLate, onChanged: (v) => setState(() => allowLate = v)),
                const Divider(),
                const Text("Assign to:", style: TextStyle(fontWeight: FontWeight.bold)),
                if (groups.isEmpty) const Text("All Students", style: TextStyle(color: Colors.grey)),
                ...groups.map((g) => CheckboxListTile(
                  title: Text(g.name),
                  value: selectedGroups.contains(g.id),
                  onChanged: (v) => setState(() => v! ? selectedGroups.add(g.id) : selectedGroups.remove(g.id)),
                )),
              ]
            ]),
          ),
          actions: [
            FilledButton(onPressed: () {
              final w = Classwork(
                id: '', courseId: widget.course.id, title: titleCtrl.text, type: type, postedDate: DateTime.now(),
                assignedGroupIds: selectedGroups.toList(), 
                allowLateSubmission: allowLate,
              );
              context.read<AppState>().addClasswork(w);
              Navigator.pop(ctx);
            }, child: const Text('Post'))
          ],
        );
      }
    ));
  }
}

// --- NEW: QUIZ SCREEN ---
class QuizScreen extends StatefulWidget {
  final Classwork quiz;
  const QuizScreen({super.key, required this.quiz});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Map<int, int> _answers = {}; // QuestionIndex -> OptionIndex

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quiz.title)),
      body: widget.quiz.isCompleted 
        ? Center(child: Text("Quiz Completed!\nScore: ${widget.quiz.score} / ${widget.quiz.questions.length}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.quiz.questions.length + 1,
            itemBuilder: (context, index) {
              if (index == widget.quiz.questions.length) {
                 return Padding(
                   padding: const EdgeInsets.symmetric(vertical: 20),
                   child: FilledButton(onPressed: _submit, child: const Text("Submit Quiz")),
                 );
              }
              final q = widget.quiz.questions[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                     Text("Q${index+1}. ${q.text}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                     ...List.generate(q.options.length, (optIndex) => RadioListTile(
                       title: Text(q.options[optIndex]),
                       value: optIndex,
                       groupValue: _answers[index],
                       onChanged: (val) => setState(() => _answers[index] = val!),
                     ))
                  ]),
                ),
              );
            },
          ),
    );
  }

  void _submit() {
    int score = 0;
    for (int i=0; i<widget.quiz.questions.length; i++) {
       if (_answers[i] == widget.quiz.questions[i].correctOptionIndex) {
         score++;
       }
    }
    context.read<AppState>().submitQuiz(widget.quiz.id, score);
  }
}

class _PeopleTab extends StatelessWidget {
  final Course course;
  const _PeopleTab({required this.course});

  @override
  Widget build(BuildContext context) {
    final isInstructor = context.watch<AppState>().currentUser!.role == UserRole.instructor;

    return Scaffold(
      floatingActionButton: isInstructor ? FloatingActionButton.extended(
        onPressed: () => _importStudents(context),
        label: const Text("Import Students"),
        icon: const Icon(Icons.person_add),
      ) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader("Teachers", course.themeColor),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(course.instructorName, style: const TextStyle(fontWeight: FontWeight.w500)),
            trailing: IconButton(icon: const Icon(Icons.message), onPressed: () => _openChat(context, "Instructor")),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Classmates", style: TextStyle(color: course.themeColor, fontSize: 24, fontWeight: FontWeight.w400)),
            Text("${course.enrolledStudentIds.length} students", style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, fontSize: 12)),
          ]),
          Divider(color: course.themeColor, thickness: 1),
          const SizedBox(height: 8),
          
          ...course.enrolledStudentIds.map((id) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text("Student $id"),
            trailing: IconButton(icon: const Icon(Icons.message), onPressed: () => _openChat(context, "Student $id")),
          ))
        ],
      ),
    );
  }

  void _openChat(BuildContext context, String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: name)));
  }

  void _importStudents(BuildContext context) async {
    // 1. Pick CSV
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null) {
      // 2. Preview
      final students = await context.read<AppState>().apiService!.previewCSV(result.files.first);
      
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Import Preview"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: students.length,
            itemBuilder: (ctx, i) {
              final s = students[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(s.email),
                trailing: s.status == ImportStatus.duplicate 
                   ? const Text("Exists", style: TextStyle(color: Colors.red)) 
                   : const Text("New", style: TextStyle(color: Colors.green)),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(onPressed: () async {
             await context.read<AppState>().apiService!.confirmImport(students);
             Navigator.pop(ctx);
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Import Successful")));
          }, child: const Text("Confirm Import"))
        ],
      ));
    }
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w400)),
      const SizedBox(height: 4),
      Divider(color: color, thickness: 1),
    ]);
  }
}

// --- NEW: PRIVATE CHAT ---
class ChatScreen extends StatelessWidget {
  final String peerName;
  const ChatScreen({super.key, required this.peerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(peerName)),
      body: Column(
        children: [
          Expanded(child: Center(child: Text("Chat with $peerName"))),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              const Expanded(child: TextField(decoration: InputDecoration(border: OutlineInputBorder(), hintText: "Type a message..."))),
              IconButton(icon: const Icon(Icons.send), onPressed: (){})
            ]),
          )
        ],
      ),
    );
  }
}

// --- CALENDAR & SETTINGS ---
class ModernCalendarScreen extends StatelessWidget {
  const ModernCalendarScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<AppState>().getUpcomingTasks();
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(children: [
        TableCalendar(
          firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: DateTime.now(),
          calendarFormat: CalendarFormat.week,
          calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
          headerStyle: const HeaderStyle(formatButtonVisible: false),
        ),
        const Divider(),
        Expanded(child: ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, index) => ListTile(
            leading: const Icon(Icons.assignment, color: AppColors.primary),
            title: Text(tasks[index].title),
            subtitle: Text(DateFormat('MMM d').format(tasks[index].dueDate!)),
          ),
        ))
      ]),
    );
  }
}

class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Profile'), subtitle: Text(state.currentUser?.email ?? '')),
        const Divider(),
        SwitchListTile(secondary: const Icon(Icons.dark_mode_outlined), title: const Text('Dark Mode'), value: state.isDarkMode, onChanged: (val) => state.toggleTheme(val)),
        ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Sign out', style: TextStyle(color: Colors.red)), onTap: () { state.logout(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
      ]),
    );
  }
}

class AssignmentDetailScreen extends StatelessWidget {
  final Classwork work;
  const AssignmentDetailScreen({super.key, required this.work});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(work.title), actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: (){})]),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.assignment, color: AppColors.primary),
            const SizedBox(width: 12),
            Text('${work.score ?? 100} points', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textLight)),
            if (work.allowLateSubmission) const Text(" • Late Turn-in Allowed", style: TextStyle(fontSize: 12, color: Colors.green))
          ]),
          const SizedBox(height: 8),
          const Divider(),
          const Text("Instructions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(work.description.isEmpty ? "No instructions." : work.description),
        ]),
      ),
    );
  }
}
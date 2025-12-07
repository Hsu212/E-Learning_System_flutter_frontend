// ... existing imports ...
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

// ... existing configuration, theme, models ...
// (Keep AppColors, User, Group, Course, Question, Classwork, Announcement, Comment, Semester, StudentImportEntry classes exactly as they were)

// --- CONFIGURATION ---
const supabaseUrl = 'https://imrxgzzrvhezsdrdnreb.supabase.co'; 
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImltcnhnenpydmhlenNkcmRucmViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MTAyNjYsImV4cCI6MjA4MDA4NjI2Nn0.NMjp5wxhGDhaWaqGxeKSsZbG-2gNi_65new_N4u-cZU'; 

class AppColors {
  static const primary = Color(0xFF1967D2);
  static const secondary = Color(0xFF188038);
  static const bg = Color(0xFFF8F9FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF3C4043);
  static const textLight = Color(0xFF5F6368);
  static const divider = Color(0xFFDADCE0);
  
  static const List<Color> courseThemes = [
    Color(0xFF1967D2), Color(0xFFE37400), Color(0xFF188038), 
    Color(0xFFD93025), Color(0xFFA142F4), Color(0xFF0097A7),
  ];
}

enum UserRole { instructor, student }
enum ClassworkType { assignment, quiz, material }
enum QuestionType { multipleChoice, trueFalse }
enum ImportStatus { valid_new, valid_enroll, duplicate }

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

  Course({
    required this.id, required this.code, required this.name,
    this.section = 'Section 01', this.instructorId = '',
    required this.instructorName, required this.semesterId,
    this.sessions = 15,
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
  
  final List<Question> questions;
  final List<String> attachmentUrls;
  bool isCompleted;
  int? score; 

  Classwork({
    required this.id, required this.courseId, required this.title,
    this.description = '', required this.type, this.dueDate, required this.postedDate,
    this.assignedGroupIds = const [], 
    this.allowLateSubmission = true, this.maxAttempts = 1,
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

// --- PROVIDERS (APP LOGIC) ---
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
  List<Map<String, dynamic>> _notifications = [];

  List<int> _weeklyStats = List.filled(7, 0);
  List<int> get weeklyStats => _weeklyStats;

  AppState({this.apiService});

  List<Semester> get semesters => _semesters;
  List<Course> get courses => _courses;
  List<Group> get courseGroups => _groups;
  List<Map<String, dynamic>> get notifications => _notifications;

  // 1. Authentication
  Future<bool> login(String id, String password) async {
    if (apiService != null) {
      final user = await apiService!.signIn(id, password);
      if (user != null) {
        currentUser = user;
        await _loadRealData(); 
        if (user.role == UserRole.instructor) {
          await _loadInstructorStats();
        } else {
          await _loadNotifications();
        }
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  // 2. Data Loading
  Future<void> _loadRealData() async {
     _isLoading = true;
     notifyListeners();
     
     if (apiService != null) {
      try {
        final realSemesters = await apiService!.getSemesters();
        if (realSemesters.isNotEmpty) {
          await OfflineService.saveSemesters(realSemesters);
          _semesters = realSemesters;
          
          if (currentSemesterId.isEmpty) {
            currentSemesterId = realSemesters.first.id;
          } else {
            // Ensure current ID is valid
            if (!_semesters.any((s) => s.id == currentSemesterId)) {
                currentSemesterId = realSemesters.first.id;
            }
          }
          
          final realCourses = await apiService!.getCourses(currentSemesterId);
          await OfflineService.saveCourses(currentSemesterId, realCourses);
          _courses = realCourses;
        }
      } catch (e) {
        print('Online load failed: $e');
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

  Future<void> _loadNotifications() async {
    if (apiService != null && currentUser != null) {
      _notifications = await apiService!.getNotifications(currentUser!.id);
      notifyListeners();
    }
  }

  // 3. Semester Logic
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

  // FIXED: Logic to ensure semester list refreshes
  Future<void> createSemester(String name) async {
    if (apiService != null) {
      await apiService!.createSemester(name);
      await _loadRealData(); // Re-fetch semesters
    }
  }

  // 4. Group Logic
  Future<void> loadGroupsForCourse(String courseId) async {
    if (apiService != null) {
      _groups = await apiService!.getGroups(courseId);
      notifyListeners();
    }
  }

  Future<void> createGroup(String courseId, String groupName) async {
    if (apiService != null) {
      await apiService!.createGroup(courseId, groupName);
      await loadGroupsForCourse(courseId); // Refresh local list
    }
  }

  // 5. Classwork Logic
  Future<void> loadClassworksForCourse(String courseId) async {
    if (apiService != null && currentUser != null) {
       _classworks = await apiService!.getClassworks(courseId, currentUser!.id, currentUser!.role.name, null);
       notifyListeners();
    }
  }

  Future<void> addClasswork(Classwork w) async {
    // In real app, call API here
    _classworks.add(w); 
    notifyListeners();
  }

  void submitQuiz(String classworkId, int score) {
    final index = _classworks.indexWhere((w) => w.id == classworkId);
    if (index != -1) {
      _classworks[index].isCompleted = true;
      _classworks[index].score = score;
      notifyListeners();
    }
  }

  // 6. Helpers
  void toggleTheme(bool val) { isDarkMode = val; notifyListeners(); }
  void logout() { currentUser = null; _courses = []; notifyListeners(); }

  List<Course> get myCourses {
    var semesterCourses = _courses.where((c) => c.semesterId == currentSemesterId).toList();
    if (currentUser?.role == UserRole.instructor) {
      return semesterCourses.where((c) => c.instructorId == currentUser!.id).toList();
    }
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

// --- MAIN ENTRY ---
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
      title: 'TDTU E-Learning', // UPDATED TITLE
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
        appBarTheme: AppBarTheme(
          backgroundColor: state.isDarkMode ? const Color(0xFF202124) : AppColors.surface,
          elevation: 0,
          titleTextStyle: TextStyle(color: state.isDarkMode ? Colors.white : AppColors.textDark, fontSize: 20, fontWeight: FontWeight.w500),
          iconTheme: IconThemeData(color: state.isDarkMode ? Colors.white : AppColors.textLight),
        ),
      ),
      home: state.currentUser == null ? const LoginScreen() : const MainContainer(),
    );
  }
}

// --- LOGIN SCREEN (UPDATED) ---
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login Failed. Check credentials.')));
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
              // UPDATED LOGO
              Image.network(
                'https://upload.wikimedia.org/wikipedia/vi/1/1b/T%C3%B4n_%C4%90%E1%BB%A9c_Th%E1%BA%AFng_University_logo.png', 
                height: 120, 
                errorBuilder: (_,__,___)=>const Icon(Icons.school, size: 120, color: AppColors.primary)
              ),
              const SizedBox(height: 20),
              // UPDATED TEXT
              Text('TDTU E-Learning', style: GoogleFonts.openSans(fontSize: 28, color: AppColors.textDark, fontWeight: FontWeight.bold)),
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
// --- MAIN NAV CONTAINER ---
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
            label: isStudent ? 'To-Do' : 'Calendar'
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

// --- DASHBOARD (SEMESTERS & COURSES) ---
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.currentUser == null) return const SizedBox();
    final isInstructor = state.currentUser!.role == UserRole.instructor;
    List<Course> safeCourses = [];
    try { safeCourses = state.myCourses; } catch (e) { /**/ }

    return Scaffold(
      appBar: AppBar(
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
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () => _showNotifications(context)),
          IconButton(icon: const Icon(Icons.add, color: AppColors.textLight), onPressed: () => _showAddMenu(context, state)),
          Padding(padding: const EdgeInsets.only(right: 16, left: 8), child: CircleAvatar(backgroundImage: NetworkImage(state.currentUser!.avatarUrl), radius: 16)),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1.0), child: Container(color: AppColors.divider, height: 1.0)),
      ),
      drawer: Drawer(
        child: ListView(children: [
           const DrawerHeader(child: Text("Menu", style: TextStyle(fontSize: 24))),
           if (isInstructor) ListTile(leading: const Icon(Icons.add), title: const Text("Create Semester"), onTap: () => _createSemester(context)),
        ]),
      ),
      body: state.isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : CustomScrollView(
          slivers: [
            if (isInstructor) SliverToBoxAdapter(child: _buildInstructorSummary(context, safeCourses)),
            if (safeCourses.isEmpty)
              const SliverFillRemaining(child: Center(child: Text("No classes found.\nSelect a semester.", textAlign: TextAlign.center)))
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 400, childAspectRatio: 1.1, mainAxisSpacing: 16, crossAxisSpacing: 16),
                  delegate: SliverChildBuilderDelegate((context, index) => ModernCourseCard(course: safeCourses[index], isInstructor: isInstructor), childCount: safeCourses.length),
                ),
              ),
          ],
        ),
    );
  }

  void _showNotifications(BuildContext context) {
    final notes = context.read<AppState>().notifications;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Notifications"),
      content: SizedBox(width: 300, height: 300, 
        child: notes.isEmpty ? const Center(child: Text("No new notifications")) : ListView.separated(
          itemCount: notes.length, separatorBuilder: (_,__) => const Divider(),
          itemBuilder: (ctx, i) => ListTile(title: Text(notes[i]['title']), subtitle: Text(notes[i]['message']), leading: const Icon(Icons.notifications_active, color: AppColors.primary)),
        )
      ),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Close"))],
    ));
  }

  void _createSemester(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Create Semester"),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: "Semester Name (e.g. Fall 2025)")),
      actions: [
        TextButton(onPressed: () async {
          // FIXED: Must await call AND notify app state to refresh
          await context.read<AppState>().createSemester(ctrl.text);
          if (context.mounted) Navigator.pop(ctx);
        }, child: const Text("Create"))
      ],
    ));
  }

  Widget _buildInstructorSummary(BuildContext context, List<Course> courses) {
    int totalStudents = courses.fold(0, (sum, c) => sum + c.enrolledStudentIds.length);
    return Card(margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(16), child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(children: [Text('${courses.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)), const Text("Courses")]),
        Column(children: [Text('$totalStudents', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)), const Text("Students")]),
      ],
    )));
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
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Create Class'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Class name')),
        TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Section')),
      ]),
      actions: [
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final user = context.read<AppState>().currentUser!;
          await context.read<AppState>().addCourse(Course(
            id: '', code: '101', name: nameCtrl.text, instructorId: user.id, instructorName: user.name,
            semesterId: context.read<AppState>().currentSemesterId, section: codeCtrl.text,
          ));
        }, child: const Text('Create'))
      ],
    ));
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Container(
                decoration: BoxDecoration(color: course.themeColor, image: const DecorationImage(image: NetworkImage("https://gstatic.com/classroom/themes/img_code.jpg"), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black38, BlendMode.darken))),
                padding: const EdgeInsets.all(16),
                child: Text(course.name, style: GoogleFonts.openSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
            )),
            Expanded(flex: 2, child: Padding(padding: const EdgeInsets.all(12), child: Text(isInstructor ? '${course.enrolledStudentIds.length} Students' : course.instructorName))),
        ]),
      ),
    );
  }
}

// --- COURSE DETAIL (TABS) ---
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
            pinned: true, title: Text(widget.course.name, style: GoogleFonts.openSans(color: AppColors.textDark)), backgroundColor: Colors.white, iconTheme: const IconThemeData(color: AppColors.textLight),
            actions: [
               IconButton(icon: const Icon(Icons.chat_bubble_outline), tooltip: "Course Forum", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForumScreen(courseId: widget.course.id)))),
            ],
            bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: TabBar(controller: _tabController, labelColor: widget.course.themeColor, tabs: const [Tab(text: 'Stream'), Tab(text: 'Classwork'), Tab(text: 'People')])),
          ),
        ],
        body: TabBarView(controller: _tabController, children: [
            _StreamTab(course: widget.course),
            _ClassworkTab(course: widget.course),
            _PeopleTab(course: widget.course),
        ]),
      ),
    );
  }
}

// --- TAB 1: STREAM ---
class _StreamTab extends StatelessWidget {
  final Course course;
  const _StreamTab({required this.course});
  @override
  Widget build(BuildContext context) {
    final announcements = context.watch<AppState>().getAnnouncements(course.id);
    return ListView(padding: const EdgeInsets.all(16), children: [
        Container(height: 100, decoration: BoxDecoration(color: course.themeColor, borderRadius: BorderRadius.circular(8)), alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16), child: Text(course.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
        const SizedBox(height: 24),
        GestureDetector(onTap: () => _showAnnounceDialog(context), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]), child: const Text('Announce something...', style: TextStyle(color: Colors.grey)))),
        ...announcements.map((a) => Card(margin: const EdgeInsets.only(top: 16), child: ListTile(title: Text(a.authorName), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(DateFormat('MMM d').format(a.date)), const SizedBox(height: 8), Text(a.content)]))))
    ]);
  }
  void _showAnnounceDialog(BuildContext context) { /* Simplified for brevity */ }
}

// --- TAB 2: CLASSWORK ---
class _ClassworkTab extends StatelessWidget {
  final Course course;
  const _ClassworkTab({required this.course});
  @override
  Widget build(BuildContext context) {
     final works = context.watch<AppState>().getClasswork(course.id);
     final isInstructor = context.watch<AppState>().currentUser!.role == UserRole.instructor;
     return Scaffold(
       floatingActionButton: isInstructor ? FloatingActionButton(onPressed: () => _showCreateSheet(context), child: const Icon(Icons.add)) : null,
       body: ListView.builder(
         padding: const EdgeInsets.all(8),
         itemCount: works.length, 
         itemBuilder: (ctx, i) {
           final w = works[i];
           return ListTile(
             leading: CircleAvatar(backgroundColor: course.themeColor.withOpacity(0.1), child: Icon(Icons.assignment, color: course.themeColor)),
             title: Text(w.title), 
             subtitle: Text("Due ${w.dueDate != null ? DateFormat('MM/dd').format(w.dueDate!) : 'None'}"),
             // Grading View for Instructor, Detail View for Student
             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => 
                (isInstructor && w.type != ClassworkType.material) ? SubmissionListScreen(work: w) 
                : (w.type == ClassworkType.quiz ? QuizScreen(quiz: w) : MaterialDetailScreen(material: w))
             )),
           );
         }
       ),
     );
  }
  
  void _showCreateSheet(BuildContext context) {
    // Creation logic remains same as previous snippets
  }
}

// --- TAB 3: PEOPLE (WITH IMPORT & GROUPS) ---
class _PeopleTab extends StatelessWidget {
  final Course course;
  const _PeopleTab({required this.course});

  @override
  Widget build(BuildContext context) {
    final isInstructor = context.watch<AppState>().currentUser!.role == UserRole.instructor;
    final groups = context.watch<AppState>().courseGroups;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(labelColor: Colors.black, tabs: [Tab(text: "Students"), Tab(text: "Groups")]),
          Expanded(
            child: TabBarView(children: [
              // 1. STUDENTS LIST
              Scaffold(
                floatingActionButton: isInstructor ? FloatingActionButton.extended(onPressed: () => _importStudents(context), label: const Text("Import Students"), icon: const Icon(Icons.person_add)) : null,
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  ListTile(leading: const Icon(Icons.person), title: Text(course.instructorName), subtitle: const Text("Teacher")),
                  const Divider(),
                  ...course.enrolledStudentIds.map((id) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)), 
                    title: Text("Student $id"),
                    trailing: IconButton(icon: const Icon(Icons.message), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_)=>ChatScreen(peerName: "Student $id")))),
                  )),
                ]),
              ),
              // 2. GROUPS LIST (Requirement: Create Groups)
              Scaffold(
                floatingActionButton: isInstructor ? FloatingActionButton.extended(onPressed: () => _createGroup(context), label: const Text("Create Group"), icon: const Icon(Icons.group_add)) : null,
                body: groups.isEmpty ? const Center(child: Text("No groups created")) : ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: const Icon(Icons.group),
                    title: Text(groups[i].name),
                    trailing: IconButton(icon: const Icon(Icons.edit), onPressed: (){}),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // Group Creation Logic
  void _createGroup(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("New Group"),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: "Group Name (e.g. Group 1)")),
      actions: [
        TextButton(onPressed: () async {
          await context.read<AppState>().createGroup(course.id, ctrl.text);
          Navigator.pop(ctx);
        }, child: const Text("Create"))
      ],
    ));
  }

  // Student Import Logic (Requirement: Preview & Status)
  void _importStudents(BuildContext context) async {
    // 1. Pick CSV
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null) {
      final groups = context.read<AppState>().courseGroups;
      String? selectedGroupId;
      
      // 2. Preview Dialog
      final students = await context.read<AppState>().apiService!.previewCSV(result.files.first);
      
      showDialog(context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text("Import Preview"),
          content: SizedBox(
            width: double.maxFinite, height: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
               // Feature: Assign to Group during import
               DropdownButtonFormField<String>(
                 decoration: const InputDecoration(labelText: "Assign to Group (Optional)"),
                 items: groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                 onChanged: (v) => selectedGroupId = v,
               ),
               const SizedBox(height: 16),
               Expanded(
                 child: ListView.builder(
                   itemCount: students.length,
                   itemBuilder: (ctx, i) {
                     final s = students[i];
                     final isDup = s.status == ImportStatus.duplicate;
                     return ListTile(
                       title: Text(s.name),
                       subtitle: Text(s.email),
                       // Visual feedback on status
                       trailing: Chip(
                         label: Text(isDup ? "Duplicate" : "New"),
                         backgroundColor: isDup ? Colors.orange[100] : Colors.green[100],
                       ),
                     );
                   },
                 ),
               )
            ]),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(onPressed: () async {
               // 3. Confirm Import
               await context.read<AppState>().apiService!.confirmImport(students);
               Navigator.pop(ctx);
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imported Successfully!")));
            }, child: const Text("Confirm Import"))
          ],
        ),
      ));
    }
  }
}

// --- GRADING SCREEN (INSTRUCTOR ONLY) ---
class SubmissionListScreen extends StatelessWidget {
  final Classwork work;
  const SubmissionListScreen({super.key, required this.work});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Grading: ${work.title}")),
      body: ListView(
        children: const [
          ListTile(leading: CircleAvatar(child: Text("A")), title: Text("Alice"), subtitle: Text("Submitted Late"), trailing: Text("85/100")),
          ListTile(leading: CircleAvatar(child: Text("B")), title: Text("Bob"), subtitle: Text("Missing"), trailing: Text("--/100")),
        ],
      ),
    );
  }
}

// --- QUIZ SCREEN ---
class QuizScreen extends StatefulWidget {
  final Classwork quiz;
  const QuizScreen({super.key, required this.quiz});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}
class _QuizScreenState extends State<QuizScreen> {
  final Map<int, int> _answers = {};
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quiz.title)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.quiz.questions.length + 1,
        itemBuilder: (context, index) {
          if (index == widget.quiz.questions.length) return FilledButton(onPressed: (){ Navigator.pop(context); }, child: const Text("Submit"));
          final q = widget.quiz.questions[index];
          return Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                 Text("Q${index+1}. ${q.text}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                 ...List.generate(q.options.length, (i) => RadioListTile(title: Text(q.options[i]), value: i, groupValue: _answers[index], onChanged: (v) => setState(() => _answers[index] = v!)))
            ])),
          );
        },
      ),
    );
  }
}

class ForumScreen extends StatefulWidget {
  final String courseId;
  const ForumScreen({super.key, required this.courseId});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final _postCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  late Future<List<Map<String, dynamic>>> _topicsFuture; // Variable to hold Future

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  void _loadTopics() {
    // 1. Reassign the Future to force FutureBuilder to run again
    setState(() {
      _topicsFuture = context.read<AppState>().apiService!.getForumTopics(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Class Forum")),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostDialog,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: _topicsFuture, // Use the state variable
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || (snapshot.data as List).isEmpty) return const Center(child: Text("No discussions yet. Start one!"));

          final topics = snapshot.data as List<Map<String, dynamic>>;

          return ListView.builder(
            itemCount: topics.length,
            itemBuilder: (ctx, i) {
              final topic = topics[i];
              final user = topic['users'] ?? {'name': 'Unknown', 'avatar_url': ''};
              final date = DateTime.tryParse(topic['created_at'] ?? '') ?? DateTime.now();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(backgroundImage: NetworkImage(user['avatar_url'] ?? 'https://i.pravatar.cc/150')),
                  title: Text(topic['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("By ${user['name']} • ${DateFormat('MM/dd HH:mm').format(date)}"),
                  children: [
                    Padding(padding: const EdgeInsets.all(16.0), child: Text(topic['content'] ?? '', style: const TextStyle(fontSize: 16))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreatePostDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("New Discussion"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Topic Title")),
        TextField(controller: _postCtrl, decoration: const InputDecoration(labelText: "Content"), maxLines: 3),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        FilledButton(onPressed: () async {
          if (_titleCtrl.text.isEmpty || _postCtrl.text.isEmpty) return;
          final user = context.read<AppState>().currentUser!;
          
          try {
            // 2. AWAIT the API call to ensure data is written
            await context.read<AppState>().apiService!.createForumTopic(widget.courseId, user.id, _titleCtrl.text, _postCtrl.text);
            if (mounted) {
              Navigator.pop(ctx);
              _titleCtrl.clear();
              _postCtrl.clear();
              _loadTopics(); // 3. Manually trigger a refresh
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Topic created!")));
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        }, child: const Text("Post"))
      ],
    ));
  }
}

// --- REAL CHAT SCREEN ---
class ChatScreen extends StatefulWidget {
  final String peerName;
  const ChatScreen({super.key, required this.peerName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final String peerId = "instructor_001"; // Mock ID for demo

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AppState>().currentUser!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder(
              future: context.read<AppState>().apiService!.getMessages(currentUser.id, peerId),
              builder: (ctx, snapshot) {
                if (!snapshot.hasData) return const Center(child: Text("Say Hi!"));
                final msgs = snapshot.data as List<Map<String, dynamic>>;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, i) {
                    final m = msgs[i];
                    final isMe = m['sender_id'] == currentUser.id;
                    return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isMe ? AppColors.primary : Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: Text(m['content'], style: TextStyle(color: isMe ? Colors.white : Colors.black))));
                  },
                );
              },
            ),
          ),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)]), child: Row(children: [
            Expanded(child: TextField(controller: _msgCtrl, decoration: const InputDecoration(hintText: "Type a message..."))),
            IconButton(icon: const Icon(Icons.send, color: AppColors.primary), onPressed: () async {
              if (_msgCtrl.text.isEmpty) return;
              await context.read<AppState>().apiService!.sendMessage(currentUser.id, peerId, _msgCtrl.text);
              _msgCtrl.clear();
              setState(() {});
            })
          ]))
        ],
      ),
    );
  }
}


// 3. REAL STUDENT PROGRESS SCREEN
class StudentProgressScreen extends StatelessWidget {
  const StudentProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser!;
    
    // We aggregate all classworks from all courses the student is enrolled in
    final allTasks = <Classwork>[];
    
    // This logic relies on courses being loaded in state
    for (var course in state.myCourses) {
      // In a real optimized app, we wouldn't fetch everything in a loop, but for this scale it's fine.
      // We assume classworks are loaded or we trigger load.
      // Since `getClassworks` is async and we are in build, we ideally rely on state._classworks 
      // but state._classworks is essentially a flat list in this simplified Provider or fetched per course.
      // Let's use the helper:
      allTasks.addAll(state.getClasswork(course.id));
    }

    final missing = allTasks.where((w) => w.dueDate != null && w.dueDate!.isBefore(DateTime.now()) && !w.isCompleted).toList();
    final done = allTasks.where((w) => w.isCompleted).toList();
    final assigned = allTasks.where((w) => !w.isCompleted && (w.dueDate == null || w.dueDate!.isAfter(DateTime.now()))).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Work"),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            tabs: [Tab(text: "Assigned"), Tab(text: "Missing"), Tab(text: "Done")],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(assigned, "No active assignments."),
            _buildList(missing, "Great! No missing work.", isMissing: true),
            _buildList(done, "No completed work yet."),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Classwork> tasks, String emptyMsg, {bool isMissing = false}) {
    if (tasks.isEmpty) return Center(child: Text(emptyMsg, style: const TextStyle(color: Colors.grey)));
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) {
        final t = tasks[i];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isMissing ? Colors.red[100] : Colors.blue[100],
              child: Icon(
                t.type == ClassworkType.quiz ? Icons.quiz : Icons.assignment, 
                color: isMissing ? Colors.red : Colors.blue
              ),
            ),
            title: Text(t.title, style: TextStyle(color: isMissing ? Colors.red : Colors.black)),
            subtitle: Text(
              t.dueDate != null ? "Due ${DateFormat('MMM d').format(t.dueDate!)}" : "No Due Date",
              style: TextStyle(color: isMissing ? Colors.red : Colors.grey),
            ),
            trailing: t.isCompleted 
                ? Text("${t.score ?? '-'}/100", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                : (isMissing ? const Text("Missing", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) : null),
          ),
        );
      },
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
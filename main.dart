import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const ARForgeApp());

class AppColors {
  static const main = Color(0xFF2D3E2C);
  static const accent = Color(0xFFE4FD97);
  static const dark = Color(0xFF1B261A);
  static const card = Color(0xFF354A34);
}

// =====================================================
// DATA
// =====================================================
int _nextId = 1;

class Clip {
  final int id;
  final String path;
  final bool isImage;
  final double srcDur;
  final bool hasAudio;
  double start;
  double end;
  double speed;
  bool rev;
  int rot; // 0, 90, 180, 270
  bool flipH;
  bool flipV;

  Clip({
    int? id,
    required this.path,
    required this.isImage,
    required this.srcDur,
    required this.hasAudio,
    required this.start,
    required this.end,
    this.speed = 1.0,
    this.rev = false,
    this.rot = 0,
    this.flipH = false,
    this.flipV = false,
  }) : id = id ?? _nextId++;

  Clip copy({bool newId = false}) => Clip(
        id: newId ? null : id,
        path: path,
        isImage: isImage,
        srcDur: srcDur,
        hasAudio: hasAudio,
        start: start,
        end: end,
        speed: speed,
        rev: rev,
        rot: rot,
        flipH: flipH,
        flipV: flipV,
      );

  double get outDur => (end - start) / speed;
}

const Map<String, List<int>> ratios = {
  '9:16': [9, 16],
  '16:9': [16, 9],
  '1:1': [1, 1],
  '4:5': [4, 5],
  '4:3': [4, 3],
};

class EditState {
  List<Clip> clips = [];
  String ratio = '9:16';
  String? text;

  EditState copy() {
    final e = EditState();
    e.clips = clips.map((c) => c.copy()).toList();
    e.ratio = ratio;
    e.text = text;
    return e;
  }

  void restore(EditState o) {
    clips = o.clips.map((c) => c.copy()).toList();
    ratio = o.ratio;
    text = o.text;
  }
}

class Project {
  final String name;
  final DateTime created;
  final EditState state = EditState();
  Project({required this.name, required this.created});
}

final ValueNotifier<List<Project>> projects = ValueNotifier<List<Project>>([]);

// =====================================================
// HELPERS
// =====================================================
void soon(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$name jald aa raha hai')),
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

String fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String fmtSec(double s) {
  final d = Duration(milliseconds: (s * 1000).round());
  return fmt(d);
}

String timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Abhi';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

bool _isImagePath(String p) {
  final l = p.toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.bmp']
      .any((e) => l.endsWith(e));
}

Future<bool> _hasAudio(String path) async {
  try {
    final s = await FFprobeKit.getMediaInformation(path);
    final info = s.getMediaInformation();
    final streams = info?.getStreams() ?? [];
    for (final st in streams) {
      if (st.getType() == 'audio') return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<List<Clip>> importMedia() async {
  final files = await ImagePicker().pickMultipleMedia();
  final out = <Clip>[];
  for (final f in files) {
    if (_isImagePath(f.path)) {
      out.add(Clip(
          path: f.path,
          isImage: true,
          srcDur: 10,
          hasAudio: false,
          start: 0,
          end: 3));
    } else {
      final c = VideoPlayerController.file(File(f.path));
      await c.initialize();
      final d = c.value.duration.inMilliseconds / 1000.0;
      await c.dispose();
      final a = await _hasAudio(f.path);
      out.add(Clip(
          path: f.path,
          isImage: false,
          srcDur: d,
          hasAudio: a,
          start: 0,
          end: d));
    }
  }
  return out;
}

Future<void> startNewProject(BuildContext context) async {
  final clips = await importMedia();
  if (clips.isEmpty) return;
  final p = Project(
      name: 'Project ${projects.value.length + 1}', created: DateTime.now());
  p.state.clips = clips;
  projects.value = [p, ...projects.value];
  if (!context.mounted) return;
  openProject(context, p);
}

void openProject(BuildContext context, Project p) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EditorScreen(project: p)),
  );
}

// =====================================================
// APP
// =====================================================
class ARForgeApp extends StatelessWidget {
  const ARForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.dark,
        textTheme: GoogleFonts.poppinsTextTheme(), // Fixed line
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------- Splash ----------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainShell()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/logo.png', width: 140, height: 140),
            ),
            const SizedBox(height: 12),
            Text('AR FORGE',
                style: GoogleFonts.poppins(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text('Create a forge',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: AppColors.accent)),
            const SizedBox(height: 14),
            const Text('CREATED BY: MUHAMMAD ALI',
                style: TextStyle(
                    color: Colors.white60, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 40),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  minHeight: 4,
                  color: AppColors.accent,
                  backgroundColor: AppColors.card,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Main shell ----------
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    AudioScreen(),
    ProjectsScreen(),
    ProfileScreen(),
  ];

  Widget _navItem(IconData icon, String label, int i) {
    final selected = _index == i;
    return InkWell(
      onTap: () => setState(() => _index = i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: selected ? AppColors.accent : Colors.white54),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? AppColors.accent : Colors.white54)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('CREATED BY: MUHAMMAD ALI',
                style: TextStyle(
                    color: Colors.white38, fontSize: 10, letterSpacing: 1)),
          ),
          Container(
        height: 74,
        decoration: const BoxDecoration(
          color: AppColors.main,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_rounded, 'Home', 0),
            _navItem(Icons.music_note_rounded, 'Audio', 1),
            GestureDetector(
              onTap: () => startNewProject(context),
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppColors.main, size: 30),
              ),
            ),
            _navItem(Icons.folder_rounded, 'Projects', 2),
            _navItem(Icons.person_rounded, 'Profile', 3),
          ],
        ),
      ),
        ],
      ),
    );
  }
}

// ---------- Home ----------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/logo.png', width: 52, height: 52),
                ),
                const SizedBox(height: 6),
                Text('AR FORGE',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                        color: Colors.white)),
                Text('Create a forge',
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppColors.accent)),
              ],
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.workspace_premium, color: AppColors.accent),
            ),
            const SizedBox(width: 14),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: () => startNewProject(context),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: AppColors.main, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: AppColors.accent),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create New Project',
                          style: TextStyle(
                              color: AppColors.main,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      Text('Video ya photo chuno aur edit shuru karo',
                          style:
                              TextStyle(color: AppColors.main, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.main),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _quick(context, Icons.auto_awesome, 'AI Tools',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiToolsScreen()))),
            _quick(context, Icons.grid_view_rounded, 'Templates',
                () => soon(context, 'Templates')),
            _quick(context, Icons.edit_note_rounded, 'AI Prompt',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiPromptScreen()))),
            _quick(context, Icons.music_note_rounded, 'Audio',
                () => soon(context, 'Audio')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Recent Projects',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ValueListenableBuilder<List<Project>>(
          valueListenable: projects,
          builder: (context, list, _) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'Abhi koi project nahi. Upar "Create New Project" dabao.',
                    style: TextStyle(color: Colors.white54)),
              );
            }
            return Column(
              children:
                  list.take(3).map((p) => _projectTile(context, p)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _quick(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

Widget _projectTile(BuildContext context, Project p) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () => openProject(context, p),
    leading: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.movie, color: Colors.white38),
    ),
    title: Text(p.name),
    subtitle: Text('${timeAgo(p.created)} · ${p.state.clips.length} clips',
        style: const TextStyle(color: Colors.white54, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
  );
}

// ---------- Audio tab ----------
class AudioScreen extends StatelessWidget {
  const AudioScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Audio library jald aa rahi hai (Phase 2)',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
      ),
    );
  }
}

// ---------- Projects ----------
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Project>>(
      valueListenable: projects,
      builder: (context, list, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Projects',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('Abhi koi project nahi.',
                    style: TextStyle(color: Colors.white54)),
              ),
            ...list.map((p) => Dismissible(
                  key: ValueKey(p.created.toIso8601String()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.shade700,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete),
                  ),
                  onDismissed: (_) {
                    projects.value =
                        projects.value.where((x) => x != p).toList();
                  },
                  child: _projectTile(context, p),
                )),
            if (list.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Delete karne ke liye project ko left swipe karo',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }
}

// ---------- Profile ----------
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.workspace_premium, 'Subscription', 'Free Plan'),
      (Icons.storage, 'Storage', ''),
      (Icons.language, 'Language', 'English'),
      (Icons.settings, 'Export Settings', ''),
      (Icons.notifications, 'Notifications', ''),
      (Icons.help_outline, 'Help & Support', ''),
      (Icons.privacy_tip_outlined, 'Privacy', ''),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Profile & Settings',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.card,
              child: Icon(Icons.person, color: AppColors.accent)),
          title: Text('Muhammad Ali'),
        ),
        const Divider(),
        ...items.map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.$1, color: AppColors.accent),
              title: Text(e.$2),
              trailing: e.$3.isEmpty
                  ? const Icon(Icons.chevron_right, color: Colors.white54)
                  : Text(e.$3, style: const TextStyle(color: Colors.white54)),
              onTap: () => soon(context, e.$2),
            )),
      ],
    );
  }
}

// ---------- AI Tools ----------
class AiToolsScreen extends StatelessWidget {
  const AiToolsScreen({super.key});
  @override
  W

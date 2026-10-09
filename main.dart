import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
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
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text('Create a forge',
                style: TextStyle(
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
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                        color: Colors.white)),
                Text('Create a forge',
                    style: TextStyle(
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
  Widget build(BuildContext context) {
    final tools = [
      (Icons.auto_fix_high, 'AI Auto Edit', 'Smart edit with one click'),
      (Icons.closed_caption, 'AI Captions', 'Auto subtitles & styling'),
      (Icons.record_voice_over, 'AI Voice', 'Text to speech & voice clone'),
      (Icons.layers_clear, 'Background Remover', 'Remove background easily'),
      (Icons.cleaning_services, 'Object Remover', 'Remove unwanted objects'),
      (Icons.description, 'Script Generator', 'Ideas to script in seconds'),
      (Icons.auto_awesome, 'AI Effects', 'Trendy & cinematic effects'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tools'),
        backgroundColor: AppColors.dark,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: tools
            .map((t) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: Icon(t.$1, color: AppColors.accent),
                    title: Text(t.$2),
                    subtitle: Text(t.$3,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => soon(context, t.$2),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ---------- AI Prompt ----------
class AiPromptScreen extends StatefulWidget {
  const AiPromptScreen({super.key});
  @override
  State<AiPromptScreen> createState() => _AiPromptScreenState();
}

class _AiPromptScreenState extends State<AiPromptScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = ['Cinematic style', 'Shorts edit', 'Add captions'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Prompt'),
        backgroundColor: AppColors.dark,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Describe what you want to create...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                hintText: 'Make this video cinematic with smooth zooms...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            Wrap(
              spacing: 8,
              children: chips
                  .map((t) => ActionChip(
                        label: Text(t),
                        onPressed: () => setState(() => _c.text = t),
                      ))
                  .toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.main),
                onPressed: () => soon(context, 'AI Generate'),
                child: const Text('Generate Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// VIDEO EDITOR (Phase 1)
// =====================================================
class EditorScreen extends StatefulWidget {
  final Project project;
  const EditorScreen({super.key, required this.project});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditState s;
  final List<EditState> _undo = [];
  final List<EditState> _redo = [];
  int sel = 0;
  VideoPlayerController? _c;
  bool _ready = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    s = widget.project.state;
    _loadSel();
  }

  @override
  void dispose() {
    _token++;
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  // ---------- preview control ----------
  Clip? get _clip =>
      (s.clips.isNotEmpty && sel >= 0 && sel < s.clips.length)
          ? s.clips[sel]
          : null;

  Future<void> _loadSel() async {
    final token = ++_token;
    final old = _c;
    old?.removeListener(_tick);
    _c = null;
    _ready = false;
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await old?.dispose();
    if (s.clips.isEmpty) return;
    if (sel >= s.clips.length) sel = s.clips.length - 1;
    if (sel < 0) sel = 0;
    final clip = s.clips[sel];
    if (clip.isImage) {
      if (mounted) setState(() {});
      return;
    }
    final c = VideoPlayerController.file(File(clip.path));
    await c.initialize();
    if (token != _token || !mounted) {
      await c.dispose();
      return;
    }
    await c.setPlaybackSpeed(clip.speed);
    await c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
    c.addListener(_tick);
    _c = c;
    _ready = true;
    setState(() {});
  }

  void _tick() {
    final c = _c;
    final clip = _clip;
    if (c == null || clip == null || !mounted) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (c.value.isPlaying && pos >= clip.end) {
      c.pause();
      c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
    }
    setState(() {});
  }

  double get _playhead {
    final c = _c;
    final clip = _clip;
    if (c == null || clip == null) return 0;
    final pos = c.value.position.inMilliseconds / 1000.0;
    return math.min(clip.end, math.max(clip.start, pos));
  }

  // ---------- state changes ----------
  void _commit(VoidCallback change, {bool reload = false}) {
    _undo.add(s.copy());
    _redo.clear();
    setState(change);
    if (reload) _loadSel();
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    _redo.add(s.copy());
    s.restore(_undo.removeLast());
    setState(() {});
    _loadSel();
  }

  void _doRedo() {
    if (_redo.isEmpty) return;
    _undo.add(s.copy());
    s.restore(_redo.removeLast());
    setState(() {});
    _loadSel();
  }

  Future<void> _import() async {
    final clips = await importMedia();
    if (clips.isEmpty) return;
    _commit(() {
      s.clips.addAll(clips);
      if (s.clips.length == clips.length) sel = 0;
    }, reload: true);
  }

  void _split() {
    final clip = _clip;
    if (clip == null) return;
    final at = clip.isImage ? (clip.start + clip.end) / 2 : _playhead;
    if (at <= clip.start + 0.2 || at >= clip.end - 0.2) {
      toast(context, 'Split ke liye playhead clip ke beech mein rakho');
      return;
    }
    _commit(() {
      final a = clip.copy();
      final b = clip.copy(newId: true);
      a.end = at;
      b.start = at;
      s.clips[sel] = a;
      s.clips.insert(sel + 1, b);
    }, reload: true);
  }

  void _delete() {
    if (_clip == null) return;
    _commit(() {
      s.clips.removeAt(sel);
      if (sel >= s.clips.length) sel = s.clips.length - 1;
      if (sel < 0) sel = 0;
    }, reload: true);
  }

  void _duplicate() {
    final clip = _clip;
    if (clip == null) return;
    _commit(() {
      s.clips.insert(sel + 1, clip.copy(newId: true));
      sel = sel + 1;
    }, reload: true);
  }

  void _reorder(int oldI, int newI) {
    if (newI > oldI) newI--;
    _commit(() {
      final c = s.clips.removeAt(oldI);
      s.clips.insert(newI, c);
      sel = newI;
    }, reload: true);
  }

  void _rotate() {
    final clip = _clip;
    if (clip == null) return;
    _commit(() => clip.rot = (clip.rot + 90) % 360);
  }

  void _flip(bool horizontal) {
    final clip = _clip;
    if (clip == null) return;
    _commit(() {
      if (horizontal) {
        clip.flipH = !clip.flipH;
      } else {
        clip.flipV = !clip.flipV;
      }
    });
  }

  // ---------- sheets ----------
  Widget _choices<T>(List<(String, T)> items, T cur, void Function(T) onSel) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((e) => ChoiceChip(
                label: Text(e.$1),
                selected: e.$2 == cur,
                onSelected: (_) => onSel(e.$2),
              ))
          .toList(),
    );
  }

  void _trim() {
    final clip = _clip;
    if (clip == null) return;
    _undo.add(s.copy());
    _redo.clear();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Trim: ${fmtSec(clip.start)} – ${fmtSec(clip.end)}  (${(clip.end - clip.start).toStringAsFixed(1)}s)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              RangeSlider(
                values: RangeValues(clip.start, clip.end),
                min: 0,
                max: clip.srcDur,
                activeColor: AppColors.accent,
                onChanged: (v) {
                  if (v.end - v.start < 0.3) return;
                  set(() {
                    clip.start = v.start;
                    clip.end = v.end;
                  });
                  setState(() {});
                  _c?.seekTo(
                      Duration(milliseconds: (v.start * 1000).round()));
                },
              ),
              const Text('Slider kheench kar shuru aur end chuno',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        );
      }),
    ).whenComplete(_loadSel);
  }

  void _speed() {
    final clip = _clip;
    if (clip == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Speed',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _choices<double>(
                [
                  ('0.25x', 0.25),
                  ('0.5x', 0.5),
                  ('0.75x', 0.75),
                  ('1x', 1.0),
                  ('1.5x', 1.5),
                  ('2x', 2.0),
                  ('3x', 3.0),
                  ('4x', 4.0),
                ],
                clip.speed,
                (v) {
                  _commit(() => clip.speed = v);
                  _c?.setPlaybackSpeed(v);
                  set(() {});
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reverse (ulta chalao)'),
                subtitle: const Text(
                    'Export mein lagta hai, preview mein nahi. Chhote clips ke liye.',
                    style: TextStyle(fontSize: 12)),
                value: clip.rev,
                onChanged: clip.isImage
                    ? null
                    : (v) {
                        _commit(() => clip.rev = v);
                        set(() {});
                      },
              ),
            ],
          ),
        );
      }),
    );
  }

  void _ratio() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aspect Ratio',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _choices<String>(
                ratios.keys.map((k) => (k, k)).toList(),
                s.ratio,
                (v) {
                  _commit(() => s.ratio = v);
                  set(() {});
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _text() async {
    final tc = TextEditingController(text: s.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Text likho'),
        content: TextField(controller: tc, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Hatao')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, tc.text),
              child: const Text('Lagao')),
        ],
      ),
    );
    if (result != null) {
      _commit(() => s.text = result.trim().isEmpty ? null : result.trim());
    }
  }

  Future<void> _extractFrame() async {
    final clip = _clip;
    if (clip == null) return;
    if (clip.isImage) {
      toast(context, 'Frame sirf video clip se nikalta hai');
      return;
    }
    final out =
        '${Directory.systemTemp.path}/frame_${DateTime.now().millisecondsSinceEpoch}.png';
    final t = _playhead.toStringAsFixed(3);
    toast(context, 'Frame nikal raha hoon...');
    final session = await FFmpegKit.executeWithArguments(
        ['-y', '-ss', t, '-i', clip.path, '-frames:v', '1', out]);
    final rc = await session.getReturnCode();
    if (!mounted) return;
    if (ReturnCode.isSuccess(rc)) {
      try {
        await Gal.putImage(out, album: 'AR Forge');
        if (mounted) toast(context, 'Frame gallery mein save ho gaya');
      } catch (e) {
        if (mounted) toast(context, 'Save nahi hua: $e');
      }
    } else {
      toast(context, 'Frame nahi nikal saka');
    }
  }

  // ---------- export ----------
  void _exportSheet() {
    if (s.clips.isEmpty) return;
    int res = 1080;
    int fps = 30;
    int crf = 23;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Export',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              const Text('Resolution'),
              const SizedBox(height: 6),
              _choices<int>(
                  [('720p', 720), ('1080p', 1080), ('4K', 2160)], res,
                  (v) => set(() => res = v)),
              const SizedBox(height: 14),
              const Text('Frame Rate'),
              const SizedBox(height: 6),
              _choices<int>([('24', 24), ('30', 30), ('60', 60)], fps,
                  (v) => set(() => fps = v)),
              const SizedBox(height: 14),
              const Text('Quality'),
              const SizedBox(height: 6),
              _choices<int>([('Low', 28), ('Medium', 23), ('High', 18)], crf,
                  (v) => set(() => crf = v)),
              const SizedBox(height: 8),
              const Text('4K aur 60fps mein export bohat der leta hai.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.main),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _export(res, fps, crf);
                  },
                  child: const Text('Export Video'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  (int, int) _size(int res) {
    final r = ratios[s.ratio]!;
    int w;
    int h;
    if (r[0] >= r[1]) {
      h = res;
      w = (res * r[0] / r[1]).round();
    } else {
      w = res;
      h = (res * r[1] / r[0]).round();
    }
    if (w.isOdd) w++;
    if (h.isOdd) h++;
    return (w, h);
  }

  List<String> _atempo(double sp) {
    final out = <String>[];
    var r = sp;
    while (r < 0.5) {
      out.add('atempo=0.5');
      r /= 0.5;
    }
    while (r > 2.0) {
      out.add('atempo=2.0');
      r /= 2.0;
    }
    out.add('atempo=${r.toStringAsFixed(4)}');
    return out;
  }

  Future<String?> _findFont() async {
    for (final p in [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
    ]) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  Future<List<String>> _buildArgs(
      String outPath, int w, int h, int fps, int crf) async {
    final args = <String>['-y'];
    final fc = StringBuffer();
    final labels = StringBuffer();
    var idx = 0;
    final n = s.clips.length;

    for (var i = 0; i < n; i++) {
      final c = s.clips[i];
      final dur = c.end - c.start;
      final vi = idx;
      if (c.isImage) {
        args.addAll(['-loop', '1', '-t', dur.toStringAsFixed(3), '-i', c.path]);
      } else {
        args.addAll([
          '-ss',
          c.start.toStringAsFixed(3),
          '-t',
          dur.toStringAsFixed(3),
          '-i',
          c.path
        ]);
      }
      idx++;

      final ownAudio = !c.isImage && c.hasAudio;
      var ai = -1;
      if (!ownAudio) {
        args.addAll([
          '-f',
          'lavfi',
          '-t',
          c.outDur.toStringAsFixed(3),
          '-i',
          'anullsrc=channel_layout=stereo:sample_rate=44100'
        ]);
        ai = idx;
        idx++;
      }

      // video chain
      final v = <String>[];
      if (c.rev && !c.isImage) v.add('reverse');
      v.add('setpts=(PTS-STARTPTS)/${c.speed.toStringAsFixed(4)}');
      if (c.rot == 90) v.add('transpose=1');
      if (c.rot == 180) v.addAll(['transpose=1', 'transpose=1']);
      if (c.rot == 270) v.add('transpose=2');
      if (c.flipH) v.add('hflip');
      if (c.flipV) v.add('vflip');
      v.add('scale=$w:$h:force_original_aspect_ratio=decrease');
      v.add('pad=$w:$h:(ow-iw)/2:(oh-ih)/2:black');
      v.addAll(['setsar=1', 'fps=$fps', 'format=yuv420p']);
      fc.write('[$vi:v]${v.join(',')}[v$i];');

      // audio chain
      if (ownAudio) {
        final a = <String>[];
        if (c.rev) a.add('areverse');
        a.add('asetpts=PTS-STARTPTS');
        if (c.speed != 1.0) a.addAll(_atempo(c.speed));
        a.addAll([
          'aresample=44100',
          'aformat=sample_fmts=fltp:channel_layouts=stereo'
        ]);
        fc.write('[$vi:a]${a.join(',')}[a$i];');
      } else {
        fc.write(
            '[$ai:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a$i];');
      }
      labels.write('[v$i][a$i]');
    }

    fc.write('${labels}concat=n=$n:v=1:a=1[cv][ca];');

    var textApplied = false;
    if (s.text != null) {
      final font = await _findFont();
      if (font != null) {
        final tf = File('${Directory.systemTemp.path}/ar_text.txt');
        await tf.writeAsString(s.text!);
        fc.write(
            '[cv]drawtext=fontfile=$font:textfile=${tf.path}:fontsize=${(h / 14).round()}:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2[vout];');
        textApplied = true;
      }
    }
    if (!textApplied) fc.write('[cv]null[vout];');
    fc.write('[ca]anull[aout]');

    args.addAll([
      '-filter_complex',
      fc.toString(),
      '-map',
      '[vout]',
      '-map',
      '[aout]',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '$crf',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      outPath,
    ]);
    return args;
  }

  Future<void> _export(int res, int fps, int crf) async {
    final out =
        '${Directory.systemTemp.path}/ARForge_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final size = _size(res);
    final args = await _buildArgs(out, size.$1, size.$2, fps, crf);
    final totalMs = s.clips.fold<double>(0, (a, c) => a + c.outDur) * 1000;
    final prog = ValueNotifier<double>(0);
    final logs = <String>[];

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.main,
        title: const Text('Export ho raha hai...'),
        content: ValueListenableBuilder<double>(
          valueListenable: prog,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: v == 0 ? null : v, color: AppColors.accent),
              const SizedBox(height: 10),
              Text('${(v * 100).round()}%'),
            ],
          ),
        ),
      ),
    );

    final done = Completer<dynamic>();
    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) {
        if (!done.isCompleted) done.complete(session);
      },
      (log) {
        logs.add(log.getMessage());
      },
      (stats) {
        final t = (stats.getTime() as num).toDouble();
        if (totalMs > 0) prog.value = math.min(1.0, t / totalMs);
      },
    );
    final session = await done.future;
    final rc = await session.getReturnCode();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (ReturnCode.isSuccess(rc)) {
      try {
        await Gal.putVideo(out, album: 'AR Forge');
        if (mounted) toast(context, 'Video gallery mein save ho gayi ✅');
      } catch (e) {
        if (mounted) toast(context, 'Video bani, par gallery mein save nahi hui: $e');
      }
    } else {
      final tail = logs.join('\n');
      final shown =
          tail.length > 900 ? tail.substring(tail.length - 900) : tail;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export fail ho gaya'),
          content: SingleChildScrollView(
            child: SelectableText(shown,
                style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Theek hai')),
          ],
        ),
      );
    }
  }

  // ---------- UI ----------
  Widget _canvas() {
    final clip = _clip;
    if (clip == null) {
      return const Center(
        child: Text('Neeche Import dabao aur media chuno',
            style: TextStyle(color: Colors.white54)),
      );
    }
    final r = ratios[s.ratio]!;
    Widget? content;
    if (clip.isImage) {
      content = Image.file(File(clip.path));
    } else if (_ready && _c != null) {
      final sz = _c!.value.size;
      content = SizedBox(
          width: sz.width, height: sz.height, child: VideoPlayer(_c!));
    }
    if (content != null) {
      content = RotatedBox(quarterTurns: clip.rot ~/ 90, child: content);
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
            clip.flipH ? -1.0 : 1.0, clip.flipV ? -1.0 : 1.0, 1.0),
        child: content,
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: r[0] / r[1],
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (content != null)
                ClipRect(child: FittedBox(fit: BoxFit.contain, child: content))
              else
                const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.accent)),
              if (s.text != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(s.text!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black)
                            ])),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playbar() {
    final clip = _clip;
    if (clip == null) return const SizedBox(height: 48);
    final len = clip.end - clip.start;
    final rel = _playhead - clip.start;
    final playing = _c?.value.isPlaying ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            iconSize: 34,
            color: AppColors.accent,
            icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
            onPressed: (!_ready || _c == null)
                ? null
                : () {
                    final c = _c!;
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      if (_playhead >= clip.end - 0.05) {
                        c.seekTo(Duration(
                            milliseconds: (clip.start * 1000).round()));
                      }
                      c.play();
                    }
                  },
          ),
          Text(fmtSec(rel), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: math.min(len, math.max(0.0, rel)),
              max: len > 0 ? len : 1,
              activeColor: AppColors.accent,
              onChanged: (!_ready || _c == null)
                  ? null
                  : (v) => _c!.seekTo(Duration(
                      milliseconds: ((clip.start + v) * 1000).round())),
            ),
          ),
          Text(fmtSec(len), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _timeline() {
    return SizedBox(
      height: 76,
      child: s.clips.isEmpty
          ? const Center(
              child: Text('Timeline khali hai',
                  style: TextStyle(color: Colors.white38)))
          : ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: s.clips.length,
              onReorder: _reorder,
              proxyDecorator: (child, i, a) =>
                  Material(color: Colors.transparent, child: child),
              itemBuilder: (ctx, i) {
                final c = s.clips[i];
                final w = math.min(220.0, math.max(84.0, c.outDur * 28));
                final selected = i == sel;
                return GestureDetector(
                  key: ValueKey(c.id),
                  onTap: () {
                    if (sel != i) {
                      sel = i;
                      _loadSel();
                    }
                  },
                  child: Container(
                    width: w,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected ? AppColors.accent : Colors.white12,
                          width: selected ? 2.5 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(c.isImage ? Icons.image : Icons.videocam,
                            size: 20, color: Colors.white70),
                        const SizedBox(height: 2),
                        Text(
                            '${c.outDur.toStringAsFixed(1)}s${c.speed != 1.0 ? ' · ${c.speed}x' : ''}',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context)),
                Expanded(
                    child: Text(widget.project.name,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: _undo.isEmpty ? null : _doUndo),
                IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: _redo.isEmpty ? null : _doRedo),
                Padding(
                  padding: const EdgeInsets.only(right: 12, left: 4),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.main),
                    onPressed: _exportSheet,
                    child: const Text('Export'),
                  ),
                ),
              ],
            ),
            Expanded(child: _canvas()),
            _playbar(),
            _timeline(),
            Container(
              height: 72,
              color: AppColors.main,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _tool(Icons.add_photo_alternate, 'Import', _import),
                  _tool(Icons.content_cut, 'Trim', _trim),
                  _tool(Icons.call_split, 'Split', _split),
                  _tool(Icons.delete_outline, 'Delete', _delete),
                  _tool(Icons.copy, 'Duplicate', _duplicate),
                  _tool(Icons.speed, 'Speed', _speed),
                  _tool(Icons.rotate_right, 'Rotate', _rotate),
                  _tool(Icons.flip, 'Flip H', () => _flip(true)),
                  _tool(Icons.flip_camera_android, 'Flip V', () => _flip(false)),
                  _tool(Icons.aspect_ratio, 'Ratio', _ratio),
                  _tool(Icons.text_fields, 'Text', _text),
                  _tool(Icons.photo_camera, 'Frame', _extractFrame),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const ARForgeApp());

class AppColors {
  static const main = Color(0xFF2D3E2C);
  static const accent = Color(0xFFE4FD97);
  static const dark = Color(0xFF1B261A);
  static const card = Color(0xFF354A34);
}

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

// ---------------- 1. SPLASH ----------------
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
            const Text('AR',
                style: TextStyle(
                    fontSize: 90,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent)),
            const Text('AR Forge',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 6),
            const Text('Created by Muhammad Ali',
                style: TextStyle(color: Colors.white60)),
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

// ---------------- MAIN SHELL (nav like sketch) ----------------
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    Center(child: Text('Audio')),
    Center(child: Text('Projects')),
    Center(child: Text('Profile')),
  ];

  void _onTap(int i) => setState(() => _index = i);

  Widget _navItem(IconData icon, String label, int i) {
    final selected = _index == i;
    return InkWell(
      onTap: () => _onTap(i),
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
      bottomNavigationBar: Container(
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
              onTap: () {}, // TODO: new project
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
    );
  }
}

// ---------------- 3. HOME ----------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      (Icons.auto_awesome, 'AI Tools'),
      (Icons.grid_view_rounded, 'Templates'),
      (Icons.edit_note_rounded, 'AI Prompt'),
      (Icons.music_note_rounded, 'Audio'),
    ];
    final recent = [
      ('Cinematic Travel', '2h ago · 00:32'),
      ('Short Edit', '5h ago · 00:18'),
      ('Documentary Style', '1d ago · 01:12'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: const [
            Text('AR ',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent)),
            Text('Forge',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            Spacer(),
            Icon(Icons.workspace_premium, color: AppColors.accent),
            SizedBox(width: 14),
            Icon(Icons.search),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
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
                    Text('Start editing your next masterpiece',
                        style: TextStyle(color: AppColors.main, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.main),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: tools
              .map((t) => Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16)),
                        child: Icon(t.$1, color: AppColors.accent),
                      ),
                      const SizedBox(height: 6),
                      Text(t.$2, style: const TextStyle(fontSize: 12)),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: const [
            Text('Recent Projects',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Spacer(),
            Text('See all', style: TextStyle(color: AppColors.accent)),
          ],
        ),
        const SizedBox(height: 10),
        ...recent.map((r) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.movie, color: Colors.white38),
              ),
              title: Text(r.$1),
              subtitle: Text(r.$2,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.more_vert, color: Colors.white54),
            )),
      ],
    );
  }
}

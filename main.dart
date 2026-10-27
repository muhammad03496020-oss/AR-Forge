import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  docsDir = await getApplicationDocumentsDirectory();
  await loadAll();
  runApp(const ARForgeApp());
}

class AppColors {
  static const main = Color(0xFF2D3E2C);
  static const accent = Color(0xFFE4FD97);
  static const dark = Color(0xFF1B261A);
  static const card = Color(0xFF354A34);
}

// =====================================================
// BASIC HELPERS
// =====================================================
int _nextId = 1;
int _newId() => _nextId++;
double _d(dynamic v, double def) => v is num ? v.toDouble() : def;
int _i(dynamic v, int def) => v is num ? v.toInt() : def;
bool _b(dynamic v, bool def) => v is bool ? v : def;
String _s(dynamic v, String def) => v is String ? v : def;

late Directory docsDir;

Directory get mediaDir {
  final d = Directory('${docsDir.path}/media');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

String newMediaPath(String ext) =>
    '${mediaDir.path}/m_${DateTime.now().microsecondsSinceEpoch}.$ext';

int defRes = 1080;
int defFps = 30;
int defCrf = 23;

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void info(BuildContext context, String title, String text) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.main,
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('OK')),
      ],
    ),
  );
}

String fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String fmtSec(double s) => fmt(Duration(milliseconds: (s * 1000).round()));

String timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

Future<bool> runFF(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  final rc = await session.getReturnCode();
  return ReturnCode.isSuccess(rc);
}

Future<double> mediaDuration(String path) async {
  try {
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    final d = c.value.duration.inMilliseconds / 1000.0;
    await c.dispose();
    return d;
  } catch (_) {
    return 0;
  }
}

Future<bool> hasAudioStream(String path) async {
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

// =====================================================
// MODELS
// =====================================================
class Clip {
  int id;
  String path;
  bool isImage;
  double srcDur;
  bool hasAudio;
  double start;
  double end;
  double speed;
  bool rev;
  int rot;
  bool flipH;
  bool flipV;
  double volume;
  String filter;
  double bright;
  double contrast;
  double sat;
  double blur;
  double mosaic;
  String fit;
  double zoom;
  String transition;
  bool denoise;
  bool stab;
  bool aDenoise;

  Clip({
    required this.id,
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
    this.volume = 1.0,
    this.filter = 'none',
    this.bright = 0,
    this.contrast = 1,
    this.sat = 1,
    this.blur = 0,
    this.mosaic = 0,
    this.fit = 'fit',
    this.zoom = 1,
    this.transition = 'none',
    this.denoise = false,
    this.stab = false,
    this.aDenoise = false,
  });

  factory Clip.make({
    required String path,
    required bool isImage,
    required double srcDur,
    required bool hasAudio,
    required double start,
    required double end,
  }) =>
      Clip(
          id: _newId(),
          path: path,
          isImage: isImage,
          srcDur: srcDur,
          hasAudio: hasAudio,
          start: start,
          end: end);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'isImage': isImage,
        'srcDur': srcDur,
        'hasAudio': hasAudio,
        'start': start,
        'end': end,
        'speed': speed,
        'rev': rev,
        'rot': rot,
        'flipH': flipH,
        'flipV': flipV,
        'volume': volume,
        'filter': filter,
        'bright': bright,
        'contrast': contrast,
        'sat': sat,
        'blur': blur,
        'mosaic': mosaic,
        'fit': fit,
        'zoom': zoom,
        'transition': transition,
        'denoise': denoise,
        'stab': stab,
        'aDenoise': aDenoise,
      };

  factory Clip.fromJson(Map<String, dynamic> j, {bool newId = false}) {
    var id = newId ? _newId() : _i(j['id'], _newId());
    if (id >= _nextId) _nextId = id + 1;
    return Clip(
      id: id,
      path: _s(j['path'], ''),
      isImage: _b(j['isImage'], false),
      srcDur: _d(j['srcDur'], 1),
      hasAudio: _b(j['hasAudio'], false),
      start: _d(j['start'], 0),
      end: _d(j['end'], 1),
      speed: _d(j['speed'], 1),
      rev: _b(j['rev'], false),
      rot: _i(j['rot'], 0),
      flipH: _b(j['flipH'], false),
      flipV: _b(j['flipV'], false),
      volume: _d(j['volume'], 1),
      filter: _s(j['filter'], 'none'),
      bright: _d(j['bright'], 0),
      contrast: _d(j['contrast'], 1),
      sat: _d(j['sat'], 1),
      blur: _d(j['blur'], 0),
      mosaic: _d(j['mosaic'], 0),
      fit: _s(j['fit'], 'fit'),
      zoom: _d(j['zoom'], 1),
      transition: _s(j['transition'], 'none'),
      denoise: _b(j['denoise'], false),
      stab: _b(j['stab'], false),
      aDenoise: _b(j['aDenoise'], false),
    );
  }

  Clip copy({bool newId = false}) => Clip.fromJson(toJson(), newId: newId);

  double get outDur => math.max(0.05, (end - start) / speed);
}

class OverlayItem {
  int id;
  String kind; // text, sticker, image, video
  String path;
  String preview;
  String label;
  int color;
  double fontSize;
  bool bg;
  double x;
  double y;
  double scale;
  double rot;
  double opacity;
  double start;
  double end;
  double srcStart;
  bool chroma;

  OverlayItem({
    required this.id,
    required this.kind,
    required this.path,
    required this.preview,
    this.label = '',
    this.color = 0xFFFFFFFF,
    this.fontSize = 96,
    this.bg = false,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 0.4,
    this.rot = 0,
    this.opacity = 1,
    this.start = 0,
    this.end = 3,
    this.srcStart = 0,
    this.chroma = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'path': path,
        'preview': preview,
        'label': label,
        'color': color,
        'fontSize': fontSize,
        'bg': bg,
        'x': x,
        'y': y,
        'scale': scale,
        'rot': rot,
        'opacity': opacity,
        'start': start,
        'end': end,
        'srcStart': srcStart,
        'chroma': chroma,
      };

  factory OverlayItem.fromJson(Map<String, dynamic> j, {bool newId = false}) {
    var id = newId ? _newId() : _i(j['id'], _newId());
    if (id >= _nextId) _nextId = id + 1;
    return OverlayItem(
      id: id,
      kind: _s(j['kind'], 'image'),
      path: _s(j['path'], ''),
      preview: _s(j['preview'], ''),
      label: _s(j['label'], ''),
      color: _i(j['color'], 0xFFFFFFFF),
      fontSize: _d(j['fontSize'], 96),
      bg: _b(j['bg'], false),
      x: _d(j['x'], 0.5),
      y: _d(j['y'], 0.5),
      scale: _d(j['scale'], 0.4),
      rot: _d(j['rot'], 0),
      opacity: _d(j['opacity'], 1),
      start: _d(j['start'], 0),
      end: _d(j['end'], 3),
      srcStart: _d(j['srcStart'], 0),
      chroma: _b(j['chroma'], false),
    );
  }

  OverlayItem copy({bool newId = false}) =>
      OverlayItem.fromJson(toJson(), newId: newId);
}

class AudioItem {
  int id;
  String path;
  String name;
  double srcDur;
  double trimStart;
  double trimEnd;
  double start;
  double volume;
  double fadeIn;
  double fadeOut;
  bool denoise;

  AudioItem({
    required this.id,
    required this.path,
    required this.name,
    required this.srcDur,
    required this.trimStart,
    required this.trimEnd,
    this.start = 0,
    this.volume = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.denoise = false,
  });

  double get len => math.max(0.1, trimEnd - trimStart);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'srcDur': srcDur,
        'trimStart': trimStart,
        'trimEnd': trimEnd,
        'start': start,
        'volume': volume,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'denoise': denoise,
      };

  factory AudioItem.fromJson(Map<String, dynamic> j, {bool newId = false}) {
    var id = newId ? _newId() : _i(j['id'], _newId());
    if (id >= _nextId) _nextId = id + 1;
    return AudioItem(
      id: id,
      path: _s(j['path'], ''),
      name: _s(j['name'], 'Audio'),
      srcDur: _d(j['srcDur'], 1),
      trimStart: _d(j['trimStart'], 0),
      trimEnd: _d(j['trimEnd'], 1),
      start: _d(j['start'], 0),
      volume: _d(j['volume'], 1),
      fadeIn: _d(j['fadeIn'], 0),
      fadeOut: _d(j['fadeOut'], 0),
      denoise: _b(j['denoise'], false),
    );
  }

  AudioItem copy({bool newId = false}) =>
      AudioItem.fromJson(toJson(), newId: newId);
}

class EditState {
  List<Clip> clips = [];
  List<OverlayItem> overlays = [];
  List<AudioItem> audios = [];
  String ratio = '9:16';
  String bgMode = 'color'; // color or blur
  int bgColor = 0xFF000000;
  bool duck = false;

  Map<String, dynamic> toJson() => {
        'clips': clips.map((e) => e.toJson()).toList(),
        'overlays': overlays.map((e) => e.toJson()).toList(),
        'audios': audios.map((e) => e.toJson()).toList(),
        'ratio': ratio,
        'bgMode': bgMode,
        'bgColor': bgColor,
        'duck': duck,
      };

  factory EditState.fromJson(Map<String, dynamic> j) {
    final e = EditState();
    e.clips = ((j['clips'] as List?) ?? [])
        .map((x) => Clip.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    e.overlays = ((j['overlays'] as List?) ?? [])
        .map((x) => OverlayItem.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    e.audios = ((j['audios'] as List?) ?? [])
        .map((x) => AudioItem.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
    e.ratio = _s(j['ratio'], '9:16');
    e.bgMode = _s(j['bgMode'], 'color');
    e.bgColor = _i(j['bgColor'], 0xFF000000);
    e.duck = _b(j['duck'], false);
    return e;
  }
}

class Project {
  String name;
  final DateTime created;
  EditState state;
  Project({required this.name, required this.created, EditState? state})
      : state = state ?? EditState();

  Map<String, dynamic> toJson() => {
        'name': name,
        'created': created.toIso8601String(),
        'state': state.toJson(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: _s(j['name'], 'Project'),
        created: DateTime.tryParse(_s(j['created'], '')) ?? DateTime.now(),
        state: EditState.fromJson(Map<String, dynamic>.from(j['state'] as Map)),
      );
}

class TemplateDef {
  String name;
  String desc;
  String ratio;
  String filter;
  String transition;
  List<Map<String, dynamic>> texts;
  int color;
  bool builtIn;

  TemplateDef({
    required this.name,
    required this.desc,
    required this.ratio,
    required this.filter,
    required this.transition,
    required this.texts,
    required this.color,
    this.builtIn = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'desc': desc,
        'ratio': ratio,
        'filter': filter,
        'transition': transition,
        'texts': texts,
        'color': color,
      };

  factory TemplateDef.fromJson(Map<String, dynamic> j) => TemplateDef(
        name: _s(j['name'], 'Template'),
        desc: _s(j['desc'], ''),
        ratio: _s(j['ratio'], '9:16'),
        filter: _s(j['filter'], 'none'),
        transition: _s(j['transition'], 'none'),
        texts: ((j['texts'] as List?) ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList(),
        color: _i(j['color'], 0xFF455A64),
      );
}

final ValueNotifier<List<Project>> projects = ValueNotifier<List<Project>>([]);
final ValueNotifier<List<TemplateDef>> userTemplates =
    ValueNotifier<List<TemplateDef>>([]);

final List<TemplateDef> builtinTemplates = [
  TemplateDef(
      name: 'Cinematic',
      desc: 'Wide 16:9, film colors, fade through black',
      ratio: '16:9',
      filter: 'cinematic',
      transition: 'fadeblack',
      texts: [
        {'t': 'YOUR TITLE', 'x': 0.5, 'y': 0.85, 's': 0.0, 'e': 3.0, 'f': 80.0}
      ],
      color: 0xFF37474F,
      builtIn: true),
  TemplateDef(
      name: 'Travel',
      desc: 'Warm colors with slide transitions',
      ratio: '16:9',
      filter: 'warm',
      transition: 'slideleft',
      texts: [
        {'t': 'My Trip', 'x': 0.5, 'y': 0.12, 's': 0.0, 'e': 3.0, 'f': 96.0}
      ],
      color: 0xFF8D6E63,
      builtIn: true),
  TemplateDef(
      name: 'Reels',
      desc: 'Vertical 9:16, vivid colors, zoom transitions',
      ratio: '9:16',
      filter: 'vivid',
      transition: 'zoomin',
      texts: [],
      color: 0xFFAD1457,
      builtIn: true),
  TemplateDef(
      name: 'Vlog',
      desc: 'Vertical, warm look, smooth slides',
      ratio: '9:16',
      filter: 'warm',
      transition: 'slideleft',
      texts: [
        {'t': 'VLOG', 'x': 0.5, 'y': 0.1, 's': 0.0, 'e': 2.5, 'f': 110.0}
      ],
      color: 0xFF2E7D32,
      builtIn: true),
  TemplateDef(
      name: 'Gaming',
      desc: 'Dramatic contrast with pixel transitions',
      ratio: '16:9',
      filter: 'dramatic',
      transition: 'pixelize',
      texts: [],
      color: 0xFF4527A0,
      builtIn: true),
  TemplateDef(
      name: 'Business',
      desc: 'Clean enhanced look, soft dissolves',
      ratio: '16:9',
      filter: 'enhance',
      transition: 'dissolve',
      texts: [],
      color: 0xFF1565C0,
      builtIn: true),
  TemplateDef(
      name: 'Vintage',
      desc: 'Retro 4:3 with faded colors',
      ratio: '4:3',
      filter: 'vintage',
      transition: 'dissolve',
      texts: [],
      color: 0xFF6D4C41,
      builtIn: true),
  TemplateDef(
      name: 'Black & White',
      desc: 'Square 1:1 monochrome',
      ratio: '1:1',
      filter: 'bw',
      transition: 'fade',
      texts: [],
      color: 0xFF424242,
      builtIn: true),
];

Future<void> saveProjects() async {
  try {
    final f = File('${docsDir.path}/projects.json');
    await f.writeAsString(
        jsonEncode(projects.value.map((p) => p.toJson()).toList()));
  } catch (_) {}
}

Future<void> saveTemplates() async {
  try {
    final f = File('${docsDir.path}/templates.json');
    await f.writeAsString(
        jsonEncode(userTemplates.value.map((p) => p.toJson()).toList()));
  } catch (_) {}
}

Future<void> loadAll() async {
  try {
    final f = File('${docsDir.path}/projects.json');
    if (await f.exists()) {
      final list = jsonDecode(await f.readAsString()) as List;
      projects.value = list
          .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  } catch (_) {}
  try {
    final f = File('${docsDir.path}/templates.json');
    if (await f.exists()) {
      final list = jsonDecode(await f.readAsString()) as List;
      userTemplates.value = list
          .map((e) => TemplateDef.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  } catch (_) {}
}

// =====================================================
// FILTERS (export string + preview matrix)
// =====================================================
List<double> matMul(List<double> a, List<double> b) {
  List<List<double>> to5(List<double> m) => [
        m.sublist(0, 5),
        m.sublist(5, 10),
        m.sublist(10, 15),
        m.sublist(15, 20),
        [0, 0, 0, 0, 1],
      ];
  final A = to5(a);
  final B = to5(b);
  final out = <double>[];
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var sum = 0.0;
      for (var k = 0; k < 5; k++) {
        sum += A[i][k] * B[k][j];
      }
      out.add(sum);
    }
  }
  return out;
}

const List<double> idM = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

List<double> satM(double s) {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  final i = 1 - s;
  return [
    lr * i + s, lg * i, lb * i, 0, 0, //
    lr * i, lg * i + s, lb * i, 0, 0, //
    lr * i, lg * i, lb * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

List<double> conM(double c) {
  final o = (0.5 - 0.5 * c) * 255;
  return [
    c, 0, 0, 0, o, //
    0, c, 0, 0, o, //
    0, 0, c, 0, o, //
    0, 0, 0, 1, 0,
  ];
}

List<double> briM(double b) {
  final o = b * 255;
  return [
    1, 0, 0, 0, o, //
    0, 1, 0, 0, o, //
    0, 0, 1, 0, o, //
    0, 0, 0, 1, 0,
  ];
}

class FilterDef {
  final String id;
  final String name;
  final String ff;
  final List<double> m;
  FilterDef(this.id, this.name, this.ff, this.m);
}

final List<FilterDef> filterDefs = [
  FilterDef('none', 'Original', '', idM),
  FilterDef('enhance', 'Enhance',
      'unsharp=5:5:.8:5:5:0,eq=contrast=1.08:saturation=1.15',
      matMul(conM(1.08), satM(1.15))),
  FilterDef('vivid', 'Vivid', 'eq=saturation=1.5:contrast=1.08',
      matMul(conM(1.08), satM(1.5))),
  FilterDef('warm', 'Warm',
      'colorbalance=rs=.15:gs=.03:bs=-.15:rm=.1:bm=-.1', const [
    1.1, 0, 0, 0, 10, //
    0, 1.0, 0, 0, 0, //
    0, 0, 0.88, 0, -10, //
    0, 0, 0, 1, 0,
  ]),
  FilterDef('cool', 'Cool', 'colorbalance=rs=-.12:bs=.18:bm=.1', const [
    0.9, 0, 0, 0, -8, //
    0, 1.0, 0, 0, 0, //
    0, 0, 1.15, 0, 15, //
    0, 0, 0, 1, 0,
  ]),
  FilterDef('cinematic', 'Cinematic',
      'eq=contrast=1.15:saturation=1.2:gamma=.95,colorbalance=rs=.08:bs=-.08:rh=.06:bh=-.04',
      matMul(conM(1.15), satM(1.2))),
  FilterDef('dramatic', 'Dramatic', 'eq=contrast=1.4:saturation=1.1:brightness=-.04',
      matMul(briM(-0.04), matMul(conM(1.4), satM(1.1)))),
  FilterDef('vintage', 'Vintage', 'curves=vintage', const [
    0.9, 0.1, 0.05, 0, 12, //
    0.1, 0.8, 0.1, 0, 6, //
    0.05, 0.1, 0.7, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  FilterDef('sepia', 'Sepia',
      'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131', const [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  FilterDef('fade', 'Fade', 'eq=contrast=.85:brightness=.06:saturation=.8',
      matMul(briM(0.06), matMul(conM(0.85), satM(0.8)))),
  FilterDef('bw', 'B&W', 'hue=s=0', satM(0)),
  FilterDef('sharp', 'Sharp', 'unsharp=5:5:1.2:5:5:0', idM),
];

FilterDef filterById(String id) =>
    filterDefs.firstWhere((f) => f.id == id, orElse: () => filterDefs.first);

List<double> previewMatrix(Clip c) {
  var m = filterById(c.filter).m;
  if (c.bright.abs() > 0.001 ||
      (c.contrast - 1).abs() > 0.001 ||
      (c.sat - 1).abs() > 0.001) {
    final adj = matMul(satM(c.sat), matMul(conM(c.contrast), briM(c.bright)));
    m = matMul(adj, m);
  }
  return m;
}

const List<String> transitionIds = [
  'none',
  'fade',
  'fadeblack',
  'dissolve',
  'wipeleft',
  'wiperight',
  'slideleft',
  'slideright',
  'slideup',
  'circleopen',
  'zoomin',
  'pixelize',
  'radial',
];

String transitionName(String id) {
  switch (id) {
    case 'none':
      return 'None';
    case 'fade':
      return 'Fade';
    case 'fadeblack':
      return 'Fade Black';
    case 'dissolve':
      return 'Dissolve';
    case 'wipeleft':
      return 'Wipe Left';
    case 'wiperight':
      return 'Wipe Right';
    case 'slideleft':
      return 'Slide Left';
    case 'slideright':
      return 'Slide Right';
    case 'slideup':
      return 'Slide Up';
    case 'circleopen':
      return 'Circle';
    case 'zoomin':
      return 'Zoom In';
    case 'pixelize':
      return 'Pixelate';
    case 'radial':
      return 'Radial';
  }
  return id;
}

// =====================================================
// TEXT / STICKER RENDERING (to PNG, used by preview + export)
// =====================================================
Future<(String, int, int)> renderTextPng(
  String text, {
  int color = 0xFFFFFFFF,
  double fontSize = 96,
  bool bg = false,
  bool shadow = true,
  bool bold = true,
}) async {
  final style = TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    color: Color(color),
    shadows: (shadow && !bg)
        ? const [Shadow(blurRadius: 5, color: Colors.black, offset: Offset(2, 2))]
        : null,
  );
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 6,
  )..layout(maxWidth: 1400);
  const pad = 24.0;
  final w = (tp.width + pad * 2).ceil();
  final h = (tp.height + pad * 2).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (bg) {
    final paint = Paint()..color = const Color(0xAA000000);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            const Radius.circular(24)),
        paint);
  }
  tp.paint(canvas, const Offset(pad, pad));
  final img = await recorder.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final path = newMediaPath('png');
  await File(path).writeAsBytes(data!.buffer.asUint8List());
  return (path, w, h);
}

Future<OverlayItem> makeTextOverlay(
  String text, {
  int color = 0xFFFFFFFF,
  double fontSize = 96,
  bool bg = false,
  double x = 0.5,
  double y = 0.5,
  double start = 0,
  double end = 3,
}) async {
  final r = await renderTextPng(text, color: color, fontSize: fontSize, bg: bg);
  return OverlayItem(
    id: _newId(),
    kind: 'text',
    path: r.$1,
    preview: r.$1,
    label: text,
    color: color,
    fontSize: fontSize,
    bg: bg,
    x: x,
    y: y,
    scale: math.min(0.9, r.$2 / 1080.0),
    start: start,
    end: end,
  );
}

// =====================================================
// IN-APP GALLERY PICKER
// =====================================================
class PickedMedia {
  final String path;
  final bool isImage;
  final bool isAudio;
  final String name;
  final double dur;
  PickedMedia({
    required this.path,
    required this.isImage,
    required this.isAudio,
    required this.name,
    required this.dur,
  });
}

enum PickKind { visual, audio }

Future<List<PickedMedia>> pickMedia(BuildContext context,
    {PickKind kind = PickKind.visual, bool multi = true}) async {
  final r = await Navigator.push<List<PickedMedia>>(
    context,
    MaterialPageRoute(builder: (_) => GalleryPicker(kind: kind, multi: multi)),
  );
  return r ?? [];
}

class _Thumb extends StatefulWidget {
  final AssetEntity asset;
  const _Thumb(this.asset);
  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<dynamic> f;
  @override
  void initState() {
    super.initState();
    f = widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(240));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: f,
      builder: (ctx, snap) {
        if (snap.data == null) {
          return Container(color: AppColors.card);
        }
        return Image.memory(snap.data, fit: BoxFit.cover);
      },
    );
  }
}

class GalleryPicker extends StatefulWidget {
  final PickKind kind;
  final bool multi;
  const GalleryPicker({super.key, required this.kind, required this.multi});
  @override
  State<GalleryPicker> createState() => _GalleryPickerState();
}

class _GalleryPickerState extends State<GalleryPicker> {
  List<AssetEntity> assets = [];
  final List<AssetEntity> picked = [];
  bool loading = true;
  bool denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) {
        setState(() {
          denied = true;
          loading = false;
        });
      }
      return;
    }
    final type =
        widget.kind == PickKind.audio ? RequestType.audio : RequestType.common;
    final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: type);
    List<AssetEntity> list = [];
    if (paths.isNotEmpty) {
      list = await paths.first.getAssetListPaged(page: 0, size: 800);
    }
    if (mounted) {
      setState(() {
        assets = list;
        loading = false;
        denied = false;
      });
    }
  }

  void _tap(AssetEntity a) {
    setState(() {
      if (!widget.multi) {
        picked
          ..clear()
          ..add(a);
        return;
      }
      if (picked.any((p) => p.id == a.id)) {
        picked.removeWhere((p) => p.id == a.id);
      } else {
        picked.add(a);
      }
    });
    if (!widget.multi) _done();
  }

  Future<void> _done() async {
    final out = <PickedMedia>[];
    for (final a in picked) {
      final f = await a.file;
      if (f == null) continue;
      out.add(PickedMedia(
        path: f.path,
        isImage: a.type == AssetType.image,
        isAudio: a.type == AssetType.audio,
        name: a.title ?? 'Audio',
        dur: a.duration.toDouble(),
      ));
    }
    if (mounted) Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final isAudio = widget.kind == PickKind.audio;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.dark,
        title: Text(isAudio ? 'Choose audio' : 'Choose media'),
        actions: [
          if (widget.multi && picked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.main),
                onPressed: _done,
                child: Text('Add (${picked.length})'),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : denied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 48, color: AppColors.accent),
                        const SizedBox(height: 12),
                        const Text(
                            'AR Forge needs access to your photos, videos and audio to edit them.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.main),
                          onPressed: () async {
                            await PhotoManager.openSetting();
                          },
                          child: const Text('Open Settings'),
                        ),
                        TextButton(
                            onPressed: _load, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              : assets.isEmpty
                  ? const Center(child: Text('Nothing found on this phone'))
                  : isAudio
                      ? ListView.builder(
                          itemCount: assets.length,
                          itemBuilder: (ctx, i) {
                            final a = assets[i];
                            final idx = picked.indexWhere((p) => p.id == a.id);
                            return ListTile(
                              leading: Icon(Icons.music_note,
                                  color: idx >= 0
                                      ? AppColors.accent
                                      : Colors.white54),
                              title: Text(a.title ?? 'Audio',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  fmt(Duration(seconds: a.duration)),
                                  style:
                                      const TextStyle(color: Colors.white54)),
                              trailing: idx >= 0
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.accent)
                                  : null,
                              onTap: () => _tap(a),
                            );
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(4),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 3,
                                  crossAxisSpacing: 3),
                          itemCount: assets.length,
                          itemBuilder: (ctx, i) {
                            final a = assets[i];
                            final idx = picked.indexWhere((p) => p.id == a.id);
                            return GestureDetector(
                              onTap: () => _tap(a),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _Thumb(a),
                                  if (a.type == AssetType.video)
                                    Positioned(
                                      right: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        color: Colors.black54,
                                        child: Text(
                                            fmt(Duration(seconds: a.duration)),
                                            style: const TextStyle(
                                                fontSize: 11)),
                                      ),
                                    ),
                                  if (idx >= 0)
                                    Container(
                                      color: Colors.black45,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.all(6),
                                      child: CircleAvatar(
                                        radius: 11,
                                        backgroundColor: AppColors.accent,
                                        child: Text('${idx + 1}',
                                            style: const TextStyle(
                                                color: AppColors.main,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
    );
  }
}

Future<List<Clip>> clipsFromPicked(List<PickedMedia> media) async {
  final out = <Clip>[];
  for (final m in media) {
    if (m.isAudio) continue;
    if (m.isImage) {
      out.add(Clip.make(
          path: m.path,
          isImage: true,
          srcDur: 10,
          hasAudio: false,
          start: 0,
          end: 3));
    } else {
      final d = await mediaDuration(m.path);
      if (d <= 0) continue;
      final a = await hasAudioStream(m.path);
      out.add(Clip.make(
          path: m.path,
          isImage: false,
          srcDur: d,
          hasAudio: a,
          start: 0,
          end: d));
    }
  }
  return out;
}

// =====================================================
// PROJECT CREATION + TEMPLATES + SMART STYLE
// =====================================================
Future<void> applyTemplate(EditState st, TemplateDef t) async {
  st.ratio = t.ratio;
  for (var i = 0; i < st.clips.length; i++) {
    st.clips[i].filter = t.filter;
    st.clips[i].transition = i < st.clips.length - 1 ? t.transition : 'none';
  }
  for (final x in t.texts) {
    final o = await makeTextOverlay(
      _s(x['t'], 'Text'),
      color: _i(x['c'], 0xFFFFFFFF),
      fontSize: _d(x['f'], 96),
      bg: _b(x['bg'], false),
      x: _d(x['x'], 0.5),
      y: _d(x['y'], 0.5),
      start: _d(x['s'], 0),
      end: _d(x['e'], 3),
    );
    st.overlays.add(o);
  }
}

List<String> applyPrompt(EditState st, String prompt) {
  final p = prompt.toLowerCase();
  final done = <String>[];
  bool has(List<String> k) => k.any((e) => p.contains(e));
  void setFilter(String f, String label) {
    for (final c in st.clips) {
      c.filter = f;
    }
    done.add(label);
  }

  void setTrans(String t, String label) {
    for (var i = 0; i < st.clips.length - 1; i++) {
      st.clips[i].transition = t;
    }
    done.add(label);
  }

  if (has(['cinematic', 'movie', 'film'])) {
    setFilter('cinematic', 'Cinematic color grade');
    st.ratio = '16:9';
    done.add('16:9 ratio');
    setTrans('fadeblack', 'Fade-through-black transitions');
  }
  if (has(['short', 'reel', 'tiktok', 'vertical', 'story'])) {
    st.ratio = '9:16';
    done.add('9:16 vertical ratio');
  }
  if (has(['youtube', 'landscape', 'widescreen'])) {
    st.ratio = '16:9';
    done.add('16:9 ratio');
  }
  if (has(['square', 'instagram post'])) {
    st.ratio = '1:1';
    done.add('1:1 ratio');
  }
  if (has(['vlog'])) {
    setFilter('warm', 'Warm vlog look');
    setTrans('slideleft', 'Slide transitions');
  }
  if (has(['black and white', 'b&w', 'monochrome'])) {
    setFilter('bw', 'Black & white');
  }
  if (has(['warm', 'sunset', 'golden'])) setFilter('warm', 'Warm tones');
  if (has(['cool', 'cold', 'icy'])) setFilter('cool', 'Cool tones');
  if (has(['vintage', 'retro', 'old'])) setFilter('vintage', 'Vintage look');
  if (has(['dramatic', 'moody', 'dark'])) setFilter('dramatic', 'Dramatic look');
  if (has(['vivid', 'colorful', 'bright'])) setFilter('vivid', 'Vivid colors');
  if (has(['enhance', 'sharp', 'clear'])) setFilter('enhance', 'Enhance');
  if (has(['slow motion', 'slow-mo', 'slowmo', 'slow'])) {
    for (final c in st.clips) {
      if (!c.isImage) c.speed = 0.5;
    }
    done.add('Slow motion (0.5x)');
  }
  if (has(['fast', 'timelapse', 'time lapse', 'speed up'])) {
    for (final c in st.clips) {
      if (!c.isImage) c.speed = 2.0;
    }
    done.add('Fast motion (2x)');
  }
  if (has(['blur background', 'blurred background', 'blur bg'])) {
    st.bgMode = 'blur';
    done.add('Blurred background');
  }
  if (has(['zoom', 'transition', 'smooth'])) {
    setTrans('zoomin', 'Zoom transitions');
  }
  if (done.isEmpty) {
    setFilter('enhance', 'Enhance');
    setTrans('fade', 'Fade transitions');
  }
  return done;
}

Future<Project?> createProjectFromMedia(BuildContext context,
    {Future<void> Function(EditState)? apply}) async {
  final media = await pickMedia(context);
  if (media.isEmpty) return null;
  if (context.mounted) toast(context, 'Preparing media...');
  final clips = await clipsFromPicked(media);
  if (clips.isEmpty) return null;
  final p = Project(
      name: 'Project ${projects.value.length + 1}', created: DateTime.now());
  p.state.clips = clips;
  if (apply != null) await apply(p.state);
  projects.value = [p, ...projects.value];
  await saveProjects();
  return p;
}

Future<void> startNewProject(BuildContext context) async {
  final p = await createProjectFromMedia(context);
  if (p == null || !context.mounted) return;
  openProject(context, p);
}

void openProject(BuildContext context, Project p, {String? autoRun}) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EditorScreen(project: p, autoRun: autoRun)),
  );
}

// =====================================================
// SOUND EFFECTS (generated on the phone, royalty-free)
// =====================================================
class SfxDef {
  final String key;
  final String name;
  final List<String> src;
  final String af;
  const SfxDef(this.key, this.name, this.src, this.af);
}

const List<SfxDef> sfxList = [
  SfxDef('ding', 'Ding', ['sine=frequency=1200:duration=1.2'],
      'afade=t=out:st=0.05:d=1.1'),
  SfxDef('beep', 'Beep', ['sine=frequency=800:duration=0.4'],
      'afade=t=out:st=0.3:d=0.1'),
  SfxDef('pop', 'Pop', ['sine=frequency=520:duration=0.18'],
      'afade=t=out:st=0.02:d=0.16'),
  SfxDef('drum', 'Drum hit', ['sine=frequency=70:duration=0.6'],
      'afade=t=out:st=0.02:d=0.58'),
  SfxDef('whoosh', 'Whoosh', ['anoisesrc=d=1:c=pink:a=0.5'],
      'highpass=f=300,afade=t=in:st=0:d=0.4,afade=t=out:st=0.4:d=0.6'),
  SfxDef('laser', 'Laser', ['sine=frequency=1800:duration=0.6'],
      'vibrato=f=20:d=1,afade=t=out:st=0.2:d=0.4'),
  SfxDef('wind', 'Wind', ['anoisesrc=d=5:c=white:a=0.25'],
      'lowpass=f=700,tremolo=f=0.4:d=0.6,afade=t=in:st=0:d=1,afade=t=out:st=4:d=1'),
  SfxDef('rain', 'Rain', ['anoisesrc=d=6:c=brown:a=0.35'],
      'highpass=f=200,afade=t=in:st=0:d=1,afade=t=out:st=5:d=1'),
];

Future<String?> sfxPath(SfxDef s) async {
  final out = '${mediaDir.path}/sfx_${s.key}.wav';
  if (await File(out).exists()) return out;
  final ok = await runFF([
    '-y',
    '-f',
    'lavfi',
    '-i',
    s.src.first,
    '-af',
    s.af,
    '-ar',
    '44100',
    out,
  ]);
  return ok ? out : null;
}

// =====================================================
// SHARED WIDGET HELPERS
// =====================================================
Widget choiceChips<T>(List<(String, T)> items, T cur, void Function(T) onSel) {
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

Widget brandBlock({double logo = 52}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/logo.png', width: logo, height: logo),
      ),
      const SizedBox(height: 6),
      const Text('AR FORGE',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: Colors.white)),
      const Text('Create a forge',
          style: TextStyle(
              fontSize: 10, letterSpacing: 1, color: AppColors.accent)),
    ],
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
      title: 'AR FORGE',
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
    Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      final seen = File('${docsDir.path}/onboarded').existsSync();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                seen ? const MainShell() : const OnboardingScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child:
                      Image.asset('assets/logo.png', width: 140, height: 140),
                ),
                const SizedBox(height: 14),
                const Text('AR FORGE',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Create a forge',
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: AppColors.accent)),
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
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: 22),
                child: Text('CREATED BY: MUHAMMAD ALI',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11, letterSpacing: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Onboarding ----------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  final _slides = const [
    (Icons.movie_creation_outlined, 'Turn Your Ideas Into Stunning Videos',
        'AR Forge is your video editor. Create, edit and bring your vision to life.'),
    (Icons.content_cut, 'Powerful Editing Tools',
        'Trim, split, speed, crop, filters, transitions and more.'),
    (Icons.layers_outlined, 'Text, Stickers and Overlays',
        'Add text, stickers and picture-in-picture layers on a multi-track timeline.'),
    (Icons.music_note_outlined, 'Music and Voiceover',
        'Add music, sound effects and record your own voice.'),
  ];

  Future<void> _finish() async {
    try {
      await File('${docsDir.path}/onboarded').writeAsString('1');
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip',
                      style: TextStyle(color: AppColors.accent))),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: _slides
                    .map((s) => Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(s.$1, size: 110, color: AppColors.accent),
                              const SizedBox(height: 28),
                              Text(s.$2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 12),
                              Text(s.$3,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 15)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  _slides.length,
                  (i) => Container(
                        margin: const EdgeInsets.all(4),
                        width: i == _page ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color:
                                i == _page ? AppColors.accent : Colors.white24,
                            borderRadius: BorderRadius.circular(8)),
                      )),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.main),
                  onPressed: () {
                    if (last) {
                      _finish();
                    } else {
                      _pc.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut);
                    }
                  },
                  child: Text(last ? 'Get Started' : 'Next'),
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

  @override
  void initState() {
    super.initState();
    // Ask for gallery permission as soon as the app opens.
    PhotoManager.requestPermissionExtend();
  }

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
    final pages = [
      HomeScreen(onSearch: () => setState(() => _index = 2)),
      const AudioScreen(),
      const ProjectsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
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
                    child:
                        const Icon(Icons.add, color: AppColors.main, size: 30),
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
  final VoidCallback onSearch;
  const HomeScreen({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            brandBlock(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PremiumScreen())),
                child:
                    const Icon(Icons.workspace_premium, color: AppColors.accent),
              ),
            ),
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                  onTap: onSearch, child: const Icon(Icons.search)),
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
                      Text('Pick videos or photos and start editing',
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
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TemplatesScreen()))),
            _quick(context, Icons.edit_note_rounded, 'AI Prompt',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiPromptScreen()))),
            _quick(
                context,
                Icons.music_note_rounded,
                'Audio',
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => Scaffold(
                              appBar: AppBar(
                                  title: const Text('Audio'),
                                  backgroundColor: AppColors.dark),
                              body: const AudioScreen(),
                            )))),
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
                child: Text('No projects yet. Tap "Create New Project".',
                    style: TextStyle(color: Colors.white54)),
              );
            }
            return Column(
              children:
                  list.take(3).map((p) => projectTile(context, p)).toList(),
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

Widget projectTile(BuildContext context, Project p) {
  final secs = p.state.clips.fold<double>(0, (a, c) => a + c.outDur);
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
    subtitle: Text('${timeAgo(p.created)} · ${fmtSec(secs)}',
        style: const TextStyle(color: Colors.white54, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
  );
}

// ---------- Audio tab ----------
class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key});
  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  int tab = 0;
  List<AssetEntity> songs = [];
  bool loading = true;
  bool denied = false;
  VideoPlayerController? pc;
  String? playingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) {
        setState(() {
          denied = true;
          loading = false;
        });
      }
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
        onlyAll: true, type: RequestType.audio);
    List<AssetEntity> list = [];
    if (paths.isNotEmpty) {
      list = await paths.first.getAssetListPaged(page: 0, size: 500);
    }
    if (mounted) {
      setState(() {
        songs = list;
        loading = false;
        denied = false;
      });
    }
  }

  Future<void> _play(String key, String path) async {
    final old = pc;
    pc = null;
    await old?.dispose();
    if (playingKey == key) {
      setState(() => playingKey = null);
      return;
    }
    try {
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      c.addListener(() {
        if (!mounted) return;
        if (c.value.position >= c.value.duration &&
            c.value.duration > Duration.zero) {
          setState(() => playingKey = null);
        }
      });
      await c.play();
      pc = c;
      if (mounted) setState(() => playingKey = key);
    } catch (_) {
      if (mounted) {
        setState(() => playingKey = null);
        toast(context, 'Could not play this file');
      }
    }
  }

  @override
  void dispose() {
    pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Text('Audio',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const Spacer(),
              choiceChips<int>(
                  [('Music', 0), ('Sound Effects', 1)], tab, (v) {
                pc?.pause();
                setState(() {
                  tab = v;
                  playingKey = null;
                });
              }),
            ],
          ),
        ),
        Expanded(
          child: tab == 1
              ? ListView(
                  children: sfxList
                      .map((s) => ListTile(
                            leading: Icon(
                                playingKey == s.key
                                    ? Icons.stop_circle
                                    : Icons.play_circle_fill,
                                color: AppColors.accent),
                            title: Text(s.name),
                            subtitle: const Text('Built-in effect',
                                style: TextStyle(color: Colors.white54)),
                            onTap: () async {
                              final p = await sfxPath(s);
                              if (p == null) {
                                if (context.mounted) {
                                  toast(context, 'Could not create sound');
                                }
                                return;
                              }
                              _play(s.key, p);
                            },
                          ))
                      .toList(),
                )
              : loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent))
                  : denied
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Allow access to play your music'),
                              const SizedBox(height: 10),
                              FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.main),
                                  onPressed: () => PhotoManager.openSetting(),
                                  child: const Text('Open Settings')),
                              TextButton(
                                  onPressed: _load,
                                  child: const Text('Try again')),
                            ],
                          ),
                        )
                      : songs.isEmpty
                          ? const Center(child: Text('No music found'))
                          : ListView.builder(
                              itemCount: songs.length,
                              itemBuilder: (ctx, i) {
                                final a = songs[i];
                                return ListTile(
                                  leading: Icon(
                                      playingKey == a.id
                                          ? Icons.stop_circle
                                          : Icons.play_circle_fill,
                                      color: AppColors.accent),
                                  title: Text(a.title ?? 'Audio',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      fmt(Duration(seconds: a.duration)),
                                      style: const TextStyle(
                                          color: Colors.white54)),
                                  onTap: () async {
                                    final f = await a.file;
                                    if (f != null) _play(a.id, f.path);
                                  },
                                );
                              },
                            ),
        ),
      ],
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
                child: Text('No projects yet.',
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
                    saveProjects();
                  },
                  child: projectTile(context, p),
                )),
            if (list.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Swipe a project left to delete it',
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

  Future<int> _mediaSize() async {
    var total = 0;
    try {
      await for (final e in mediaDir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  void _exportSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Default export settings',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                const Text('Resolution'),
                const SizedBox(height: 6),
                choiceChips<int>([('720p', 720), ('1080p', 1080), ('4K', 2160)],
                    defRes, (v) => set(() => defRes = v)),
                const SizedBox(height: 14),
                const Text('Frame rate'),
                const SizedBox(height: 6),
                choiceChips<int>([('24', 24), ('30', 30), ('60', 60)], defFps,
                    (v) => set(() => defFps = v)),
                const SizedBox(height: 14),
                const Text('Quality'),
                const SizedBox(height: 6),
                choiceChips<int>([('Low', 28), ('Medium', 23), ('High', 18)],
                    defCrf, (v) => set(() => defCrf = v)),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, VoidCallback)>[
      (
        Icons.workspace_premium,
        'Subscription',
        'Free Plan',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PremiumScreen()))
      ),
      (
        Icons.storage,
        'Storage',
        '',
        () async {
          final size = await _mediaSize();
          if (context.mounted) {
            info(context, 'Storage',
                'Project media (stickers, text, audio, frames): ${(size / 1048576).toStringAsFixed(1)} MB');
          }
        }
      ),
      (
        Icons.language,
        'Language',
        'English',
        () => info(context, 'Language', 'English is the only language for now.')
      ),
      (
        Icons.settings,
        'Export Settings',
        '',
        () => _exportSettings(context)
      ),
      (
        Icons.notifications,
        'Notifications',
        '',
        () => info(context, 'Notifications',
            'AR Forge does not send notifications.')
      ),
      (
        Icons.help_outline,
        'Help & Support',
        '',
        () => info(context, 'Help & Support',
            'Tap the + button to start a project. Pick media, then use the tool bar at the bottom of the editor. Long-press a clip in the timeline to drag it to a new position.\n\nContact us: arforge.help@gmail.com')
      ),
      (
        Icons.privacy_tip_outlined,
        'Privacy',
        '',
        () => info(context, 'Privacy',
            'Your photos, videos and audio stay on your phone. AR Forge does not upload them anywhere.\n\nQuestions about privacy: arforge.help@gmail.com')
      ),
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
              onTap: e.$4,
            )),
      ],
    );
  }
}

// ---------- Premium ----------
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const feats = [
      'Multi-track timeline',
      'All filters and transitions',
      'Stickers, text and PIP',
      'Music, sound effects and voiceover',
      '4K export',
      'No watermark',
    ];
    return Scaffold(
      appBar: AppBar(
          title: const Text('AR Forge Pro'), backgroundColor: AppColors.dark),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Unlock the full creative engine.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            ...feats.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.accent, size: 20),
                    const SizedBox(width: 10),
                    Text(f),
                  ]),
                )),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.main),
                onPressed: () => info(context, 'Go Premium',
                    'Payments will be enabled once AR Forge is published on Google Play. All features are unlocked for you right now.'),
                child: const Text('Go Premium'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Templates ----------
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  Future<void> _use(BuildContext context, TemplateDef t) async {
    final p = await createProjectFromMedia(context,
        apply: (st) => applyTemplate(st, t));
    if (p == null || !context.mounted) return;
    openProject(context, p);
  }

  Widget _card(BuildContext context, TemplateDef t) {
    return GestureDetector(
      onTap: () => _use(context, t),
      onLongPress: t.builtIn
          ? null
          : () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.main,
                  title: Text('Delete "${t.name}"?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () {
                          userTemplates.value = userTemplates.value
                              .where((x) => x != t)
                              .toList();
                          saveTemplates();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Delete')),
                  ],
                ),
              );
            },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(t.color), AppColors.dark],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.movie_filter, color: AppColors.accent),
            const Spacer(),
            Text(t.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t.desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 6),
            Text('${t.ratio} · ${filterById(t.filter).name}',
                style: const TextStyle(fontSize: 10, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Templates'), backgroundColor: AppColors.dark),
      body: ValueListenableBuilder<List<TemplateDef>>(
        valueListenable: userTemplates,
        builder: (context, mine, _) {
          final all = [...builtinTemplates, ...mine];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Tap a template, pick your media, and it is applied for you. To make your own, open a project and choose Save as template from the menu.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: all.map((t) => _card(context, t)).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- AI Tools ----------
Future<void> pickProjectFor(BuildContext context, String autoRun) async {
  final list = projects.value;
  final choice = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.main,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Run on which project?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.add_circle, color: AppColors.accent),
            title: const Text('New project (pick media)'),
            onTap: () => Navigator.pop(ctx, -1),
          ),
          ...List.generate(
              list.length,
              (i) => ListTile(
                    leading: const Icon(Icons.movie, color: Colors.white54),
                    title: Text(list[i].name),
                    onTap: () => Navigator.pop(ctx, i),
                  )),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  Project? p;
  if (choice == -1) {
    p = await createProjectFromMedia(context);
  } else {
    p = list[choice];
  }
  if (p == null || !context.mounted) return;
  openProject(context, p, autoRun: autoRun);
}

class AiToolsScreen extends StatelessWidget {
  const AiToolsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, String, String, VoidCallback)>[
      (
        Icons.content_cut,
        'Auto Cut',
        'Remove silent parts automatically',
        () => pickProjectFor(context, 'autocut')
      ),
      (
        Icons.record_voice_over,
        'Text to Speech',
        'Turn text into a voiceover track',
        () => pickProjectFor(context, 'tts')
      ),
      (
        Icons.auto_fix_high,
        'Auto Enhance',
        'Sharpen, denoise and boost colors',
        () => pickProjectFor(context, 'enhance')
      ),
      (
        Icons.edit_note,
        'Smart Style',
        'Describe a style, get matching edits',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AiPromptScreen()))
      ),
    ];
    return Scaffold(
      appBar: AppBar(
          title: const Text('AI Tools'), backgroundColor: AppColors.dark),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...tools.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Icon(t.$1, color: AppColors.accent),
                  title: Text(t.$2),
                  subtitle: Text(t.$3,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: t.$4,
                ),
              )),
          const SizedBox(height: 8),
          const Text(
              'These tools run on your phone, so they work offline. Tools that need online AI services are not included yet.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------- AI Prompt (Smart Style) ----------
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

  Future<void> _go() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      toast(context, 'Describe the style you want first');
      return;
    }
    final applied = <String>[];
    final p = await createProjectFromMedia(context, apply: (st) async {
      applied.addAll(applyPrompt(st, text));
    });
    if (p == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.main,
        title: const Text('Applied to your project'),
        content: Text(applied.map((e) => '• $e').join('\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Open editor'))
        ],
      ),
    );
    if (!mounted) return;
    openProject(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      'Cinematic style',
      'Shorts edit',
      'Vlog look',
      'Slow motion',
      'Black and white',
      'Vintage retro',
    ];
    return Scaffold(
      appBar: AppBar(
          title: const Text('AI Prompt'), backgroundColor: AppColors.dark),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Describe what you want to create...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
                'Smart Style reads keywords like cinematic, shorts, vlog, slow motion, black and white, vintage, warm, cool, blur background and applies matching edits.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              maxLines: 4,
              maxLength: 300,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                hintText: 'Make it cinematic with slow motion...',
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
                        onPressed: () => setState(() {
                          _c.text = _c.text.isEmpty ? t : '${_c.text}, $t';
                        }),
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
                onPressed: _go,
                child: const Text('Pick media and apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// VIDEO EDITOR
// =====================================================
List<String> atempoChain(double sp) {
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

const List<int> swatches = [
  0xFFFFFFFF,
  0xFF000000,
  0xFFFFEB3B,
  0xFFE4FD97,
  0xFFFF5252,
  0xFF40C4FF,
  0xFFFF9800,
  0xFFE040FB,
];

const String emojiList =
    '😀 😂 😍 🥰 😎 🤩 😭 😡 👍 👏 🙏 💪 🔥 ❤️ 💯 ✨ ⭐ 🌟 🎉 🎁 🎵 🎶 📌 📍 ➡️ ⬅️ ⬆️ ⬇️ ✅ ❌ ⚠️ 💬 💡 🏆 🚀 🌈 ☀️ 🌙 ⚡ 🍕 🍔 ☕ 🎬 📸 🎮 🐶 🐱 🌸 🌍';

class EditorScreen extends StatefulWidget {
  final Project project;
  final String? autoRun;
  const EditorScreen({super.key, required this.project, this.autoRun});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Project get proj => widget.project;
  EditState get s => proj.state;

  final List<String> _undo = [];
  final List<String> _redo = [];
  int sel = 0;
  int? selOv;
  VideoPlayerController? _c;
  bool _ready = false;
  int _token = 0;
  bool _playing = false;
  Timer? _imgTimer;
  double _imgT = 0;
  double pps = 36;
  double _gScale0 = 1;
  double _gRot0 = 0;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _loadSel().then((_) {
      final a = widget.autoRun;
      if (a != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runAuto(a);
        });
      }
    });
  }

  @override
  void dispose() {
    _token++;
    _imgTimer?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    saveProjects();
    super.dispose();
  }

  Clip? get _clip => (s.clips.isNotEmpty && sel >= 0 && sel < s.clips.length)
      ? s.clips[sel]
      : null;

  void _save() => saveProjects();

  void _needClip() => toast(context, 'Add media first');

  // ---------- timing ----------
  double _tr(int i) {
    if (i < 0 || i >= s.clips.length - 1) return 0;
    final a = s.clips[i];
    final b = s.clips[i + 1];
    final lim = 0.45 * math.min(a.outDur, b.outDur);
    final d = a.transition == 'none' ? 0.05 : 0.5;
    return math.min(d, lim);
  }

  List<double> _starts() {
    final r = <double>[];
    double t = 0;
    for (var i = 0; i < s.clips.length; i++) {
      r.add(t);
      t += s.clips[i].outDur - _tr(i);
    }
    return r;
  }

  double _total() {
    if (s.clips.isEmpty) return 0;
    final st = _starts();
    return st.last + s.clips.last.outDur;
  }

  double get _globalT {
    final clip = _clip;
    if (clip == null) return 0;
    final base = _starts()[sel];
    if (clip.isImage) return base + (_imgT - clip.start);
    final c = _c;
    if (c == null) return base;
    final pos = c.value.position.inMilliseconds / 1000.0;
    final p = math.min(clip.end, math.max(clip.start, pos));
    return base + (p - clip.start) / clip.speed;
  }

  // ---------- preview control ----------
  Future<void> _loadSel({bool autoplay = false, double? seekSrc}) async {
    final token = ++_token;
    _imgTimer?.cancel();
    final old = _c;
    old?.removeListener(_tick);
    _c = null;
    _ready = false;
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await old?.dispose();
    if (!mounted || s.clips.isEmpty) return;
    if (sel >= s.clips.length) sel = s.clips.length - 1;
    if (sel < 0) sel = 0;
    final clip = s.clips[sel];
    if (clip.isImage) {
      _imgT = seekSrc ?? clip.start;
      if (mounted) setState(() {});
      if (autoplay) _play();
      return;
    }
    final c = VideoPlayerController.file(File(clip.path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (token != _token || !mounted) {
      await c.dispose();
      return;
    }
    try {
      await c.setPlaybackSpeed(clip.speed.clamp(0.25, 2.0).toDouble());
      await c.setVolume(clip.volume.clamp(0.0, 1.0).toDouble());
    } catch (_) {}
    await c.seekTo(
        Duration(milliseconds: ((seekSrc ?? clip.start) * 1000).round()));
    c.addListener(_tick);
    _c = c;
    _ready = true;
    if (mounted) setState(() {});
    if (autoplay) {
      _playing = true;
      await c.play();
    }
  }

  void _tick() {
    final c = _c;
    final clip = _clip;
    if (c == null || clip == null || !mounted) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (_playing && pos >= clip.end - 0.03) {
      _advance();
      return;
    }
    setState(() {});
  }

  void _advance() {
    if (sel < s.clips.length - 1) {
      sel++;
      _loadSel(autoplay: true);
    } else {
      _pause();
      final clip = _clip;
      if (clip != null) {
        _c?.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
        _imgT = clip.start;
      }
    }
  }

  void _startImgTimer() {
    _imgTimer?.cancel();
    _imgTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final clip = _clip;
      if (clip == null || !clip.isImage || !_playing) {
        t.cancel();
        return;
      }
      _imgT += 0.05;
      if (_imgT >= clip.end) {
        t.cancel();
        _advance();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void _play() {
    final clip = _clip;
    if (clip == null) return;
    final total = _total();
    if (_globalT >= total - 0.1 && sel != 0) {
      sel = 0;
      _loadSel(autoplay: true);
      return;
    }
    _playing = true;
    if (clip.isImage) {
      if (_imgT >= clip.end - 0.05) _imgT = clip.start;
      _startImgTimer();
    } else {
      final c = _c;
      if (c == null) return;
      final pos = c.value.position.inMilliseconds / 1000.0;
      if (pos >= clip.end - 0.05) {
        c.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
      }
      c.play();
    }
    if (mounted) setState(() {});
  }

  void _pause() {
    _playing = false;
    _imgTimer?.cancel();
    _c?.pause();
    if (mounted) setState(() {});
  }

  Future<void> _seekGlobal(double g) async {
    if (s.clips.isEmpty) return;
    final st = _starts();
    var idx = 0;
    for (var i = 0; i < s.clips.length; i++) {
      if (g >= st[i]) idx = i;
    }
    final clip = s.clips[idx];
    final off = math.max(0.0, math.min(clip.outDur, g - st[idx]));
    final src = clip.start + off * clip.speed;
    if (idx != sel) {
      sel = idx;
      await _loadSel(autoplay: _playing, seekSrc: src);
    } else if (clip.isImage) {
      setState(() => _imgT = src);
    } else {
      _c?.seekTo(Duration(milliseconds: (src * 1000).round()));
    }
  }

  // ---------- state changes ----------
  void _pushUndo() {
    _undo.add(jsonEncode(s.toJson()));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _commit(VoidCallback change, {bool reload = false}) {
    _pushUndo();
    setState(change);
    _save();
    if (reload) _loadSel();
  }

  void _restore(String json) {
    proj.state = EditState.fromJson(
        Map<String, dynamic>.from(jsonDecode(json) as Map));
    if (sel >= s.clips.length) sel = s.clips.length - 1;
    if (sel < 0) sel = 0;
    setState(() {});
    _save();
    _loadSel();
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    _redo.add(jsonEncode(s.toJson()));
    _restore(_undo.removeLast());
  }

  void _doRedo() {
    if (_redo.isEmpty) return;
    _undo.add(jsonEncode(s.toJson()));
    _restore(_redo.removeLast());
  }

  Future<void> _runAuto(String a) async {
    if (a == 'autocut') {
      await _autoCut();
    } else if (a == 'tts') {
      await _ttsDialog();
    } else if (a == 'enhance') {
      _autoEnhance();
    }
  }

  // ---------- generic sheets ----------
  Future<void> _sheet(String title, Widget Function(StateSetter set) body,
      {bool snapshot = true, VoidCallback? onClose}) async {
    if (snapshot) _pushUndo();
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, set) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  body((fn) {
                    set(fn);
                    if (mounted) setState(() {});
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _save();
    if (onClose != null) onClose();
  }

  Widget _slider(String label, double v, double mn, double mx,
      ValueChanged<double> on,
      {String Function(double)? show}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${show != null ? show(v) : v.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: v.clamp(mn, mx).toDouble(),
          min: mn,
          max: mx,
          activeColor: AppColors.accent,
          onChanged: on,
        ),
      ],
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback on) {
    return OutlinedButton.icon(
      onPressed: on,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  void _menu(String title, List<(IconData, String, VoidCallback)> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 10,
                children: items
                    .map((e) => InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            e.$3();
                          },
                          child: SizedBox(
                            width: 82,
                            child: Column(
                              children: [
                                Icon(e.$1, color: AppColors.accent),
                                const SizedBox(height: 4),
                                Text(e.$2,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- menus ----------
  void _editMenu() => _menu('Edit', [
        (Icons.add_photo_alternate, 'Add media', _addMedia),
        (Icons.content_cut, 'Trim', _trim),
        (Icons.call_split, 'Split', _split),
        (Icons.delete_outline, 'Delete', _delete),
        (Icons.copy, 'Duplicate', _duplicate),
        (Icons.speed, 'Speed / Reverse', _speed),
        (Icons.crop, 'Crop / Fit', _crop),
        (Icons.rotate_right, 'Rotate', _rotate),
        (Icons.flip, 'Mirror', () => _flip(true)),
        (Icons.flip_camera_android, 'Flip', () => _flip(false)),
        (Icons.ac_unit, 'Freeze frame', _freeze),
        (Icons.photo_camera, 'Save frame', _saveFrame),
        (Icons.arrow_back, 'Move left', () => _move(-1)),
        (Icons.arrow_forward, 'Move right', () => _move(1)),
        (Icons.volume_up, 'Clip volume', _clipVolume),
      ]);

  void _audioMenu() {
    final c = _clip;
    _menu('Audio', [
      (Icons.library_music, 'Add music', _addMusic),
      (Icons.graphic_eq, 'Sound effects', _sfxSheet),
      (Icons.mic, 'Voiceover', _voiceover),
      (Icons.audiotrack, 'Extract audio', _extractAudio),
      (Icons.record_voice_over, 'Text to speech', _ttsDialog),
      (Icons.volume_up, 'Clip volume', _clipVolume),
      (
        Icons.hearing,
        (c != null && c.aDenoise) ? 'Noise: ON' : 'Noise: OFF',
        () {
          final cl = _clip;
          if (cl == null) {
            _needClip();
            return;
          }
          _commit(() => cl.aDenoise = !cl.aDenoise);
          toast(context,
              cl.aDenoise ? 'Noise reduction on' : 'Noise reduction off');
        }
      ),
      (
        Icons.compress,
        s.duck ? 'Ducking: ON' : 'Ducking: OFF',
        () {
          _commit(() => s.duck = !s.duck);
          toast(
              context,
              s.duck
                  ? 'Music will get quieter when the video has sound'
                  : 'Ducking off');
        }
      ),
    ]);
  }

  void _effectsMenu() {
    final c = _clip;
    _menu('Effects', [
      (Icons.palette, 'Filters', _filters),
      (Icons.tune, 'Adjust', _adjust),
      (Icons.blur_on, 'Blur / Mosaic', _blurSheet),
      (Icons.swap_horiz, 'Transition', _transitionSheet),
      (
        Icons.vibration,
        (c != null && c.stab) ? 'Stabilize: ON' : 'Stabilize: OFF',
        () {
          final cl = _clip;
          if (cl == null || cl.isImage) {
            _needClip();
            return;
          }
          _commit(() => cl.stab = !cl.stab);
          toast(context, cl.stab ? 'Stabilize on (export)' : 'Stabilize off');
        }
      ),
      (
        Icons.grain,
        (c != null && c.denoise) ? 'Denoise: ON' : 'Denoise: OFF',
        () {
          final cl = _clip;
          if (cl == null) {
            _needClip();
            return;
          }
          _commit(() => cl.denoise = !cl.denoise);
          toast(context, cl.denoise ? 'Denoise on (export)' : 'Denoise off');
        }
      ),
      (Icons.auto_fix_high, 'Auto enhance', _autoEnhance),
    ]);
  }

  void _canvasMenu() => _menu('Canvas', [
        (Icons.aspect_ratio, 'Aspect ratio', _ratioSheet),
        (Icons.wallpaper, 'Background', _bgSheet),
      ]);

  void _aiMenu() => _menu('AI Tools', [
        (Icons.content_cut, 'Auto cut', _autoCut),
        (Icons.record_voice_over, 'Text to speech', _ttsDialog),
        (Icons.auto_fix_high, 'Auto enhance', _autoEnhance),
      ]);

  // ---------- core editing ----------
  Future<void> _addMedia() async {
    final media = await pickMedia(context);
    if (media.isEmpty) return;
    if (mounted) toast(context, 'Adding media...');
    final clips = await clipsFromPicked(media);
    if (clips.isEmpty || !mounted) return;
    final wasEmpty = s.clips.isEmpty;
    _commit(() {
      s.clips.addAll(clips);
      if (wasEmpty) sel = 0;
    }, reload: true);
  }

  void _trim() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Trim', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${fmtSec(c.start)} – ${fmtSec(c.end)}   (${(c.end - c.start).toStringAsFixed(1)}s)'),
          RangeSlider(
            values: RangeValues(c.start, c.end),
            min: 0,
            max: c.srcDur,
            activeColor: AppColors.accent,
            onChanged: (v) {
              if (v.end - v.start < 0.3) return;
              set(() {
                c.start = v.start;
                c.end = v.end;
              });
              _c?.seekTo(Duration(milliseconds: (v.start * 1000).round()));
            },
          ),
          if (c.isImage)
            const Text('Photos can be shown for up to 10 seconds.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    }, onClose: _loadSel);
  }

  void _split() {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    double at;
    if (clip.isImage) {
      at = (clip.start + clip.end) / 2;
    } else {
      final c = _c;
      at = c == null ? clip.start : c.value.position.inMilliseconds / 1000.0;
    }
    if (at <= clip.start + 0.2 || at >= clip.end - 0.2) {
      toast(context, 'Move the playhead into the middle of the clip to split');
      return;
    }
    _commit(() {
      final a = clip.copy();
      final b = clip.copy(newId: true);
      a.end = at;
      b.start = at;
      b.transition = clip.transition;
      a.transition = 'none';
      s.clips[sel] = a;
      s.clips.insert(sel + 1, b);
    }, reload: true);
  }

  void _delete() {
    if (_clip == null) {
      _needClip();
      return;
    }
    _commit(() {
      s.clips.removeAt(sel);
      if (sel >= s.clips.length) sel = s.clips.length - 1;
      if (sel < 0) sel = 0;
    }, reload: true);
  }

  void _duplicate() {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    _commit(() {
      s.clips.insert(sel + 1, clip.copy(newId: true));
      sel = sel + 1;
    }, reload: true);
  }

  void _move(int dir) {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    final ni = sel + dir;
    if (ni < 0 || ni >= s.clips.length) return;
    _commit(() {
      final c = s.clips.removeAt(sel);
      s.clips.insert(ni, c);
      sel = ni;
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

  void _speed() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    if (c.isImage) {
      toast(context, 'Speed works on video clips');
      return;
    }
    _sheet('Speed', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          choiceChips<double>([
            ('0.25x', 0.25),
            ('0.5x', 0.5),
            ('0.75x', 0.75),
            ('1x', 1.0),
            ('1.5x', 1.5),
            ('2x', 2.0),
            ('3x', 3.0),
            ('4x', 4.0),
          ], c.speed, (v) => set(() => c.speed = v)),
          const SizedBox(height: 6),
          const Text('Preview plays up to 2x. Export uses the exact speed.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reverse'),
            subtitle: const Text('Plays the clip backwards (export). Best for short clips.',
                style: TextStyle(fontSize: 12)),
            value: c.rev,
            onChanged: (v) => set(() => c.rev = v),
          ),
        ],
      );
    }, onClose: _loadSel);
  }

  void _clipVolume() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Clip volume', (set) {
      return _slider('Volume', c.volume, 0, 2, (v) {
        set(() => c.volume = v);
        _c?.setVolume(v.clamp(0.0, 1.0).toDouble());
      }, show: (v) => '${(v * 100).round()}%');
    });
  }

  void _crop() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Crop / Fit', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          choiceChips<String>([('Fit (show all)', 'fit'), ('Fill (crop)', 'fill')],
              c.fit, (v) => set(() => c.fit = v)),
          const SizedBox(height: 8),
          _slider('Zoom', c.zoom, 1, 3, (v) => set(() => c.zoom = v),
              show: (v) => '${v.toStringAsFixed(1)}x'),
          const Text('Zoom above 1x fills the frame and crops the edges.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    });
  }

  void _rotate() {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    _commit(() => clip.rot = (clip.rot + 90) % 360);
  }

  void _flip(bool horizontal) {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    _commit(() {
      if (horizontal) {
        clip.flipH = !clip.flipH;
      } else {
        clip.flipV = !clip.flipV;
      }
    });
  }

  double _srcPos(Clip clip) {
    final c = _c;
    if (clip.isImage || c == null) return clip.start;
    return c.value.position.inMilliseconds / 1000.0;
  }

  Future<void> _saveFrame() async {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    if (clip.isImage) {
      toast(context, 'Frames can be saved from video clips');
      return;
    }
    final out = newMediaPath('png');
    final ok = await runFF([
      '-y',
      '-ss',
      _srcPos(clip).toStringAsFixed(3),
      '-i',
      clip.path,
      '-frames:v',
      '1',
      out
    ]);
    if (!mounted) return;
    if (!ok) {
      toast(context, 'Could not save the frame');
      return;
    }
    try {
      await Gal.putImage(out, album: 'AR Forge');
      if (mounted) toast(context, 'Frame saved to your gallery');
    } catch (e) {
      if (mounted) toast(context, 'Could not save to gallery: $e');
    }
  }

  Future<void> _freeze() async {
    final clip = _clip;
    if (clip == null) {
      _needClip();
      return;
    }
    if (clip.isImage) {
      toast(context, 'Freeze frame works on video clips');
      return;
    }
    final at = _srcPos(clip);
    final out = newMediaPath('png');
    toast(context, 'Creating freeze frame...');
    final ok = await runFF(
        ['-y', '-ss', at.toStringAsFixed(3), '-i', clip.path, '-frames:v', '1', out]);
    if (!ok || !mounted) {
      if (mounted) toast(context, 'Could not create the frame');
      return;
    }
    final j = clip.toJson();
    j['path'] = out;
    j['isImage'] = true;
    j['srcDur'] = 10.0;
    j['hasAudio'] = false;
    j['start'] = 0.0;
    j['end'] = 2.0;
    j['speed'] = 1.0;
    j['rev'] = false;
    j['transition'] = 'none';
    final frame = Clip.fromJson(j, newId: true);
    _commit(() {
      if (at > clip.start + 0.2 && at < clip.end - 0.2) {
        final a = clip.copy();
        final b = clip.copy(newId: true);
        a.end = at;
        b.start = at;
        a.transition = 'none';
        s.clips[sel] = a;
        s.clips.insert(sel + 1, frame);
        s.clips.insert(sel + 2, b);
      } else if (at <= clip.start + 0.2) {
        s.clips.insert(sel, frame);
      } else {
        s.clips.insert(sel + 1, frame);
      }
    }, reload: true);
    toast(context, 'Freeze frame added (2 seconds)');
  }

  // ---------- effects ----------
  void _filters() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Filters', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          choiceChips<String>(
              filterDefs.map((f) => (f.name, f.id)).toList(), c.filter,
              (v) => set(() => c.filter = v)),
          const SizedBox(height: 10),
          _btn(Icons.done_all, 'Apply to all clips', () {
            set(() {
              for (final x in s.clips) {
                x.filter = c.filter;
              }
            });
          }),
        ],
      );
    });
  }

  void _adjust() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Adjust', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider('Brightness', c.bright, -0.5, 0.5, (v) => set(() => c.bright = v)),
          _slider('Contrast', c.contrast, 0.5, 1.5, (v) => set(() => c.contrast = v)),
          _slider('Saturation', c.sat, 0, 2, (v) => set(() => c.sat = v)),
          Wrap(spacing: 8, children: [
            _btn(Icons.restart_alt, 'Reset', () {
              set(() {
                c.bright = 0;
                c.contrast = 1;
                c.sat = 1;
              });
            }),
            _btn(Icons.done_all, 'Apply to all', () {
              set(() {
                for (final x in s.clips) {
                  x.bright = c.bright;
                  x.contrast = c.contrast;
                  x.sat = c.sat;
                }
              });
            }),
          ]),
        ],
      );
    });
  }

  void _blurSheet() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    _sheet('Blur / Mosaic', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider('Blur', c.blur, 0, 10, (v) => set(() => c.blur = v)),
          _slider('Mosaic', c.mosaic, 0, 40, (v) => set(() => c.mosaic = v),
              show: (v) => v < 1 ? 'off' : v.round().toString()),
          const Text('Mosaic is visible in the exported video.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    });
  }

  void _transitionSheet() {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    if (sel >= s.clips.length - 1) {
      toast(context, 'Select a clip that has another clip after it');
      return;
    }
    _sheet('Transition to next clip', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          choiceChips<String>(
              transitionIds.map((t) => (transitionName(t), t)).toList(),
              c.transition,
              (v) => set(() => c.transition = v)),
          const SizedBox(height: 10),
          _btn(Icons.done_all, 'Apply to all clips', () {
            set(() {
              for (var i = 0; i < s.clips.length - 1; i++) {
                s.clips[i].transition = c.transition;
              }
            });
          }),
          const SizedBox(height: 6),
          const Text('Transitions are visible in the exported video.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    });
  }

  void _autoEnhance() {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    _commit(() {
      for (final c in s.clips) {
        c.filter = 'enhance';
        c.denoise = true;
      }
    });
    toast(context, 'Auto enhance applied to all clips');
  }

  // ---------- canvas ----------
  void _ratioSheet() {
    _sheet('Aspect ratio', (set) {
      return choiceChips<String>(
          ratios.keys.map((k) => (k, k)).toList(), s.ratio, (v) => set(() => s.ratio = v));
    });
  }

  void _bgSheet() {
    _sheet('Background', (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          choiceChips<String>([('Color', 'color'), ('Blur', 'blur')], s.bgMode,
              (v) => set(() => s.bgMode = v)),
          const SizedBox(height: 12),
          const Text('Color', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: swatches
                .map((c) => GestureDetector(
                      onTap: () => set(() {
                        s.bgColor = c;
                        s.bgMode = 'color';
                      }),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: s.bgColor == c && s.bgMode == 'color'
                                  ? AppColors.accent
                                  : Colors.white24,
                              width: 2.5),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          const Text('The background shows around clips that do not fill the frame.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    });
  }

  // ---------- overlays: text, stickers, PIP ----------
  double _newEnd(double st) {
    final tot = _total();
    var e = st + 3;
    if (tot > st + 0.5 && e > tot) e = tot;
    return e;
  }

  Future<void> _addText({OverlayItem? edit}) async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final tc = TextEditingController(text: edit?.label ?? '');
    int color = edit?.color ?? 0xFFFFFFFF;
    double size = edit?.fontSize ?? 96;
    bool bg = edit?.bg ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.main,
          title: Text(edit == null ? 'Add text' : 'Edit text'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tc,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Type your text'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: swatches
                      .map((c) => GestureDetector(
                            onTap: () => set(() => color = c),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: color == c
                                        ? AppColors.accent
                                        : Colors.white24,
                                    width: 2.5),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                Slider(
                  value: size,
                  min: 40,
                  max: 200,
                  activeColor: AppColors.accent,
                  onChanged: (v) => set(() => size = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background box'),
                  value: bg,
                  onChanged: (v) => set(() => bg = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(edit == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );
    final text = tc.text.trim();
    if (ok != true || text.isEmpty) return;
    if (edit == null) {
      final st = _globalT;
      final o = await makeTextOverlay(text,
          color: color, fontSize: size, bg: bg, start: st, end: _newEnd(st));
      _commit(() {
        s.overlays.add(o);
        selOv = o.id;
      });
    } else {
      final r = await renderTextPng(text, color: color, fontSize: size, bg: bg);
      _commit(() {
        edit.path = r.$1;
        edit.preview = r.$1;
        edit.label = text;
        edit.color = color;
        edit.fontSize = size;
        edit.bg = bg;
        edit.scale = math.min(0.9, r.$2 / 1080.0);
      });
    }
  }

  void _stickerSheet() {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final list = emojiList.split(' ');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            children: list
                .map((e) => InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final r = await renderTextPng(e,
                            fontSize: 200, shadow: false, bold: false);
                        final st = _globalT;
                        final o = OverlayItem(
                          id: _newId(),
                          kind: 'sticker',
                          path: r.$1,
                          preview: r.$1,
                          label: e,
                          scale: 0.25,
                          start: st,
                          end: _newEnd(st),
                        );
                        _commit(() {
                          s.overlays.add(o);
                          selOv = o.id;
                        });
                      },
                      child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 28))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _addPip() async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final media = await pickMedia(context);
    if (media.isEmpty) return;
    if (mounted) toast(context, 'Adding overlay...');
    final added = <OverlayItem>[];
    for (final m in media) {
      if (m.isAudio) continue;
      final st = _globalT;
      if (m.isImage) {
        added.add(OverlayItem(
          id: _newId(),
          kind: 'image',
          path: m.path,
          preview: m.path,
          label: 'Photo',
          scale: 0.4,
          x: 0.72,
          y: 0.25,
          start: st,
          end: _newEnd(st),
        ));
      } else {
        final d = await mediaDuration(m.path);
        if (d <= 0) continue;
        final prev = newMediaPath('png');
        final ok =
            await runFF(['-y', '-ss', '0', '-i', m.path, '-frames:v', '1', prev]);
        added.add(OverlayItem(
          id: _newId(),
          kind: 'video',
          path: m.path,
          preview: ok ? prev : '',
          label: 'Video',
          scale: 0.4,
          x: 0.72,
          y: 0.25,
          start: st,
          end: st + d,
        ));
      }
    }
    if (added.isEmpty || !mounted) return;
    _commit(() {
      s.overlays.addAll(added);
      selOv = added.last.id;
    });
    toast(context, 'Drag it on the preview to move it, pinch to resize');
  }

  void _overlaySheet(OverlayItem o) {
    final total = math.max(_total(), 5.0);
    _sheet(
      o.kind == 'text'
          ? 'Text'
          : o.kind == 'sticker'
              ? 'Sticker'
              : o.kind == 'video'
                  ? 'Video overlay'
                  : 'Photo overlay',
      (set) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slider('Size', o.scale, 0.05, 1.5, (v) => set(() => o.scale = v)),
            _slider('Rotation', o.rot * 180 / math.pi, -180, 180,
                (v) => set(() => o.rot = v * math.pi / 180),
                show: (v) => '${v.round()}°'),
            _slider('Opacity', o.opacity, 0.1, 1, (v) => set(() => o.opacity = v),
                show: (v) => '${(v * 100).round()}%'),
            _slider('Starts at', o.start, 0, total, (v) {
              set(() {
                final len = o.end - o.start;
                o.start = v;
                o.end = v + len;
              });
            }, show: (v) => '${v.toStringAsFixed(1)}s'),
            _slider('Duration', o.end - o.start, 0.3, total,
                (v) => set(() => o.end = o.start + v),
                show: (v) => '${v.toStringAsFixed(1)}s'),
            if (o.kind == 'video')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Green screen (chroma key)'),
                subtitle: const Text('Removes green in the export',
                    style: TextStyle(fontSize: 12)),
                value: o.chroma,
                onChanged: (v) => set(() => o.chroma = v),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (o.kind == 'text')
                  _btn(Icons.edit, 'Edit text', () {
                    Navigator.pop(context);
                    _addText(edit: o);
                  }),
                _btn(Icons.flip_to_front, 'Bring forward', () {
                  final i = s.overlays.indexOf(o);
                  if (i < s.overlays.length - 1) {
                    set(() {
                      s.overlays.removeAt(i);
                      s.overlays.insert(i + 1, o);
                    });
                  }
                }),
                _btn(Icons.flip_to_back, 'Send backward', () {
                  final i = s.overlays.indexOf(o);
                  if (i > 0) {
                    set(() {
                      s.overlays.removeAt(i);
                      s.overlays.insert(i - 1, o);
                    });
                  }
                }),
                _btn(Icons.copy, 'Duplicate', () {
                  Navigator.pop(context);
                  _commit(() {
                    final n = o.copy(newId: true);
                    n.x = math.min(0.95, o.x + 0.05);
                    n.y = math.min(0.95, o.y + 0.05);
                    s.overlays.add(n);
                    selOv = n.id;
                  });
                }),
                _btn(Icons.delete_outline, 'Delete', () {
                  Navigator.pop(context);
                  _commit(() {
                    s.overlays.remove(o);
                    selOv = null;
                  });
                }),
              ],
            ),
          ],
        );
      },
    );
  }

  // ---------- audio ----------
  Future<void> _addMusic() async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final media = await pickMedia(context, kind: PickKind.audio, multi: false);
    if (media.isEmpty) return;
    final m = media.first;
    var d = await mediaDuration(m.path);
    if (d <= 0) d = m.dur;
    if (d <= 0 || !mounted) {
      if (mounted) toast(context, 'Could not read this audio file');
      return;
    }
    final a = AudioItem(
      id: _newId(),
      path: m.path,
      name: m.name,
      srcDur: d,
      trimStart: 0,
      trimEnd: d,
      start: _globalT,
    );
    _commit(() => s.audios.add(a));
    toast(context, 'Music added. Tap its bar in the timeline to edit.');
  }

  void _sfxSheet() {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Sound effects',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...sfxList.map((x) => ListTile(
                  leading: const Icon(Icons.graphic_eq, color: AppColors.accent),
                  title: Text(x.name),
                  onTap: () async {
                    Navigator.pop(ctx);
                    toast(context, 'Adding ${x.name}...');
                    final p = await sfxPath(x);
                    if (p == null || !mounted) return;
                    final d = await mediaDuration(p);
                    if (d <= 0 || !mounted) return;
                    final a = AudioItem(
                      id: _newId(),
                      path: p,
                      name: x.name,
                      srcDur: d,
                      trimStart: 0,
                      trimEnd: d,
                      start: _globalT,
                    );
                    _commit(() => s.audios.add(a));
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _extractAudio() async {
    final c = _clip;
    if (c == null) {
      _needClip();
      return;
    }
    if (c.isImage || !c.hasAudio) {
      toast(context, 'This clip has no audio');
      return;
    }
    final out = newMediaPath('m4a');
    toast(context, 'Extracting audio...');
    final ok = await runFF([
      '-y',
      '-ss',
      c.start.toStringAsFixed(3),
      '-t',
      (c.end - c.start).toStringAsFixed(3),
      '-i',
      c.path,
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      out
    ]);
    if (!ok || !mounted) {
      if (mounted) toast(context, 'Could not extract audio');
      return;
    }
    final d = await mediaDuration(out);
    if (d <= 0 || !mounted) return;
    final startAt = _starts()[sel];
    _commit(() {
      s.audios.add(AudioItem(
        id: _newId(),
        path: out,
        name: 'Extracted audio',
        srcDur: d,
        trimStart: 0,
        trimEnd: d,
        start: startAt,
      ));
      c.volume = 0;
    });
    toast(context, 'Audio extracted. The original clip is now muted.');
  }

  Future<void> _voiceover() async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        if (mounted) toast(context, 'Microphone permission is needed');
        return;
      }
      final path = newMediaPath('m4a');
      final startAt = _globalT;
      await rec.start(const RecordConfig(), path: path);
      _play();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.main,
          title: const Text('Recording...'),
          content: const Text('Speak now. The video plays while you record.'),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.main),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
      _pause();
      final out = await rec.stop();
      if (out != null) {
        final d = await mediaDuration(out);
        if (d > 0.2 && mounted) {
          _commit(() => s.audios.add(AudioItem(
                id: _newId(),
                path: out,
                name: 'Voiceover',
                srcDur: d,
                trimStart: 0,
                trimEnd: d,
                start: startAt,
              )));
          toast(context, 'Voiceover added');
        }
      }
    } finally {
      await rec.dispose();
    }
  }

  Future<void> _ttsDialog() async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    final tc = TextEditingController();
    String lang = 'en-US';
    double rate = 0.5;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.main,
          title: const Text('Text to Speech'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tc,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(hintText: 'Type what to say'),
                ),
                const SizedBox(height: 10),
                choiceChips<String>(
                    [('English', 'en-US'), ('Urdu', 'ur-PK'), ('Hindi', 'hi-IN')],
                    lang,
                    (v) => set(() => lang = v)),
                const SizedBox(height: 6),
                const Text('Speed', style: TextStyle(fontSize: 12)),
                Slider(
                  value: rate,
                  min: 0.2,
                  max: 0.9,
                  activeColor: AppColors.accent,
                  onChanged: (v) => set(() => rate = v),
                ),
                const Text('Voices come from your phone. Install the language in your phone settings if it is missing.',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    final text = tc.text.trim();
    if (go != true || text.isEmpty || !mounted) return;
    toast(context, 'Creating voice...');
    try {
      await _tts.setLanguage(lang);
      await _tts.setSpeechRate(rate);
      await _tts.awaitSynthCompletion(true);
      final out = '${mediaDir.path}/tts_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _tts.synthesizeToFile(text, out, true);
      final f = File(out);
      if (!await f.exists() || await f.length() < 1000) {
        if (mounted) {
          toast(context, 'Your phone could not create that voice. Try English.');
        }
        return;
      }
      final d = await mediaDuration(out);
      if (d <= 0 || !mounted) return;
      _commit(() => s.audios.add(AudioItem(
            id: _newId(),
            path: out,
            name: 'Speech',
            srcDur: d,
            trimStart: 0,
            trimEnd: d,
            start: _globalT,
          )));
      toast(context, 'Speech added to the timeline');
    } catch (e) {
      if (mounted) toast(context, 'Text to speech failed: $e');
    }
  }

  void _audioSheet(AudioItem a) {
    final total = math.max(_total(), 5.0);
    _sheet(a.name, (set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider('Volume', a.volume, 0, 2, (v) => set(() => a.volume = v),
              show: (v) => '${(v * 100).round()}%'),
          _slider('Fade in', a.fadeIn, 0, math.min(5.0, a.len / 2),
              (v) => set(() => a.fadeIn = v),
              show: (v) => '${v.toStringAsFixed(1)}s'),
          _slider('Fade out', a.fadeOut, 0, math.min(5.0, a.len / 2),
              (v) => set(() => a.fadeOut = v),
              show: (v) => '${v.toStringAsFixed(1)}s'),
          _slider('Starts at', a.start, 0, total, (v) => set(() => a.start = v),
              show: (v) => '${v.toStringAsFixed(1)}s'),
          const Text('Trim', style: TextStyle(fontSize: 12)),
          RangeSlider(
            values: RangeValues(a.trimStart, a.trimEnd),
            min: 0,
            max: a.srcDur,
            activeColor: AppColors.accent,
            onChanged: (v) {
              if (v.end - v.start < 0.3) return;
              set(() {
                a.trimStart = v.start;
                a.trimEnd = v.end;
              });
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce noise'),
            value: a.denoise,
            onChanged: (v) => set(() => a.denoise = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              _btn(Icons.call_split, 'Split at playhead', () {
                final g = _globalT;
                final rel = g - a.start;
                if (rel <= 0.2 || rel >= a.len - 0.2) {
                  toast(context, 'Move the playhead onto this audio bar first');
                  return;
                }
                Navigator.pop(context);
                _commit(() {
                  final b = a.copy(newId: true);
                  b.trimStart = a.trimStart + rel;
                  b.start = g;
                  a.trimEnd = a.trimStart + rel;
                  s.audios.add(b);
                });
              }),
              _btn(Icons.delete_outline, 'Delete', () {
                Navigator.pop(context);
                _commit(() => s.audios.remove(a));
              }),
            ],
          ),
        ],
      );
    });
  }

  // ---------- AI: auto cut ----------
  Future<void> _autoCut() async {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    toast(context, 'Looking for silent parts...');
    final out = <Clip>[];
    var removed = 0.0;
    for (final c in s.clips) {
      if (c.isImage || !c.hasAudio) {
        out.add(c);
        continue;
      }
      final dur = c.end - c.start;
      final session = await FFmpegKit.executeWithArguments([
        '-ss',
        c.start.toStringAsFixed(3),
        '-t',
        dur.toStringAsFixed(3),
        '-i',
        c.path,
        '-af',
        'silencedetect=noise=-32dB:d=0.5',
        '-f',
        'null',
        '-'
      ]);
      final logs = await session.getAllLogsAsString() ?? '';
      final starts = RegExp(r'silence_start: (-?[\d.]+)')
          .allMatches(logs)
          .map((m) => double.tryParse(m.group(1)!) ?? 0.0)
          .toList();
      final ends = RegExp(r'silence_end: (-?[\d.]+)')
          .allMatches(logs)
          .map((m) => double.tryParse(m.group(1)!) ?? dur)
          .toList();
      if (starts.isEmpty) {
        out.add(c);
        continue;
      }
      final keeps = <List<double>>[];
      var cursor = 0.0;
      for (var i = 0; i < starts.length; i++) {
        final ss = math.max(0.0, starts[i]);
        final se = i < ends.length ? ends[i] : dur;
        if (ss - cursor >= 0.3) keeps.add([cursor, ss]);
        cursor = se;
      }
      if (dur - cursor >= 0.3) keeps.add([cursor, dur]);
      if (keeps.isEmpty) {
        out.add(c);
        continue;
      }
      var kept = 0.0;
      for (final k in keeps) {
        final n = c.copy(newId: true);
        n.start = c.start + k[0];
        n.end = c.start + k[1];
        n.transition = 'none';
        kept += k[1] - k[0];
        out.add(n);
      }
      removed += (dur - kept);
    }
    if (!mounted) return;
    if (removed < 0.3) {
      toast(context, 'No long silent parts found');
      return;
    }
    _commit(() {
      s.clips = out;
      sel = 0;
    }, reload: true);
    toast(context, 'Removed ${removed.toStringAsFixed(1)}s of silence');
  }

  // ---------- project actions ----------
  Future<void> _saveTemplate() async {
    final tc = TextEditingController(text: proj.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.main,
        title: const Text('Save as template'),
        content: TextField(
            controller: tc,
            decoration: const InputDecoration(hintText: 'Template name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final f = s.clips.isNotEmpty ? s.clips.first : null;
    final texts = s.overlays
        .where((o) => o.kind == 'text')
        .map((o) => <String, dynamic>{
              't': o.label,
              'x': o.x,
              'y': o.y,
              's': o.start,
              'e': o.end,
              'f': o.fontSize,
              'c': o.color,
              'bg': o.bg,
            })
        .toList();
    final name = tc.text.trim().isEmpty ? 'My template' : tc.text.trim();
    final t = TemplateDef(
      name: name,
      desc: 'Saved from ${proj.name}',
      ratio: s.ratio,
      filter: f?.filter ?? 'none',
      transition: f?.transition ?? 'none',
      texts: texts,
      color: 0xFF2E7D32,
    );
    userTemplates.value = [...userTemplates.value, t];
    await saveTemplates();
    if (mounted) toast(context, 'Template saved');
  }

  Future<void> _rename() async {
    final tc = TextEditingController(text: proj.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.main,
        title: const Text('Rename project'),
        content: TextField(controller: tc, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && tc.text.trim().isNotEmpty) {
      setState(() => proj.name = tc.text.trim());
      _save();
    }
  }

  // ---------- export ----------
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

  Future<String> _wmPath() async {
    final p = '${mediaDir.path}/wm.png';
    if (!await File(p).exists()) {
      final data = await rootBundle.load('assets/logo.png');
      await File(p).writeAsBytes(data.buffer.asUint8List());
    }
    return p;
  }

  Future<(List<String>, double)> _buildArgs(
      String outPath, int w, int h, int fps, int crf, bool removeWm) async {
    final args = <String>['-y'];
    final fc = StringBuffer();
    final n = s.clips.length;
    var idx = 0;
    final total = _total();
    final bgBlur = s.bgMode == 'blur';
    final bgColor =
        '0x${(s.bgColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

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
      final own = !c.isImage && c.hasAudio;
      var ai = -1;
      if (!own) {
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

      final pre = <String>[];
      if (c.rev && !c.isImage) pre.add('reverse');
      if (c.stab && !c.isImage) pre.add('deshake');
      if (c.denoise) pre.add('hqdn3d=4:3:6:4.5');
      pre.add('setpts=(PTS-STARTPTS)/${c.speed.toStringAsFixed(4)}');
      if (c.rot == 90) pre.add('transpose=1');
      if (c.rot == 180) pre.addAll(['transpose=1', 'transpose=1']);
      if (c.rot == 270) pre.add('transpose=2');
      if (c.flipH) pre.add('hflip');
      if (c.flipV) pre.add('vflip');

      final post = <String>[];
      final fdef = filterById(c.filter);
      if (fdef.ff.isNotEmpty) post.add(fdef.ff);
      if (c.bright.abs() > 0.001 ||
          (c.contrast - 1).abs() > 0.001 ||
          (c.sat - 1).abs() > 0.001) {
        post.add(
            'eq=brightness=${c.bright.toStringAsFixed(3)}:contrast=${c.contrast.toStringAsFixed(3)}:saturation=${c.sat.toStringAsFixed(3)}');
      }
      if (c.blur > 0.5) post.add('boxblur=${(c.blur * 2).round()}:1');
      if (c.mosaic > 1) {
        final m = c.mosaic.round();
        post.add(
            'scale=${math.max(2, (w / m).round())}:${math.max(2, (h / m).round())},scale=$w:$h:flags=neighbor');
      }
      post.addAll(['setsar=1', 'fps=$fps', 'format=yuv420p']);

      final cover = c.fit == 'fill' || c.zoom > 1.001;
      if (cover) {
        final zw = (w * c.zoom).round();
        final zh = (h * c.zoom).round();
        fc.write(
            '[$vi:v]${pre.join(',')},scale=$zw:$zh:force_original_aspect_ratio=increase,crop=$w:$h,${post.join(',')}[v$i];');
      } else if (bgBlur) {
        fc.write(
            '[$vi:v]${pre.join(',')}[vp$i];[vp$i]split=2[vb$i][vf$i];[vb$i]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,boxblur=24:3[vbb$i];[vf$i]scale=$w:$h:force_original_aspect_ratio=decrease[vff$i];[vbb$i][vff$i]overlay=(W-w)/2:(H-h)/2[vo$i];[vo$i]${post.join(',')}[v$i];');
      } else {
        fc.write(
            '[$vi:v]${pre.join(',')},scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=$bgColor,${post.join(',')}[v$i];');
      }

      if (own) {
        final a = <String>[];
        if (c.rev) a.add('areverse');
        a.add('asetpts=PTS-STARTPTS');
        if (c.speed != 1.0) a.addAll(atempoChain(c.speed));
        if (c.aDenoise) a.add('afftdn=nf=-25');
        if ((c.volume - 1).abs() > 0.001) {
          a.add('volume=${c.volume.toStringAsFixed(3)}');
        }
        a.addAll([
          'aresample=44100',
          'aformat=sample_fmts=fltp:channel_layouts=stereo'
        ]);
        fc.write('[$vi:a]${a.join(',')}[a$i];');
      } else {
        fc.write(
            '[$ai:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a$i];');
      }
    }

    var vcur = '[v0]';
    var acur = '[a0]';
    if (n > 1) {
      var tot = s.clips[0].outDur;
      for (var i = 1; i < n; i++) {
        final prev = s.clips[i - 1];
        final d = _tr(i - 1);
        final tname = prev.transition == 'none' ? 'fade' : prev.transition;
        final off = math.max(0.0, tot - d);
        fc.write(
            '$vcur[v$i]xfade=transition=$tname:duration=${d.toStringAsFixed(3)}:offset=${off.toStringAsFixed(3)}[xv$i];');
        fc.write('$acur[a$i]acrossfade=d=${d.toStringAsFixed(3)}[xa$i];');
        vcur = '[xv$i]';
        acur = '[xa$i]';
        tot += s.clips[i].outDur - d;
      }
    }

    // overlays
    for (var k = 0; k < s.overlays.length; k++) {
      final o = s.overlays[k];
      final dur = math.max(0.1, o.end - o.start);
      final ii = idx;
      if (o.kind == 'video') {
        args.addAll([
          '-ss',
          o.srcStart.toStringAsFixed(3),
          '-t',
          dur.toStringAsFixed(3),
          '-i',
          o.path
        ]);
      } else {
        args.addAll(
            ['-loop', '1', '-t', (total + 0.5).toStringAsFixed(3), '-i', o.path]);
      }
      idx++;
      final ch = <String>[];
      if (o.kind == 'video') {
        ch.add('setpts=PTS-STARTPTS');
        if (o.chroma) ch.add('chromakey=0x00ff00:0.18:0.08');
      }
      ch.add('format=rgba');
      ch.add('scale=${math.max(2, (w * o.scale).round())}:-1');
      if (o.rot.abs() > 0.01) {
        final a = o.rot.toStringAsFixed(4);
        ch.add('rotate=$a:c=none:ow=rotw($a):oh=roth($a)');
      }
      if (o.opacity < 0.999) {
        ch.add('colorchannelmixer=aa=${o.opacity.toStringAsFixed(3)}');
      }
      if (o.kind == 'video') {
        ch.add('setpts=PTS+${o.start.toStringAsFixed(3)}/TB');
      }
      fc.write('[$ii:v]${ch.join(',')}[ov$k];');
      final st = o.start.toStringAsFixed(3);
      final en = o.end.toStringAsFixed(3);
      fc.write(
          "$vcur[ov$k]overlay=x=W*${o.x.toStringAsFixed(4)}-w/2:y=H*${o.y.toStringAsFixed(4)}-h/2:enable='between(t,$st,$en)':eof_action=pass[ox$k];");
      vcur = '[ox$k]';
    }

    if (!removeWm) {
      final wm = await _wmPath();
      args.addAll(['-i', wm]);
      final wi = idx;
      idx++;
      final mg = (w * 0.03).round();
      fc.write(
          '[$wi:v]scale=${(w * 0.14).round()}:-1,format=rgba,colorchannelmixer=aa=0.7[wm];$vcur[wm]overlay=x=W-w-$mg:y=H-h-$mg[vwm];');
      vcur = '[vwm]';
    }

    // audio: music tracks + ducking
    final mlabels = <String>[];
    for (var j = 0; j < s.audios.length; j++) {
      final a = s.audios[j];
      final len = a.len;
      args.addAll([
        '-ss',
        a.trimStart.toStringAsFixed(3),
        '-t',
        len.toStringAsFixed(3),
        '-i',
        a.path
      ]);
      final ii = idx;
      idx++;
      final ch = <String>[
        'aresample=44100',
        'aformat=sample_fmts=fltp:channel_layouts=stereo'
      ];
      if (a.denoise) ch.add('afftdn=nf=-25');
      if ((a.volume - 1).abs() > 0.001) {
        ch.add('volume=${a.volume.toStringAsFixed(3)}');
      }
      if (a.fadeIn > 0.05) {
        ch.add('afade=t=in:st=0:d=${a.fadeIn.toStringAsFixed(2)}');
      }
      if (a.fadeOut > 0.05) {
        ch.add(
            'afade=t=out:st=${math.max(0.0, len - a.fadeOut).toStringAsFixed(2)}:d=${a.fadeOut.toStringAsFixed(2)}');
      }
      final ms = (a.start * 1000).round();
      if (ms > 0) ch.add('adelay=$ms|$ms');
      fc.write('[$ii:a]${ch.join(',')}[m$j];');
      mlabels.add('[m$j]');
    }
    if (mlabels.isEmpty) {
      fc.write('${acur}anull[aout];');
    } else {
      var mus = mlabels.first;
      if (mlabels.length > 1) {
        fc.write(
            '${mlabels.join()}amix=inputs=${mlabels.length}:duration=longest:normalize=0[mus];');
        mus = '[mus]';
      }
      if (s.duck) {
        fc.write(
            '${acur}asplit=2[amain][asc];$mus[asc]sidechaincompress=threshold=0.04:ratio=8:attack=20:release=300[musd];[amain][musd]amix=inputs=2:duration=first:normalize=0[aout];');
      } else {
        fc.write('$acur${mus}amix=inputs=2:duration=first:normalize=0[aout];');
      }
    }

    var graph = fc.toString();
    if (graph.endsWith(';')) graph = graph.substring(0, graph.length - 1);

    args.addAll([
      '-filter_complex',
      graph,
      '-map',
      vcur,
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
      '160k',
      '-movflags',
      '+faststart',
      outPath,
    ]);
    return (args, total);
  }

  void _exportSheet() {
    if (s.clips.isEmpty) {
      _needClip();
      return;
    }
    int res = defRes;
    int fps = defFps;
    int crf = defCrf;
    String format = 'MP4';
    bool noWm = true;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.main,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, set) => Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  const Text('Format'),
                  const SizedBox(height: 6),
                  choiceChips<String>(
                      [('MP4', 'MP4'), ('MOV', 'MOV'), ('GIF', 'GIF')],
                      format,
                      (v) => set(() => format = v)),
                  const SizedBox(height: 14),
                  const Text('Resolution'),
                  const SizedBox(height: 6),
                  choiceChips<int>(
                      [('720p', 720), ('1080p', 1080), ('4K', 2160)], res,
                      (v) => set(() => res = v)),
                  const SizedBox(height: 14),
                  const Text('Frame rate'),
                  const SizedBox(height: 6),
                  choiceChips<int>([('24', 24), ('30', 30), ('60', 60)], fps,
                      (v) => set(() => fps = v)),
                  const SizedBox(height: 14),
                  const Text('Quality'),
                  const SizedBox(height: 6),
                  choiceChips<int>(
                      [('Low', 28), ('Medium', 23), ('High', 18)], crf,
                      (v) => set(() => crf = v)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remove watermark'),
                    value: noWm,
                    onChanged: (v) => set(() => noWm = v),
                  ),
                  const Text(
                      'GIF ignores resolution and frame rate (480p, 12 fps). 4K and 60 fps take a long time.',
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
                        _export(res, fps, crf, format, noWm);
                      },
                      child: const Text('Export Video'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _export(
      int res, int fps, int crf, String format, bool removeWm) async {
    if (s.clips.isEmpty) return;
    _pause();
    final isGif = format == 'GIF';
    final ext = format == 'MOV' ? 'mov' : 'mp4';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = '${Directory.systemTemp.path}/ARForge_$stamp.$ext';
    final wh = _size(isGif ? 480 : res);
    final built = await _buildArgs(
        out, wh.$1, wh.$2, isGif ? 12 : fps, isGif ? 30 : crf, removeWm);
    final totalMs = built.$2 * 1000;
    final prog = ValueNotifier<double>(0);
    final logs = <String>[];

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.main,
        title: const Text('Exporting...'),
        content: ValueListenableBuilder<double>(
          valueListenable: prog,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: v == 0 ? null : v, color: AppColors.accent),
              const SizedBox(height: 10),
              Text('${(v * 100).round()}%'),
              const SizedBox(height: 6),
              const Text('Keep the app open',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    final done = Completer<dynamic>();
    await FFmpegKit.executeWithArgumentsAsync(
      built.$1,
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
    var finalPath = out;
    var ok = ReturnCode.isSuccess(rc);

    if (ok && isGif) {
      final gif = '${Directory.systemTemp.path}/ARForge_$stamp.gif';
      ok = await runFF([
        '-y',
        '-i',
        out,
        '-filter_complex',
        'fps=12,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',
        gif
      ]);
      finalPath = gif;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (ok) {
      var saved = true;
      try {
        if (isGif) {
          await Gal.putImage(finalPath, album: 'AR Forge');
        } else {
          await Gal.putVideo(finalPath, album: 'AR Forge');
        }
      } catch (_) {
        saved = false;
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.main,
          title: Text(saved ? 'Saved to your gallery' : 'Export finished'),
          content: Text(saved
              ? 'Your ${isGif ? 'GIF' : 'video'} is in the AR Forge album.'
              : 'The file was created, but it could not be added to the gallery.'),
          actions: [
            TextButton(
              onPressed: () {
                SharePlus.instance.share(ShareParams(
                    files: [XFile(finalPath)], text: 'Made with AR Forge'));
              },
              child: const Text('Share'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
    } else {
      final tail = logs.join('\n');
      final shown = tail.length > 1200 ? tail.substring(tail.length - 1200) : tail;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.main,
          title: const Text('Export failed'),
          content: SingleChildScrollView(
            child: SelectableText(shown, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  // ---------- UI: preview ----------
  Widget? _raw(Clip clip, {required bool styled}) {
    Widget? w;
    if (clip.isImage) {
      w = Image.file(File(clip.path));
    } else if (_ready && _c != null) {
      final sz = _c!.value.size;
      w = SizedBox(width: sz.width, height: sz.height, child: VideoPlayer(_c!));
    }
    if (w == null) return null;
    w = RotatedBox(quarterTurns: clip.rot ~/ 90, child: w);
    w = Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
          clip.flipH ? -1.0 : 1.0, clip.flipV ? -1.0 : 1.0, 1.0),
      child: w,
    );
    if (styled) {
      w = ColorFiltered(
          colorFilter: ColorFilter.matrix(previewMatrix(clip)), child: w);
      if (clip.blur > 0.5) {
        w = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: clip.blur, sigmaY: clip.blur),
            child: w);
      }
    }
    return w;
  }

  Widget _fg(Clip clip) {
    final raw = _raw(clip, styled: true);
    if (raw == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    final cover = clip.fit == 'fill' || clip.zoom > 1.001;
    return ClipRect(
      child: Transform.scale(
        scale: cover ? clip.zoom : 1.0,
        child: SizedBox.expand(
          child: FittedBox(
            fit: cover ? BoxFit.cover : BoxFit.contain,
            child: raw,
          ),
        ),
      ),
    );
  }

  Widget _bgBlur(Clip clip) {
    final raw = _raw(clip, styled: false);
    if (raw == null) return const SizedBox();
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: SizedBox.expand(
          child: FittedBox(fit: BoxFit.cover, child: raw),
        ),
      ),
    );
  }

  Widget _overlayWidget(OverlayItem o, double cw, double ch) {
    final selected = selOv == o.id;
    final Widget img = o.preview.isEmpty
        ? const Icon(Icons.movie, size: 40, color: Colors.white70)
        : Image.file(File(o.preview), fit: BoxFit.contain);
    return Positioned(
      left: o.x * cw,
      top: o.y * ch,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () => setState(() => selOv = o.id),
          onDoubleTap: () => _overlaySheet(o),
          onScaleStart: (d) {
            _pushUndo();
            _gScale0 = o.scale;
            _gRot0 = o.rot;
            setState(() => selOv = o.id);
          },
          onScaleUpdate: (d) {
            setState(() {
              o.x = (o.x + d.focalPointDelta.dx / cw).clamp(0.0, 1.0).toDouble();
              o.y = (o.y + d.focalPointDelta.dy / ch).clamp(0.0, 1.0).toDouble();
              if (d.pointerCount > 1) {
                o.scale = (_gScale0 * d.scale).clamp(0.05, 2.0).toDouble();
                o.rot = _gRot0 + d.rotation;
              }
            });
          },
          onScaleEnd: (d) => _save(),
          child: Transform.rotate(
            angle: o.rot,
            child: Opacity(
              opacity: o.opacity.clamp(0.0, 1.0).toDouble(),
              child: Container(
                width: o.scale * cw,
                decoration: selected
                    ? BoxDecoration(
                        border: Border.all(color: AppColors.accent, width: 1.5))
                    : null,
                child: img,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas() {
    final clip = _clip;
    if (clip == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This project is empty',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.main),
                onPressed: _addMedia,
                child: const Text('Add media'),
              ),
            ],
          ),
        ),
      );
    }
    final r = ratios[s.ratio]!;
    return Center(
      child: AspectRatio(
        aspectRatio: r[0] / r[1],
        child: LayoutBuilder(builder: (ctx, cons) {
          final cw = cons.maxWidth;
          final ch = cons.maxHeight;
          final t = _globalT;
          return ClipRect(
            child: Container(
              color: Color(s.bgColor),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (s.bgMode == 'blur') _bgBlur(clip),
                  _fg(clip),
                  ...s.overlays
                      .where((o) => t >= o.start - 0.001 && t <= o.end + 0.001)
                      .map((o) => _overlayWidget(o, cw, ch)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _playbar() {
    final total = _total();
    final g = math.min(total, math.max(0.0, _globalT));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            iconSize: 34,
            color: AppColors.accent,
            icon: Icon(
                _playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
            onPressed: s.clips.isEmpty
                ? null
                : () {
                    if (_playing) {
                      _pause();
                    } else {
                      _play();
                    }
                  },
          ),
          Text(fmtSec(g), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: g,
              max: total > 0 ? total : 1,
              activeColor: AppColors.accent,
              onChanged: s.clips.isEmpty ? null : (v) => _seekGlobal(v),
            ),
          ),
          Text(fmtSec(total), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ---------- UI: timeline ----------
  Widget _timeline() {
    final total = _total();
    final contentW =
        math.max(MediaQuery.of(context).size.width, total * pps + 140);
    final rows = <Widget>[
      SizedBox(
        height: 60,
        child: s.clips.isEmpty
            ? const Center(
                child: Text('Timeline is empty',
                    style: TextStyle(color: Colors.white38)))
            : ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: s.clips.length,
                onReorder: _reorder,
                proxyDecorator: (child, i, a) =>
                    Material(color: Colors.transparent, child: child),
                itemBuilder: (ctx, i) {
                  final c = s.clips[i];
                  final w = math.max(52.0, c.outDur * pps);
                  final selected = i == sel;
                  return GestureDetector(
                    key: ValueKey(c.id),
                    onTap: () {
                      if (sel != i) {
                        sel = i;
                        selOv = null;
                        _loadSel();
                      }
                    },
                    child: Container(
                      width: w,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected ? AppColors.accent : Colors.white12,
                            width: selected ? 2.5 : 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(c.isImage ? Icons.image : Icons.videocam,
                                  size: 16, color: Colors.white70),
                              if (c.transition != 'none' && i < s.clips.length - 1)
                                const Icon(Icons.swap_horiz,
                                    size: 14, color: AppColors.accent),
                              if (c.filter != 'none')
                                const Icon(Icons.palette,
                                    size: 14, color: AppColors.accent),
                            ],
                          ),
                          Text(
                              '${c.outDur.toStringAsFixed(1)}s${c.speed != 1.0 ? ' ${c.speed}x' : ''}',
                              style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ];

    for (final o in s.overlays) {
      final icon = o.kind == 'text'
          ? Icons.text_fields
          : o.kind == 'sticker'
              ? Icons.emoji_emotions
              : Icons.picture_in_picture;
      rows.add(SizedBox(
        height: 28,
        child: Stack(
          children: [
            Positioned(
              left: o.start * pps,
              top: 2,
              bottom: 2,
              width: math.max(40.0, (o.end - o.start) * pps),
              child: GestureDetector(
                onTap: () {
                  setState(() => selOv = o.id);
                  _overlaySheet(o);
                },
                onHorizontalDragStart: (_) => _pushUndo(),
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    final len = o.end - o.start;
                    o.start = math.max(0.0, o.start + d.delta.dx / pps);
                    o.end = o.start + len;
                  });
                },
                onHorizontalDragEnd: (_) => _save(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E5C3D),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: selOv == o.id ? AppColors.accent : Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                            o.kind == 'text' || o.kind == 'sticker'
                                ? o.label
                                : o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    }

    for (final a in s.audios) {
      rows.add(SizedBox(
        height: 28,
        child: Stack(
          children: [
            Positioned(
              left: a.start * pps,
              top: 2,
              bottom: 2,
              width: math.max(40.0, a.len * pps),
              child: GestureDetector(
                onTap: () => _audioSheet(a),
                onHorizontalDragStart: (_) => _pushUndo(),
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    a.start = math.max(0.0, a.start + d.delta.dx / pps);
                  });
                },
                onHorizontalDragEnd: (_) => _save(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A5B2A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return Container(
      height: 170,
      color: AppColors.dark,
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentW,
              child: SingleChildScrollView(
                child: Stack(
                  children: [
                    Column(children: rows),
                    Positioned(
                      left: _globalT * pps,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.zoom_out, size: 20),
                  onPressed: () =>
                      setState(() => pps = math.max(12.0, pps - 8)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.zoom_in, size: 20),
                  onPressed: () =>
                      setState(() => pps = math.min(120.0, pps + 8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.content_cut, 'Edit', _editMenu),
      (Icons.music_note, 'Audio', _audioMenu),
      (Icons.text_fields, 'Text', () => _addText()),
      (Icons.emoji_emotions, 'Sticker', _stickerSheet),
      (Icons.picture_in_picture, 'PIP', _addPip),
      (Icons.auto_awesome, 'Effects', _effectsMenu),
      (Icons.aspect_ratio, 'Canvas', _canvasMenu),
      (Icons.smart_toy, 'AI', _aiMenu),
    ];
    return Container(
      height: 66,
      color: AppColors.main,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: items
            .map((t) => InkWell(
                  onTap: t.$3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1, color: Colors.white),
                        const SizedBox(height: 3),
                        Text(t.$2, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ))
            .toList(),
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
                  child: Text(proj.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: _undo.isEmpty ? null : _doUndo),
                IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: _redo.isEmpty ? null : _doRedo),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'save') {
                      _save();
                      toast(context, 'Draft saved');
                    } else if (v == 'template') {
                      _saveTemplate();
                    } else if (v == 'rename') {
                      _rename();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'save', child: Text('Save draft')),
                    PopupMenuItem(
                        value: 'template', child: Text('Save as template')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10, left: 2),
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
            _bottomBar(),
          ],
        ),
      ),
    );
  }
}

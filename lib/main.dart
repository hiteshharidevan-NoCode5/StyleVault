import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StyleTApp());
}

class StyleTApp extends StatelessWidget {
  const StyleTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StyleT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101318),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5EEAD4),
          brightness: Brightness.dark,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, height: 1.45),
          bodyMedium: TextStyle(fontSize: 16, height: 1.4),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class WardrobeItem {
  final String id;
  final String imagePath;
  final String category;
  final String silhouette;
  final int r;
  final int g;
  final int b;
  final String colorName;
  final String note;

  WardrobeItem({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.silhouette,
    required this.r,
    required this.g,
    required this.b,
    required this.colorName,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'category': category,
        'silhouette': silhouette,
        'r': r,
        'g': g,
        'b': b,
        'colorName': colorName,
        'note': note,
      };

  factory WardrobeItem.fromJson(Map<String, dynamic> json) => WardrobeItem(
        id: json['id'],
        imagePath: json['imagePath'],
        category: json['category'],
        silhouette: json['silhouette'],
        r: json['r'],
        g: json['g'],
        b: json['b'],
        colorName: json['colorName'],
        note: json['note'] ?? '',
      );
}

class ColorAnalyzer {
  static Map<String, dynamic> extractDominantColor(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return {'r': 120, 'g': 130, 'b': 140, 'name': 'Neutral Slate'};
    }
    final resized = img.copyResize(decoded, width: 64);
    int rSum = 0, gSum = 0, bSum = 0, count = 0;

    final startX = (resized.width * 0.25).round();
    final endX = (resized.width * 0.75).round();
    final startY = (resized.height * 0.25).round();
    final endY = (resized.height * 0.75).round();

    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        final pixel = resized.getPixel(x, y);
        rSum += pixel.r.toInt();
        gSum += pixel.g.toInt();
        bSum += pixel.b.toInt();
        count++;
      }
    }

    final r = (rSum / max(1, count)).round();
    final g = (gSum / max(1, count)).round();
    final b = (bSum / max(1, count)).round();
    return {'r': r, 'g': g, 'b': b, 'name': classifyColor(r, g, b)};
  }

  static String classifyColor(int r, int g, int b) {
    final brightness = (r + g + b) / 3;
    final maxVal = max(r, max(g, b));
    final minVal = min(r, min(g, b));
    final saturation = maxVal == 0 ? 0.0 : (maxVal - minVal) / maxVal;

    if (brightness < 55) return 'Charcoal / Deep Black';
    if (brightness > 215 && saturation < 0.2) return 'Crisp Ivory / White';
    if (saturation < 0.18) return 'Classic Neutral Grey';
    if (r > g + 35 && r > b + 35) {
      return brightness > 150 ? 'Warm Coral / Terracotta' : 'Rich Maroon / Crimson';
    }
    if (b > r + 25 && b > g + 15) {
      return brightness < 110 ? 'Deep Navy' : 'Serene Sky Blue';
    }
    if (g > r + 15 && g > b + 15) {
      return brightness < 115 ? 'Forest / Olive Green' : 'Fresh Sage';
    }
    if (r > 160 && g > 130 && b < 110) return 'Warm Earth / Mustard';
    return 'Balanced Earth Tone';
  }

  static double colorHarmonyScore(WardrobeItem a, int r2, int g2, int b2) {
    final neutralA = (max(a.r, max(a.g, a.b)) - min(a.r, min(a.g, a.b))) < 40;
    final neutralB = (max(r2, max(g2, b2)) - min(r2, min(g2, b2))) < 40;
    if (neutralA || neutralB) return 0.92;

    final dist = sqrt(pow(a.r - r2, 2) + pow(a.g - g2, 2) + pow(a.b - b2, 2));
    if (dist < 75) return 0.85;
    if (dist > 170) return 0.88;
    return 0.72;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  List<WardrobeItem> _wardrobe = [];
  String _styleGoal = 'Balanced & Elongated Silhouette';
  String _currentVersion = '...';
  String? _latestTag;
  String? _apkDownloadUrl;
  bool _isDownloading = false;

  final List<String> _goalOptions = [
    'Balanced & Elongated Silhouette',
    'Broaden & Define Shoulders',
    'Streamline & Soften Midsection',
    'Smart Effortless Everyday',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkGitHubUpdate();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('wardrobe_items') ?? [];
    final goal = prefs.getString('style_goal') ?? _goalOptions.first;
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _wardrobe = raw.map((e) => WardrobeItem.fromJson(jsonDecode(e))).toList();
      _styleGoal = goal;
      _currentVersion = 'v${info.version}';
    });
  }

  Future<void> _saveWardrobe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'wardrobe_items',
      _wardrobe.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _saveGoal(String goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('style_goal', goal);
    setState(() => _styleGoal = goal);
  }

  Future<void> _checkGitHubUpdate() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/hiteshharidevan-NoCode5/StyleT/releases/latest'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tag = data['tag_name'] as String?;
        final assets = (data['assets'] as List?) ?? [];
        String? apkUrl;
        for (final asset in assets) {
          final name = (asset['name'] ?? '').toString();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'];
            break;
          }
        }
        if (tag != null && tag != _currentVersion && apkUrl != null) {
          setState(() {
            _latestTag = tag;
            _apkDownloadUrl = apkUrl;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _downloadAndInstallUpdate() async {
    if (_apkDownloadUrl == null) return;
    setState(() => _isDownloading = true);
    try {
      final res = await http.get(Uri.parse(_apkDownloadUrl!));
      final dir = await getTemporaryDirectory();
      final apkFile = File('${dir.path}/StyleT-$_latestTag.apk');
      await apkFile.writeAsBytes(res.bodyBytes);
      setState(() => _isDownloading = false);
      await OpenFilex.open(apkFile.path);
    } catch (e) {
      setState(() => _isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download update: $e')),
        );
      }
    }
  }

  Future<void> _addOutfitPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'outfit_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await File(picked.path).copy('${appDir.path}/$fileName');
    final colorData = ColorAnalyzer.extractDominantColor(savedFile);

    String category = 'Full Outfit';
    String silhouette = 'Tailored & Clean';
    final noteCtrl = TextEditingController();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add to Your Private Wardrobe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Detected Tone: ${colorData['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                const Text('Garment Type'),
                DropdownButton<String>(
                  value: category,
                  isExpanded: true,
                  items: ['Full Outfit', 'Top / Kurta / Shirt', 'Bottom / Trousers', 'Layer / Jacket']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
                const SizedBox(height: 12),
                const Text('Cut & Drape'),
                DropdownButton<String>(
                  value: silhouette,
                  isExpanded: true,
                  items: [
                    'Tailored & Clean',
                    'Vertical / Elongating',
                    'Structured Shoulders',
                    'Relaxed & Flowing'
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => silhouette = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Personal note (optional)',
                    hintText: 'e.g., Festive cotton kurta, office blazer',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _wardrobe.insert(
                    0,
                    WardrobeItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      imagePath: savedFile.path,
                      category: category,
                      silhouette: silhouette,
                      r: colorData['r'],
                      g: colorData['g'],
                      b: colorData['b'],
                      colorName: colorData['name'],
                      note: noteCtrl.text.trim(),
                    ),
                  );
                });
                _saveWardrobe();
                Navigator.pop(ctx);
              },
              child: const Text('Save Locally'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildWardrobeTab(),
      ShoppingCheckTab(wardrobe: _wardrobe, styleGoal: _styleGoal),
      _buildStylistProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('StyleT'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(_currentVersion, style: const TextStyle(color: Colors.white60)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_latestTag != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF1E3A3A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Update $_latestTag is ready on GitHub.'),
                  ),
                  _isDownloading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton(
                          onPressed: _downloadAndInstallUpdate,
                          child: const Text('Update'),
                        ),
                ],
              ),
            ),
          Expanded(child: pages[_tabIndex]),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addOutfitPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Outfit'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checkroom), label: 'My Wardrobe'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Shop Match'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'My Style'),
        ],
      ),
    );
  }

  Widget _buildWardrobeTab() {
    if (_wardrobe.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 54, color: Color(0xFF5EEAD4)),
              const SizedBox(height: 16),
              Text('Your Private Wardrobe', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              const Text(
                'Add photos of outfits you already own and feel great in. Everything stays 100% offline on your device—never uploaded anywhere.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _wardrobe.length,
      itemBuilder: (context, index) {
        final item = _wardrobe[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          color: const Color(0xFF181D26),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(item.imagePath),
                    width: 84,
                    height: 104,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 84,
                      height: 104,
                      child: Icon(Icons.image_not_supported),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.category,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${item.colorName} • ${item.silhouette}',
                          style: const TextStyle(color: Color(0xFF5EEAD4))),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.note, style: const TextStyle(color: Colors.white70)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () {
                    setState(() => _wardrobe.removeAt(index));
                    _saveWardrobe();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStylistProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Your Styling Focus', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'StyleT highlights your natural strengths and balances proportions so you look sharp and feel confident in every outfit.',
        ),
        const SizedBox(height: 16),
        ..._goalOptions.map(
          (goal) => RadioListTile<String>(
            value: goal,
            groupValue: _styleGoal,
            title: Text(goal),
            onChanged: (v) => _saveGoal(v!),
          ),
        ),
        const Divider(height: 32),
        const Text(
          'Privacy Guarantee: All photo color analysis, wardrobe matching, and styling rules run locally on your device. Adults only (18+).',
          style: TextStyle(color: Colors.white60),
        ),
      ],
    );
  }
}

class ShoppingCheckTab extends StatefulWidget {
  final List<WardrobeItem> wardrobe;
  final String styleGoal;

  const ShoppingCheckTab({super.key, required this.wardrobe, required this.styleGoal});

  @override
  State<ShoppingCheckTab> createState() => _ShoppingCheckTabState();
}

class _ShoppingCheckTabState extends State<ShoppingCheckTab> {
  File? _candidateImage;
  String? _adviceTitle;
  String? _adviceBody;
  String _selectedCut = 'Vertical / Elongating';

  Future<void> _analyzeStorePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked == null) return;

    final file = File(picked.path);
    final color = ColorAnalyzer.extractDominantColor(file);
    final int r = color['r'], g = color['g'], b = color['b'];
    final String colorName = color['name'];

    WardrobeItem? bestMatch;
    double bestScore = 0;
    for (final item in widget.wardrobe) {
      final score = ColorAnalyzer.colorHarmonyScore(item, r, g, b);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = item;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('This piece brings a lovely $colorName tone to your look.');

    if (bestMatch != null && bestScore >= 0.8) {
      final desc = bestMatch.note.isNotEmpty ? bestMatch.note : bestMatch.category.toLowerCase();
      buffer.writeln(
        '\nWardrobe Pairing: It harmonizes wonderfully with your existing ${bestMatch.colorName} $desc, giving you an effortless, put-together combination right away.',
      );
    } else if (widget.wardrobe.isNotEmpty) {
      buffer.writeln(
        '\nWardrobe Pairing: Because this shade is a fresh departure from your current pieces, pairing it with a classic neutral bottom or layer you already own will keep the outfit balanced and refined.',
      );
    } else {
      buffer.writeln(
        '\nTip: Add 2–3 of your favourite outfits in the "My Wardrobe" tab so I can check how well this pairs with what you already own.',
      );
    }

    buffer.writeln('\nSilhouette & Confidence Note (${widget.styleGoal}):');
    if (_selectedCut == 'Vertical / Elongating' || _selectedCut == 'Tailored & Clean') {
      buffer.writeln(
        'Its clean lines draw the eye smoothly from top to bottom, creating a poised, well-proportioned silhouette that flatters effortlessly.',
      );
    } else if (_selectedCut == 'Structured Shoulders') {
      buffer.writeln(
        'The defined shoulder line adds crisp presence and frames your posture beautifully—especially when paired with a clean, tapered lower half.',
      );
    } else {
      buffer.writeln(
        'This relaxed drape offers wonderful ease and comfort. For an extra sharp finish, try a gentle half-tuck or pair it with structured trousers so the silhouette stays tailored.',
      );
    }

    setState(() {
      _candidateImage = file;
      _adviceTitle = bestScore >= 0.85
          ? 'A Strong Match for Your Wardrobe'
          : 'Thoughtful Styling Potential';
      _adviceBody = buffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Check Before You Buy', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Upload a photo of a garment on a hanger, mannequin, or online store to see how well it complements you and your existing wardrobe.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedCut,
          decoration: const InputDecoration(
            labelText: 'Garment Cut / Drape You Are Considering',
            border: OutlineInputBorder(),
          ),
          items: [
            'Vertical / Elongating',
            'Tailored & Clean',
            'Structured Shoulders',
            'Relaxed & Flowing',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _selectedCut = v!),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _analyzeStorePhoto,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Select Hanger or Store Photo'),
        ),
        if (_candidateImage != null && _adviceBody != null) ...[
          const SizedBox(height: 20),
          Card(
            color: const Color(0xFF181D26),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_candidateImage!, height: 220, width: double.infinity, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 14),
                  Text(_adviceTitle!,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5EEAD4))),
                  const SizedBox(height: 8),
                  Text(_adviceBody!),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

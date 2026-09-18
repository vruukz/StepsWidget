import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'history_screen.dart';

const appGroupId = 'com.example.steps_widget';
const widgetName = 'StepsWidget';
const defaultGoal = 10000;
const defaultAccent = Color(0xFF4ADE80);

// Rough estimates (no user height/weight input) — average adult stride and
// energy cost per step. Good enough for a ballpark, not a fitness tracker.
const strideMeters = 0.78;
const kcalPerStep = 0.04;

double stepsToKm(int steps) => steps * strideMeters / 1000;
double stepsToKcal(int steps) => steps * kcalPerStep;

Future<void> backgroundCallback(Uri? uri) async {
  // Called when widget is tapped — open app
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StepsApp());
}

class StepsApp extends StatefulWidget {
  const StepsApp({super.key});

  @override
  State<StepsApp> createState() => _StepsAppState();
}

class _StepsAppState extends State<StepsApp> {
  Color _accent = defaultAccent;

  @override
  void initState() {
    super.initState();
    _loadAccent();
  }

  Future<void> _loadAccent() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('accent_color');
    if (value != null) {
      setState(() => _accent = Color(value));
    }
  }

  Future<void> _setAccent(Color color) async {
    setState(() => _accent = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.value);
    const platform = MethodChannel('com.example.steps_widget/widget');
    try {
      await platform.invokeMethod('updateWidget');
    } catch (e) {
      debugPrint('Widget update: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Steps',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          primary: _accent,
          surface: const Color(0xFF111111),
        ),
      ),
      home: HomeScreen(accent: _accent, onAccentChanged: _setAccent),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Color accent;
  final ValueChanged<Color> onAccentChanged;

  const HomeScreen({
    super.key,
    required this.accent,
    required this.onAccentChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const _historyKey = 'steps_history';

class _HomeScreenState extends State<HomeScreen> {
  int _steps = 0;
  int _goal = defaultGoal;
  int _baseSteps = 0; // steps at midnight (reset baseline)
  Map<String, int> _history = {};
  StreamSubscription<StepCount>? _subscription;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _requestPermission();
    await _loadGoal();
    await _loadHistory();
    await _loadBaseline();
    // Pick up whatever the native background service tracked while the
    // app wasn't open, instead of sitting at 0 until the next step event.
    final prefs = await SharedPreferences.getInstance();
    final savedSteps = prefs.getInt('steps') ?? 0;
    if (savedSteps > 0) {
      setState(() => _steps = savedSteps);
      await _recordHistory(savedSteps);
    }
    _startPedometer();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _history = decoded.map((k, v) => MapEntry(k, v as int));
    });
  }

  Future<void> _recordHistory(int steps) async {
    final today = _todayString();
    if (_history[today] == steps) return;
    setState(() => _history = {..._history, today: steps});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(_history));
  }

  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _goal = prefs.getInt('goal') ?? defaultGoal);
  }

  Future<void> _setGoal(int newGoal) async {
    setState(() => _goal = newGoal);
    await _updateWidget(_steps);
  }

  void _openGoalEditor() {
    final controller = TextEditingController(text: _goal.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Daily goal', style: TextStyle(color: Color(0xFFF0F0F0))),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Color(0xFFF0F0F0)),
          decoration: const InputDecoration(
            hintText: 'Steps',
            hintStyle: TextStyle(color: Color(0xFF555555)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0) {
                _setGoal(value);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermission() async {
    await Permission.activityRecognition.request();
    // Needed on Android 13+ for the "tracking your steps" foreground
    // service notification to actually show up.
    await Permission.notification.request();
  }

  Future<void> _loadBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('step_date') ?? '';
    final today = _todayString();
    if (savedDate != today) {
      // New day — reset baseline on next step event
      await prefs.setString('step_date', today);
      await prefs.setInt('step_baseline', -1); // -1 = not set yet
    }
    _baseSteps = prefs.getInt('step_baseline') ?? -1;
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  void _startPedometer() {
    _subscription = Pedometer.stepCountStream.listen(
      (event) async {
        final prefs = await SharedPreferences.getInstance();

        // Set baseline on first event of the day
        if (_baseSteps == -1) {
          _baseSteps = event.steps;
          await prefs.setInt('step_baseline', _baseSteps);
        }

        final todaySteps = (event.steps - _baseSteps).clamp(0, 999999);

        setState(() {
          _steps = todaySteps;
          _status = 'Active';
        });

        await _updateWidget(todaySteps);
        await _recordHistory(todaySteps);
      },
      onError: (e) {
        setState(() => _status = 'Sensor unavailable');
      },
    );
  }

  Future<void> _updateWidget(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps', steps);
    await prefs.setInt('goal', _goal);
    await prefs.setString('label',
        steps >= _goal ? 'GOAL REACHED ✓' : '$steps / $_goal');

    // Trigger widget update via broadcast
    const platform = MethodChannel('com.example.steps_widget/widget');
    try {
      await platform.invokeMethod('updateWidget');
    } catch (e) {
      debugPrint('Widget update: $e');
    }
  }

  void _openAccentPicker() {
    Color pending = widget.accent;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Accent color', style: TextStyle(color: Color(0xFFF0F0F0))),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pending,
            onColorChanged: (color) => pending = color,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.onAccentChanged(pending);
              Navigator.of(context).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final progress = (_steps / _goal).clamp(0.0, 1.0);
    final pct = (progress * 100).toStringAsFixed(0);
    final km = stepsToKm(_steps);
    final kcal = stepsToKcal(_steps);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: accent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('SW',
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 2)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('StepWidget',
                        style: TextStyle(
                            color: Color(0xFFF0F0F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 18)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoryScreen(accent: accent),
                      ),
                    ),
                    icon: const Icon(Icons.bar_chart_rounded, color: Color(0xFF555555)),
                    tooltip: 'History',
                  ),
                  IconButton(
                    onPressed: _openAccentPicker,
                    icon: const Icon(Icons.palette_outlined, color: Color(0xFF555555)),
                    tooltip: 'Accent color',
                  ),
                ],
              ),
              const SizedBox(height: 48),

              // Step count
              Text(
                '$_steps',
                style: TextStyle(
                  color: accent,
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -3,
                ),
              ),
              const Text(
                'STEPS TODAY',
                style: TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // Distance / calories
              Row(
                children: [
                  Text('${km.toStringAsFixed(2)} km',
                      style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                  Text('${kcal.toStringAsFixed(0)} kcal',
                      style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 32),

              // Progress bar
              GestureDetector(
                onTap: _openGoalEditor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('GOAL',
                            style: TextStyle(
                                color: Color(0xFF555555),
                                fontSize: 10,
                                letterSpacing: 2)),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined, color: const Color(0xFF444444), size: 11),
                      ],
                    ),
                    Text('$pct%',
                        style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFF2A2A2A),
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_steps / $_goal steps',
                style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
              ),

              const Spacer(),

              // Status
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _status == 'Active' ? accent : const Color(0xFF555555),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status.toUpperCase(),
                    style: const TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 10,
                        letterSpacing: 2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Widget updates automatically as you walk.',
                style: TextStyle(color: Color(0xFF333333), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

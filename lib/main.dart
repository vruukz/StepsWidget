import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

const appGroupId = 'com.example.steps_widget';
const widgetName = 'StepsWidget';
const goalSteps = 10000;
const defaultAccent = Color(0xFF4ADE80);

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

class _HomeScreenState extends State<HomeScreen> {
  int _steps = 0;
  int _baseSteps = 0; // steps at midnight (reset baseline)
  StreamSubscription<StepCount>? _subscription;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _requestPermission();
    await _loadBaseline();
    _startPedometer();
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
      },
      onError: (e) {
        setState(() => _status = 'Sensor unavailable');
      },
    );
  }

  Future<void> _updateWidget(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps', steps);
    await prefs.setInt('goal', goalSteps);
    await prefs.setString('label',
        steps >= goalSteps ? 'GOAL REACHED ✓' : '$steps / $goalSteps');

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
    final progress = (_steps / goalSteps).clamp(0.0, 1.0);
    final pct = (progress * 100).toStringAsFixed(0);

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
                    onPressed: _openAccentPicker,
                    icon: const Icon(Icons.palette_outlined, color: Color(0xFF555555)),
                    tooltip: 'Accent color',
                  ),
                ],
              ),
              const SizedBox(height: 60),

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
              const SizedBox(height: 40),

              // Progress bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('GOAL',
                      style: TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 10,
                          letterSpacing: 2)),
                  Text('$pct%',
                      style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ],
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
                '$_steps / $goalSteps steps',
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

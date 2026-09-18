import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show stepsToKm, stepsToKcal;

const _historyKey = 'steps_history';

class HistoryScreen extends StatefulWidget {
  final Color accent;
  const HistoryScreen({super.key, required this.accent});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<MapEntry<String, int>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    final Map<String, dynamic> decoded =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    final entries = decoded.entries
        .map((e) => MapEntry(e.key, e.value as int))
        .toList()
      ..sort((a, b) => _parseDate(b.key).compareTo(_parseDate(a.key)));
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  DateTime _parseDate(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  String _formatDate(String key) {
    final date = _parseDate(key);
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    if (isToday) return 'Today';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF555555)),
                  ),
                  const SizedBox(width: 4),
                  const Text('HISTORY',
                      style: TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const SizedBox()
                    : _entries.isEmpty
                        ? Center(
                            child: Text('No history yet',
                                style: const TextStyle(
                                    color: Color(0xFF555555), fontSize: 13)),
                          )
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Color(0xFF1A1A1A), height: 1),
                            itemBuilder: (context, i) {
                              final entry = _entries[i];
                              final steps = entry.value;
                              final km = stepsToKm(steps);
                              final kcal = stepsToKcal(steps);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_formatDate(entry.key),
                                            style: const TextStyle(
                                                color: Color(0xFFE8E2D9),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${km.toStringAsFixed(2)} km · ${kcal.toStringAsFixed(0)} kcal',
                                            style: const TextStyle(
                                                color: Color(0xFF555555),
                                                fontSize: 11)),
                                      ],
                                    ),
                                    Text('$steps',
                                        style: TextStyle(
                                            color: accent,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            fontFamily: 'monospace')),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChromaService extends ChangeNotifier with WidgetsBindingObserver {
  static const _kHueKey = 'chroma_hue';
  static const _kTimestampKey = 'chroma_ts';

  static const double _cycleDurationMs = 24 * 60 * 60 * 1000.0;

  double _hue = 240.0;
  Timer? _timer;
  int _lastSavedMs = 0;

  ChromaService() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  double get hue => _hue;

  Color get primary => HSLColor.fromAHSL(1.0, _hue, 0.85, 0.58).toColor();

  Color get primaryLight => HSLColor.fromAHSL(1.0, _hue, 0.80, 0.72).toColor();

  Color get primaryDark => HSLColor.fromAHSL(0.22, _hue, 0.85, 0.58).toColor();

  Color get accent =>
      HSLColor.fromAHSL(1.0, (_hue + 120) % 360, 0.90, 0.60).toColor();

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, accent],
      );

  LinearGradient get spectrumGradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: List.generate(
          6,
          (i) => HSLColor.fromAHSL(1.0, (_hue + i * 30) % 360, 0.85, 0.62)
              .toColor(),
        ),
      );

  LinearGradient get buttonGradient => LinearGradient(
        colors: [
          HSLColor.fromAHSL(1.0, _hue, 0.88, 0.55).toColor(),
          HSLColor.fromAHSL(1.0, (_hue + 40) % 360, 0.85, 0.60).toColor(),
        ],
      );

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHue = prefs.getDouble(_kHueKey) ?? 240.0;
    final savedTs = prefs.getInt(_kTimestampKey) ?? 0;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastSavedMs = nowMs;

    if (savedTs > 0) {
      final elapsedMs = (nowMs - savedTs).clamp(0, _cycleDurationMs.toInt());
      final hueDelta = (elapsedMs / _cycleDurationMs) * 360.0;
      _hue = (savedHue + hueDelta) % 360;
    } else {
      _hue = savedHue;
    }

    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = nowMs - _lastSavedMs;
      final hueDelta = (elapsedMs / _cycleDurationMs) * 360.0;
      _hue = (_hue + hueDelta) % 360;
      _lastSavedMs = nowMs;
      _persist();
      notifyListeners();
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kHueKey, _hue);
    await prefs.setInt(_kTimestampKey, _lastSavedMs);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persist();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

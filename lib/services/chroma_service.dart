import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ChromaService — slow rainbow hue cycling over a 24-hour period.
///
/// The hue advances at ~15 degrees/hour (360° / 24h).
/// Every 20 seconds the timer fires and notifyListeners() is called,
/// but the actual hue change per 20s is only 0.0833° — imperceptible
/// moment-to-moment, yet after minutes you can tell it shifted.
///
/// The current hue + timestamp are saved to SharedPreferences on every tick
/// so that after the app is closed and reopened, the cycle continues
/// seamlessly from the right position.
class ChromaService extends ChangeNotifier with WidgetsBindingObserver {
  static const _kHueKey = 'chroma_hue';
  static const _kTimestampKey = 'chroma_ts';

  // Full cycle duration = 24 hours in milliseconds
  static const double _cycleDurationMs = 24 * 60 * 60 * 1000.0;

  double _hue = 240.0; // start at violet-ish
  Timer? _timer;
  int _lastSavedMs = 0;

  ChromaService() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  double get hue => _hue;

  /// Primary color at the current hue (vivid, high-saturation)
  Color get primary => HSLColor.fromAHSL(1.0, _hue, 0.85, 0.58).toColor();

  /// Lighter variant for shimmer/glow
  Color get primaryLight => HSLColor.fromAHSL(1.0, _hue, 0.80, 0.72).toColor();

  /// Dark/translucent variant for backgrounds
  Color get primaryDark => HSLColor.fromAHSL(0.22, _hue, 0.85, 0.58).toColor();

  /// Accent: 120° ahead on the wheel (complementary-ish)
  Color get accent => HSLColor.fromAHSL(1.0, (_hue + 120) % 360, 0.90, 0.60).toColor();

  /// Gradient: current hue → accent
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, accent],
      );

  /// Gradient matching the current position in the spectrum for buttons
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
    // Tick every 20 seconds = 0.0833° hue shift per tick
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
      _persist(); // save when app goes to background
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../screens/pin_screen.dart';

class AutoLockGate extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const AutoLockGate(
      {super.key, required this.child, required this.navigatorKey});

  @override
  State<AutoLockGate> createState() => _AutoLockGateState();
}

class _AutoLockGateState extends State<AutoLockGate>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  bool _wasUnlocked = false;
  WalletService? _wallet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wallet = context.read<WalletService>();
      _wasUnlocked = _anyUnlocked;
      _wallet!.addListener(_onWalletChanged);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _wallet?.removeListener(_onWalletChanged);
    super.dispose();
  }

  bool get _anyUnlocked =>
      (_wallet?.isUnlocked ?? false) || (_wallet?.isMerchantUnlocked ?? false);

  void _onWalletChanged() {
    final unlocked = _anyUnlocked;
    if (unlocked && !_wasUnlocked) {
      _armInactivityTimer();
    } else if (!unlocked) {
      _inactivityTimer?.cancel();
    }
    _wasUnlocked = unlocked;
  }

  void _armInactivityTimer() {
    _inactivityTimer?.cancel();
    final w = _wallet;
    if (w == null || !_anyUnlocked) return;
    final minutes = w.autoLockMinutes;
    if (minutes <= 0) {
      return;
    }
    _inactivityTimer = Timer(Duration(minutes: minutes), _triggerLock);
  }

  void _triggerLock() {
    _inactivityTimer?.cancel();
    final w = _wallet;
    if (w == null || !_anyUnlocked) return;
    final wasMerchant = w.lastSessionType == 'merchant';
    w.lock();
    widget.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            PinScreen(mode: PinMode.unlock, isMerchant: wasMerchant),
      ),
      (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final w = _wallet;
    if (w == null || !_anyUnlocked) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      final bgAt = _backgroundedAt;
      _backgroundedAt = null;
      if (bgAt == null) return;
      if (w.lockOnSuspend) {
        _triggerLock();
        return;
      }
      final minutes = w.autoLockMinutes;
      if (minutes > 0 &&
          DateTime.now().difference(bgAt) >= Duration(minutes: minutes)) {
        _triggerLock();
      } else {
        _armInactivityTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _armInactivityTimer(),
      child: widget.child,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../services/chroma_service.dart';
import '../core/theme.dart';
import '../widgets/iris_widgets.dart';
import 'pin_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut)
        .drive(Tween(begin: 0.65, end: 1.0));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));
    _ctrl.forward();
    _checkWallet();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkWallet() async {
    final wallet = context.read<WalletService>();
    final hasWallet = await wallet.checkHasWallet();
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    if (hasWallet) {
      final isMerchant = wallet.lastSessionType == 'merchant';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              PinScreen(mode: PinMode.unlock, isMerchant: isMerchant),
        ),
      );
    } else {
      Navigator.pushReplacementNamed(context, '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chroma = context.watch<ChromaService>();

    return Scaffold(
      backgroundColor: IrisTheme.bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(scale: _scaleAnim, child: child),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: chroma.primary.withOpacity(0.5),
                      blurRadius: 48,
                      spreadRadius: 8,
                    ),
                    BoxShadow(
                      color: chroma.accent.withOpacity(0.25),
                      blurRadius: 80,
                      spreadRadius: 16,
                    ),
                  ],
                ),
                child: const IrisLogo(size: 120),
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (bounds) =>
                    chroma.brandGradient.createShader(bounds),
                child: const Text(
                  'IRIS',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 10,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'sua carteira do arco-íris',
                style: TextStyle(
                  fontSize: 13,
                  color: chroma.primary.withOpacity(0.7),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              Container(
                width: 120,
                height: 3,
                decoration: BoxDecoration(
                  gradient: IrisTheme.rainbowGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

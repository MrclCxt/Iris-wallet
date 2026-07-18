import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallet_service.dart';
import '../services/chroma_service.dart';
import '../core/theme.dart';
import '../widgets/iris_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final chroma = context.watch<ChromaService>();

    return Scaffold(
      backgroundColor: BitpayTheme.bg,
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: BitpayTheme.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Real IRIS icon with chroma glow
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: chroma.primary.withOpacity(0.4),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const IrisLogo(size: 96),
                    ),
                    const SizedBox(height: 24),
                    ShaderMask(
                      shaderCallback: (b) =>
                          chroma.brandGradient.createShader(b),
                      child: const Text(
                        'IRIS',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Receba e pague com Bitcoin e DEPIX\nRápido, barato e sem burocracia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: BitpayTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Rainbow divider
                    Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: BitpayTheme.rainbowGradient,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: chroma.primaryDark,
                        border: Border.all(
                            color: chroma.primary.withOpacity(0.25)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '🔒  Sua carteira fica guardada só no seu celular.\nNinguém mais tem acesso.',
                        style: TextStyle(
                          color: chroma.primaryLight,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IrisButton(
                        label: 'Criar minha carteira grátis',
                        onPressed: () {
                          context.read<WalletService>().resetAndGenerateSeed();
                          Navigator.pushNamed(context, '/seed_gen');
                        },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BitpayTheme.textSecondary,
                          side: BorderSide(
                              color: chroma.primary.withOpacity(0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/seed_restore'),
                        child: const Text('Já tenho carteira'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

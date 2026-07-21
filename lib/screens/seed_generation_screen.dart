import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../core/theme.dart';

class SeedGenerationScreen extends StatefulWidget {
  const SeedGenerationScreen({super.key});

  @override
  State<SeedGenerationScreen> createState() => _SeedGenerationScreenState();
}

class _SeedGenerationScreenState extends State<SeedGenerationScreen> {
  @override
  void initState() {
    super.initState();
    // Gera a semente ao entrar na tela se ainda não existir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletService>().initWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final seed = wallet.consumerSeed;
    final words = seed != null ? seed.split(' ') : List.filled(12, '...');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: (wallet.consumerAccounts.isNotEmpty || wallet.merchantAccounts.isNotEmpty) 
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
              onPressed: () {
                wallet.cancelWalletCreation();
                Navigator.pop(context);
              },
            ) 
          : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: IrisTheme.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('🔑', style: TextStyle(fontSize: 17))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(wallet.consumerAccounts.isNotEmpty ? 'Nova Semente (Secundária)' : 'Nova Semente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(wallet.consumerAccounts.isNotEmpty ? 'Anote a semente da sua nova carteira. Você precisará dela para backup.' : 'Anote em um lugar seguro. É a sua única forma de recuperar a conta.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IrisTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('ANOTE EM PAPEL ANTES DE CONTINUAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: IrisTheme.textTertiary)),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 4.5,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: 12,
                    itemBuilder: (ctx, i) {
                      return Container(
                        decoration: BoxDecoration(
                          color: IrisTheme.s2,
                          border: Border.all(color: IrisTheme.bdr),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              child: Text('${i + 1}.', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: IrisTheme.textTertiary)),
                            ),
                            Text(words[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: IrisTheme.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: IrisTheme.primaryDark,
                      border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Guarde essas palavras em lugar seguro. Se perder o celular, elas recuperam tudo.',
                      style: TextStyle(color: IrisTheme.primaryLight, fontSize: 12, height: 1.55),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: seed != null ? () {
                          Navigator.pushNamed(context, '/seed_confirm');
                        } : null,
                        child: const Text('Já anotei — verificar →'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: IrisTheme.textSecondary,
                          side: const BorderSide(color: IrisTheme.bdr),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Outfit'),
                        ),
                        onPressed: () {
                          context.read<WalletService>().resetAndGenerateSeed();
                        },
                        child: const Text('Gerar palavras novas'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          context.read<WalletService>().cancelWalletCreation();
                          Navigator.of(context).popUntil((route) => route.settings.name == '/consumer_home' || route.settings.name == '/welcome' || route.isFirst);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: IrisTheme.danger,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancelar e Voltar', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

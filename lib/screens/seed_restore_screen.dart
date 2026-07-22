import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/wallet_service.dart';
import '../../core/theme.dart';

class SeedRestoreScreen extends StatefulWidget {
  const SeedRestoreScreen({super.key});

  @override
  State<SeedRestoreScreen> createState() => _SeedRestoreScreenState();
}

class _SeedRestoreScreenState extends State<SeedRestoreScreen> {
  final TextEditingController _seedController = TextEditingController();
  String? _error;

  void _importSeed() {
    final seed = _seedController.text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    // Aceita 12 ou 24 palavras; a validação (tamanho + checksum) fica no
    // serviço para as duas áreas usarem a mesma regra.
    final erro = WalletService.validateSeedPhrase(seed);
    if (erro != null) {
      setState(() => _error = erro);
      return;
    }

    // Set valid seed and go to PIN creation
    context.read<WalletService>().importSeed(seed);
    Navigator.pushReplacementNamed(context, '/pin_create');
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: IrisTheme.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('🔄', style: TextStyle(fontSize: 17))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Importar carteira', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 1),
                            const Text('Use uma seed já existente', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '12 ou 24 palavras (separadas por espaço)',
                          style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _seedController,
                          maxLines: 4,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: IrisTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'palavra1 palavra2 ...',
                            hintStyle: TextStyle(color: IrisTheme.textSecondary.withOpacity(0.5)),
                            filled: true,
                            fillColor: IrisTheme.s2,
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: IrisTheme.bdr2, width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: IrisTheme.primary, width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_error!, style: const TextStyle(fontSize: 12, color: IrisTheme.danger)),
                          ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                          decoration: BoxDecoration(
                            color: IrisTheme.primaryDark,
                            border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Use se já tem uma carteira Bitcoin Lightning para a loja ou uso pessoal.',
                            style: TextStyle(color: IrisTheme.primaryLight, fontSize: 12, height: 1.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: _importSeed,
                        child: const Text('Importar →'),
                      ),
                      if (context.watch<WalletService>().consumerAccounts.isNotEmpty || context.watch<WalletService>().merchantAccounts.isNotEmpty) ...[
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
                            context.read<WalletService>().cancelWalletCreation();
                            Navigator.of(context).popUntil((route) => route.settings.name == '/consumer_home' || route.settings.name == '/welcome' || route.isFirst);
                          },
                          child: const Text('← Voltar'),
                        ),
                      ],
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

import '../core/seed_quiz.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/wallet_service.dart';
import '../../core/theme.dart';

class SeedConfirmationScreen extends StatefulWidget {
  const SeedConfirmationScreen({super.key});

  @override
  State<SeedConfirmationScreen> createState() => _SeedConfirmationScreenState();
}

class _SeedConfirmationScreenState extends State<SeedConfirmationScreen> {
  SeedQuiz? _quiz;
  List<String?> _respostas = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateQuestions();
  }

  void _generateQuestions() {
    final seedStr = context.read<WalletService>().consumerSeed;
    if (seedStr == null) return;
    // Funciona igual para 12 ou 24 palavras.
    _quiz = SeedQuiz.gerar(seedStr.split(' '));
    _respostas = List<String?>.filled(_quiz!.indices.length, null);
  }


  void _verify() {
    final seedStr = context.read<WalletService>().consumerSeed;
    if (seedStr == null) return;
    final words = seedStr.split(' ');
    final quiz = _quiz;
    if (quiz == null) return;

    // Todas as posições sorteadas precisam bater.
    var todasCertas = true;
    for (var i = 0; i < quiz.indices.length; i++) {
      if (_respostas[i] != words[quiz.indices[i]]) todasCertas = false;
    }

    if (todasCertas) {
      setState(() => _error = null);
      Navigator.pushReplacementNamed(context, '/pin_create');
    } else {
      setState(() => _error = 'Palavras incorretas. Tente novamente ou releia sua semente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final seedStr = context.watch<WalletService>().consumerSeed;
    if (seedStr == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmação'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
                        child: const Center(child: Text('✅', style: TextStyle(fontSize: 17))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Confirme a Semente (Secundária)' : 'Confirme sua semente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(context.read<WalletService>().consumerAccounts.isNotEmpty ? 'Para garantir que anotou a nova semente.' : 'Para garantir que anotou corretamente.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IrisTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < (_quiz?.indices.length ?? 0); i++) ...[
                          _buildQuestionBlock(
                            i + 1,
                            _quiz!.indices[i],
                            _quiz!.alternativas[i],
                            _respostas[i],
                            (val) => setState(() => _respostas[i] = val),
                          ),
                          const SizedBox(height: 14),
                        ],

                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Center(
                              child: Text(_error!, style: const TextStyle(color: IrisTheme.danger, fontSize: 12), textAlign: TextAlign.center),
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
                        onPressed: (_respostas.isNotEmpty &&
                                _respostas.every((r) => r != null))
                            ? _verify
                            : null,
                        child: const Text('Confirmar e continuar'),
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
                          Navigator.pop(context);
                        },
                        child: const Text('← Voltar e reler'),
                      ),
                      if (context.watch<WalletService>().consumerAccounts.isNotEmpty || context.watch<WalletService>().merchantAccounts.isNotEmpty) ...[
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

  Widget _buildQuestionBlock(int qNum, int idx, List<String> opts, String? currentAns, ValueChanged<String> onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é a ${idx + 1}ª palavra?',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: IrisTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Row(
          children: opts.map((opt) {
            final isSelected = opt == currentAns;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? IrisTheme.primary : IrisTheme.s2,
                    border: Border.all(color: isSelected ? IrisTheme.primary : IrisTheme.bdr2, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.black : IrisTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/wallet_service.dart';
import 'pin_screen.dart';

/// Recuperação de carteira: quem esqueceu o PIN digita as 12/24 palavras da
/// própria semente e define um PIN novo. É o único caminho — o app nunca
/// guarda o PIN em forma reversível, e a semente é a verdadeira chave da
/// carteira. Reaproveita o fluxo de restauração (`importSeed` → cria conta
/// com o PIN novo → varre a blockchain).
class RecuperacaoPinScreen extends StatefulWidget {
  const RecuperacaoPinScreen({super.key});

  @override
  State<RecuperacaoPinScreen> createState() => _RecuperacaoPinScreenState();
}

class _RecuperacaoPinScreenState extends State<RecuperacaoPinScreen> {
  final _controller = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continuar() {
    final semente = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final erro = WalletService.validateSeedPhrase(semente);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    final wallet = context.read<WalletService>();
    wallet.importSeed(semente.toLowerCase());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const PinScreen(mode: PinMode.create),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(title: const Text('Recuperar carteira')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esqueceu o PIN?',
                style: TextStyle(
                    color: IrisTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'O PIN não pode ser lido nem recuperado — nem por você, nem por '
                'nós. A chave da sua carteira são as 12 ou 24 palavras da '
                'semente que você anotou ao criá-la. Digite-as abaixo para '
                'reaver o acesso com um PIN novo.',
                style: TextStyle(color: IrisTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: IrisTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'palavra1 palavra2 palavra3 …',
                  hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                  filled: true,
                  fillColor: IrisTheme.s2,
                  errorText: _erro,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _continuar,
                  style: FilledButton.styleFrom(
                    backgroundColor: IrisTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Continuar e definir novo PIN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

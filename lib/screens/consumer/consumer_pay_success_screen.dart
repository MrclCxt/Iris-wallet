import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';

class ConsumerPaySuccessScreen extends StatefulWidget {
  const ConsumerPaySuccessScreen({super.key});

  @override
  State<ConsumerPaySuccessScreen> createState() => _ConsumerPaySuccessScreenState();
}

class _ConsumerPaySuccessScreenState extends State<ConsumerPaySuccessScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  
                  const Icon(Icons.check_circle, color: IrisTheme.success, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    'Pago com sucesso!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: IrisTheme.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O valor já foi enviado para o destino.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: IrisTheme.textSecondary,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  const Text(
                    'Os detalhes reais (hash, valor e status) ficam no histórico da carteira.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: IrisTheme.textTertiary),
                  ),

                  const Spacer(),
                  
                  ElevatedButton(
                    onPressed: () {
                      // Vai direto para a home do perfil ativo, limpando
                      // qualquer resíduo da pilha de navegação — nunca cai
                      // no PIN ou em telas do fluxo de criação.
                      final isMerchant =
                          context.read<WalletService>().lastSessionType == 'merchant';
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        isMerchant ? '/merchant_home' : '/consumer_home',
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Voltar ao Início'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

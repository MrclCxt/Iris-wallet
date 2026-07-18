import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ConsumerPaySuccessScreen extends StatefulWidget {
  const ConsumerPaySuccessScreen({super.key});

  @override
  State<ConsumerPaySuccessScreen> createState() => _ConsumerPaySuccessScreenState();
}

class _ConsumerPaySuccessScreenState extends State<ConsumerPaySuccessScreen> {
  bool _showNerdData = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BitpayTheme.bg,
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
                  
                  const Icon(Icons.check_circle, color: BitpayTheme.success, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    'Pago com sucesso!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: BitpayTheme.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O valor já foi enviado para o destino.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: BitpayTheme.textSecondary,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  if (_showNerdData)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BitpayTheme.bdr),
                      ),
                      child: const Text(
                        'ROUTING LOG:\n'
                        '[+] Swap SATS -> BRL concluído\n'
                        '[+] DEPIX AUTOSWAP ativado\n'
                        '[+] Chave PIX destino: 123.456.789-00\n'
                        '[+] Hash da tx: 4a5e1e...88f2\n'
                        '[+] Fee: 0 sats',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: BitpayTheme.success,
                          height: 1.5,
                        ),
                      ),
                    ),
                    
                  const Spacer(),
                  
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showNerdData = !_showNerdData;
                      });
                    },
                    icon: const Icon(Icons.terminal, color: BitpayTheme.textSecondary, size: 16),
                    label: Text(
                      _showNerdData ? 'Esconder Dados Nerd' : 'Ver Dados Nerd',
                      style: const TextStyle(color: BitpayTheme.textSecondary),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Voltar para Home (porque usamos pushReplacement)
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

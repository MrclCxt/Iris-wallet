import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/wallet_service.dart';

/// Aparece quando o nó não conseguiu iniciar. Sem isto, a falha parecia uma
/// carteira zerada e sem nó ligado.
class AvisoNoParado extends StatelessWidget {
  final bool isMerchant;
  const AvisoNoParado({super.key, this.isMerchant = false});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    if (wallet.nodeStartError(forMerchant: isMerchant) == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: IrisTheme.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IrisTheme.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: IrisTheme.danger),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'A carteira não conectou à rede. O saldo pode estar desatualizado.',
              style: TextStyle(fontSize: 12, color: IrisTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => wallet.restartNode(forMerchant: isMerchant),
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

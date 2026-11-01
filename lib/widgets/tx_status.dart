import 'package:flutter/material.dart';

import '../core/theme.dart';

class TxStatusStyle {
  final String label;
  final IconData icon;
  final Color color;
  const TxStatusStyle(this.label, this.icon, this.color);

  /// [isIncoming] deixa o rótulo explícito: o mesmo "pendente" vira
  /// "Recebendo" ou "Enviada — confirmando" conforme a direção.
  static TxStatusStyle of(String status, {bool isIncoming = false}) {
    switch (status) {
      // Em andamento (transitório): a operação está acontecendo agora.
      case 'sending':
        return const TxStatusStyle(
            'Enviando…', Icons.arrow_upward, IrisTheme.blue);
      case 'receiving':
        return const TxStatusStyle(
            'Recebendo…', Icons.arrow_downward, IrisTheme.cyan);
      // Já na rede, aguardando confirmação — agora direcional.
      case 'pending':
        return TxStatusStyle(
            isIncoming ? 'Recebendo — confirmando' : 'Enviada — confirmando',
            Icons.schedule,
            IrisTheme.warning);
      case 'failed':
        return const TxStatusStyle(
            'Não validada', Icons.error_outline, IrisTheme.danger);
      default:
        return const TxStatusStyle(
            'Confirmada', Icons.check_circle_outline, IrisTheme.success);
    }
  }
}

class TxStatusChip extends StatelessWidget {
  final String status;
  final bool compact;
  final bool isIncoming;
  const TxStatusChip(
      {super.key,
      required this.status,
      this.compact = false,
      this.isIncoming = false});

  @override
  Widget build(BuildContext context) {
    final s = TxStatusStyle.of(status, isIncoming: isIncoming);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: s.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: compact ? 10 : 13, color: s.color),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(
              color: s.color,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class PendingBanner extends StatelessWidget {
  final int pendingSats;
  final bool hide;
  final String Function(int sats) format;
  const PendingBanner({
    super.key,
    required this.pendingSats,
    required this.format,
    this.hide = false,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingSats <= 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: IrisTheme.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IrisTheme.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(IrisTheme.warning),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hide
                      ? 'Recebendo •••• — aguardando confirmação'
                      : 'Recebendo ${format(pendingSats)} — aguardando confirmação',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: IrisTheme.warning,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'O valor entra no saldo assim que a rede confirmar.',
                  style:
                      TextStyle(fontSize: 11, color: IrisTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

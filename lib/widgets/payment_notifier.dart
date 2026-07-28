import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/currency_format.dart';
import '../core/theme.dart';
import '../services/wallet_service.dart';

class PaymentNotifier extends StatefulWidget {
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;
  const PaymentNotifier({
    super.key,
    required this.messengerKey,
    required this.child,
  });

  @override
  State<PaymentNotifier> createState() => _PaymentNotifierState();
}

class _PaymentNotifierState extends State<PaymentNotifier> {
  StreamSubscription<ReceivedPayment>? _sub;

  @override
  void initState() {
    super.initState();

    final wallet = context.read<WalletService>();
    _sub = wallet.paymentsReceived.listen(_notificar);
  }

  void _notificar(ReceivedPayment p) {
    final messenger = widget.messengerKey.currentState;
    if (messenger == null) return;

    final valor = CurrencyFormatter.formatBtcOrSats(p.amountSats);
    final via = p.isOnchain ? 'on-chain' : 'Lightning';

    late final String texto;
    late final IconData icone;
    late final Color cor;

    if (p.isConfirmation) {
      texto = 'Transação confirmada — $valor $via já disponível';
      icone = Icons.check_circle;
      cor = IrisTheme.success;
    } else if (p.isPending) {
      texto = 'Recebendo $valor $via — aguardando confirmação';
      icone = Icons.schedule;
      cor = IrisTheme.warning;
    } else {
      texto = 'Recebido $valor $via';
      icone = Icons.arrow_downward;
      cor = IrisTheme.success;
    }

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: p.isPending ? 6 : 4),
          backgroundColor: IrisTheme.s2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cor.withOpacity(0.4)),
          ),
          content: Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: IrisTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

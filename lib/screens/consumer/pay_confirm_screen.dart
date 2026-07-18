import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/currency_format.dart';
import '../../services/wallet_service.dart';
import '../../services/exchange_rate_service.dart';
import 'consumer_pay_success_screen.dart';
import '../pin_screen.dart';

class PayConfirmScreen extends StatefulWidget {
  final int satsAmount;
  final String destination;
  
  const PayConfirmScreen({
    super.key,
    required this.satsAmount,
    required this.destination,
  });

  @override
  State<PayConfirmScreen> createState() => _PayConfirmScreenState();
}

class _PayConfirmScreenState extends State<PayConfirmScreen> {
  void _confirmWithPin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinScreen(
          mode: PinMode.unlock,
          onSuccess: () async {
            Navigator.pop(context); // pop PIN
            
            // Process payment
            final wallet = context.read<WalletService>();
            
            // Check balance
            if (wallet.consumerBalance < widget.satsAmount) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Saldo insuficiente!'), backgroundColor: IrisTheme.danger),
               );
               return;
            }

            // Show loading overlay
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator(color: IrisTheme.primary)),
            );
            
            await wallet.payInvoice(widget.destination, widget.satsAmount);
            if (context.mounted) {
              Navigator.pop(context); // pop loading
              
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConsumerPaySuccessScreen(),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exchangeRate = context.watch<ExchangeRateService>();
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: IrisTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirmar pagamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: IrisTheme.textPrimary)),
            Text('Verifique antes de pagar', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: IrisTheme.s1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: IrisTheme.bdr),
                ),
                child: Column(
                  children: [
                    const Text('Valor', style: TextStyle(fontSize: 11, color: IrisTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '${CurrencyFormatter.formatSats(widget.satsAmount)} sats',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 38,
                        fontWeight: FontWeight.w600,
                        color: IrisTheme.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '≈ R\$ ${CurrencyFormatter.formatBrl(exchangeRate.satsToBrl(widget.satsAmount))}',
                      style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, color: IrisTheme.primary),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: IrisTheme.bdr),
                    const SizedBox(height: 12),
                    _buildRow('Para', widget.destination, isBold: true),
                    const SizedBox(height: 8),
                    _buildRow('Taxa', '0 sats (grátis)', valueColor: IrisTheme.success, isBold: true),
                    const SizedBox(height: 8),
                    _buildRow('Confirmação', 'menos de 2 segundos'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: IrisTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: IrisTheme.primary.withOpacity(0.2)),
                ),
                child: const Text(
                  'Depois de confirmar não é possível cancelar. Verifique o destino.',
                  style: TextStyle(fontSize: 12, color: IrisTheme.primary, height: 1.5),
                ),
              ),
              const Spacer(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirmWithPin,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Confirmar com PIN'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color valueColor = IrisTheme.textPrimary, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: IrisTheme.textSecondary)),
        Text(value, style: TextStyle(fontSize: 12, color: valueColor, fontWeight: isBold ? FontWeight.w600 : FontWeight.normal)),
      ],
    );
  }
}

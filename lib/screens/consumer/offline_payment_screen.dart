import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/currency_format.dart';
import '../../core/theme.dart';

/// Pagamento assinado sem internet. Quem recebe lê o QR no Iris (ou em outra
/// carteira) e transmite quando tiver rede; até a rede confirmar, é promessa.
class OfflinePaymentScreen extends StatelessWidget {
  final String txHex;
  final String txid;
  final int sats;

  const OfflinePaymentScreen({
    super.key,
    required this.txHex,
    required this.txid,
    required this.sats,
  });

  @override
  Widget build(BuildContext context) {
    final lado = (MediaQuery.of(context).size.width * 0.8).clamp(220.0, 420.0);
    return Scaffold(
      backgroundColor: IrisTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Pagamento sem internet',
            style: TextStyle(
                color: IrisTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: IrisTheme.textPrimary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(CurrencyFormatter.formatBtcOrSats(sats),
                  style: const TextStyle(
                      color: IrisTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: QrImageView(
                  data: txHex,
                  version: QrVersions.auto,
                  size: lado,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mostre este código para quem vai receber. O aparelho dele, '
                'com internet, envia o pagamento para a rede Bitcoin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: IrisTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: IrisTheme.warning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: IrisTheme.warning.withOpacity(0.4)),
                ),
                child: const Text(
                  'Só vale quando a rede confirmar. Até lá, quem recebe deve '
                  'tratar como pagamento pendente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: IrisTheme.warning, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: txHex));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado!')));
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Share.share(txHex),
                      icon: const Icon(Icons.share,
                          size: 18, color: Colors.black),
                      label: const Text('Enviar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('id: $txid',
                  style: const TextStyle(
                      color: IrisTheme.textTertiary,
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../services/wallet_service.dart';
import 'package:provider/provider.dart';
import '../../services/exchange_rate_service.dart';
import '../../widgets/currency_toggle_btn.dart';
import 'pay_confirm_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';

class ConsumerPayScreen extends StatefulWidget {
  const ConsumerPayScreen({super.key});

  @override
  State<ConsumerPayScreen> createState() => _ConsumerPayScreenState();
}

class _ConsumerPayScreenState extends State<ConsumerPayScreen> {
  final TextEditingController _invoiceCtrl = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isNfcAvailable = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _initNfc();
  }

  Future<void> _initNfc() async {
    try {
      _isNfcAvailable = await NfcManager.instance.isAvailable();
    } catch (_) {
      _isNfcAvailable = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scannerController.dispose();
    if (_isNfcAvailable) {
      NfcManager.instance.stopSession();
    }
    super.dispose();
  }

  void _handlePay() {
    if (_invoiceCtrl.text.isEmpty) return;
    
    final isSatsMode = context.read<ExchangeRateService>().isSatsDisplay;
    // Simulate parsing the invoice or Liquid address
    // We'll mock a 10.000 sats payment or equivalent DEPIX to "Satoshi Nakamoto" as the HTML did
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayConfirmScreen(
          satsAmount: 10000,
          destination: isSatsMode ? 'Lightning Node (Satoshi Nakamoto)' : 'Liquid Address (Satoshi Nakamoto)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSatsMode = context.watch<ExchangeRateService>().isSatsDisplay;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48), // Balance for centering
                const Text(
                  'Pagar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const CurrencyToggleBtn(),
              ],
            ),
            const SizedBox(height: 24),

            // Scanner Area
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: IrisTheme.s1,
                    border: Border.all(color: IrisTheme.bdr),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: (capture) {
                          if (_hasScanned) return;
                          final List<Barcode> barcodes = capture.barcodes;
                          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                            _hasScanned = true;
                            setState(() {
                              _invoiceCtrl.text = barcodes.first.rawValue!;
                            });
                            _handlePay();
                            
                            // Reset scan state after a delay
                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted) _hasScanned = false;
                            });
                          }
                        },
                      ),
                      const Positioned(
                        bottom: 16,
                        child: Text(
                          'Aponte para o QR Code',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Paste Input
            TextField(
              controller: _invoiceCtrl,
              decoration: InputDecoration(
                hintText: isSatsMode ? 'Colar fatura Lightning' : 'Colar endereço Liquid',
                hintStyle: const TextStyle(color: IrisTheme.textTertiary),
                filled: true,
                fillColor: IrisTheme.s1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: IrisTheme.bdr),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: IrisTheme.bdr),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, color: IrisTheme.primary),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null && data!.text!.isNotEmpty) {
                      setState(() {
                        _invoiceCtrl.text = data.text!;
                      });
                    }
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // NFC Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: IrisTheme.s1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: IrisTheme.bdr),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.contactless, color: IrisTheme.textSecondary),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Pagar por aproximação', overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  Switch(
                    value: context.watch<WalletService>().isNfcEnabled,
                    activeColor: IrisTheme.primary,
                    onChanged: _isNfcAvailable ? (val) async {
                      context.read<WalletService>().toggleNfc(val);
                      if (val) {
                        try {
                          await NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
                            final ndef = Ndef.from(tag);
                            if (ndef != null && ndef.cachedMessage != null) {
                              for (var record in ndef.cachedMessage!.records) {
                                final payload = String.fromCharCodes(record.payload);
                                // The payload often contains a language code prefix, e.g. "en"
                                final invoice = payload.length > 3 ? payload.substring(3) : payload;
                                if (mounted) {
                                  setState(() {
                                    _invoiceCtrl.text = invoice;
                                  });
                                }
                                NfcManager.instance.stopSession();
                                _handlePay();
                                if (mounted) {
                                  context.read<WalletService>().toggleNfc(false);
                                }
                                break;
                              }
                            }
                          });
                        } catch (e) {
                          debugPrint('NFC error: $e');
                        }
                      } else {
                        NfcManager.instance.stopSession();
                      }
                    } : null,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handlePay,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                child: const Text('Confirmar e Pagar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

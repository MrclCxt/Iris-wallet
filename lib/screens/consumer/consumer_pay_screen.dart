import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/bolt11.dart';
import '../../core/lnurl.dart';
import '../../core/tx_policy.dart';
import '../../services/wallet_service.dart';
import 'package:provider/provider.dart';
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
  bool _isResolving = false;

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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: IrisTheme.danger),
    );
  }

  String _sanitize(String raw) {
    var s = raw.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith('lightning:')) s = s.substring(10);
    return s.trim();
  }

  /// Endereço Bitcoin (testnet: tb1/m/n/2; mainnet: bc1/1/3) ou URI BIP21.
  bool _looksLikeBitcoin(String input) {
    final s = input.toLowerCase();
    if (s.startsWith('bitcoin:')) return true;
    return RegExp(r'^(tb1|bc1)[a-z0-9]{20,}$').hasMatch(s) ||
        RegExp(r'^[mn2][a-km-zA-HJ-NP-Z1-9]{25,39}$').hasMatch(input.trim());
  }

  /// Decompõe URI BIP21: endereço, valor (sats) e fatura Lightning unificada.
  ({String address, int? sats, String? lightning}) _parseBip21(String input) {
    var s = input.trim();
    if (s.toLowerCase().startsWith('bitcoin:')) s = s.substring(8);
    String? lightning;
    int? sats;
    final qIdx = s.indexOf('?');
    if (qIdx != -1) {
      final params = Uri.splitQueryString(s.substring(qIdx + 1));
      final amountBtc = double.tryParse(params['amount'] ?? '');
      if (amountBtc != null) sats = (amountBtc * 100000000).round();
      lightning = params['lightning'];
      s = s.substring(0, qIdx);
    }
    return (address: s, sats: sats, lightning: lightning);
  }

  bool _looksLikeLiquid(String input) {
    final s = input.toLowerCase();
    if (s.startsWith('liquid:') || s.startsWith('liquidtestnet:')) return true;
    // Prefixos de endereços Liquid (mainnet e testnet, confidenciais ou não)
    return s.startsWith('lq1') ||
        s.startsWith('tlq1') ||
        s.startsWith('vjl') ||
        s.startsWith('tex1') ||
        s.startsWith('ex1');
  }

  String _extractLiquidAddress(String input) {
    var s = input;
    final lower = s.toLowerCase();
    if (lower.startsWith('liquid:')) s = s.substring(7);
    if (lower.startsWith('liquidtestnet:')) s = s.substring(14);
    final qIdx = s.indexOf('?');
    if (qIdx != -1) s = s.substring(0, qIdx);
    return s;
  }

  /// Interpreta o conteúdo (QR, colagem ou NFC) e roteia para o fluxo real:
  /// fatura BOLT11 -> LDK | LNURL/Lightning Address -> LUD-06 | Liquid -> LWK.
  Future<void> _handlePay() async {
    if (_isResolving) return;
    final input = _sanitize(_invoiceCtrl.text);
    if (input.isEmpty) return;

    setState(() => _isResolving = true);
    try {
      if (Bolt11.looksLikeInvoice(input)) {
        final parsed = Bolt11.decode(input);
        if (!parsed.isTestnet) {
          _showError('Fatura da mainnet detectada — este protótipo opera apenas na testnet.');
          return;
        }
        if (parsed.isExpired) {
          _showError('Esta fatura já expirou. Peça uma nova cobrança.');
          return;
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PayConfirmScreen(
              satsAmount: parsed.amountSats ?? 0,
              destination: parsed.description.isNotEmpty
                  ? parsed.description
                  : 'Fatura Lightning',
              rawInvoice: input,
              editableAmount: parsed.amountSats == null,
            ),
          ),
        );
      } else if (Lnurl.looksLikeLnurl(input)) {
        final params = await Lnurl.fetchPayParams(input);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PayConfirmScreen(
              satsAmount: params.minSendableSats,
              destination: params.description,
              lnurlParams: params,
              editableAmount: !params.isFixedAmount,
            ),
          ),
        );
      } else if (_looksLikeBitcoin(input)) {
        final parsed = _parseBip21(input);
        // Política de roteamento: Lightning para o dia a dia; acima do
        // limiar (ou sem fatura unificada) vai pela rede Bitcoin on-chain.
        final useLightning = parsed.lightning != null &&
            parsed.sats != null &&
            !TxPolicy.shouldUseOnchain(parsed.sats!);
        if (useLightning && Bolt11.looksLikeInvoice(parsed.lightning!)) {
          final inv = Bolt11.decode(parsed.lightning!);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PayConfirmScreen(
                satsAmount: inv.amountSats ?? parsed.sats ?? 0,
                destination: inv.description.isNotEmpty ? inv.description : 'Fatura Lightning',
                rawInvoice: parsed.lightning,
                editableAmount: inv.amountSats == null,
              ),
            ),
          );
        } else {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PayConfirmScreen(
                satsAmount: parsed.sats ?? 0,
                destination: 'Endereço Bitcoin (on-chain)',
                btcAddress: parsed.address,
                editableAmount: parsed.sats == null,
              ),
            ),
          );
        }
      } else if (_looksLikeLiquid(input)) {
        final address = _extractLiquidAddress(input);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PayConfirmScreen(
              satsAmount: 0,
              destination: 'Endereço Liquid',
              liquidAddress: address,
              editableAmount: true,
            ),
          ),
        );
      } else {
        _showError('Código não reconhecido. Use fatura Lightning, LNURL, endereço Bitcoin ou Liquid.');
      }
    } on Bolt11ParseException catch (e) {
      _showError('Fatura inválida: ${e.message}');
    } on LnurlException catch (e) {
      _showError('LNURL: ${e.message}');
    } catch (e) {
      _showError('Erro ao processar: $e');
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                hintText: 'Fatura Lightning, LNURL ou endereço',
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
                onPressed: _isResolving ? null : _handlePay,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                child: _isResolving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Confirmar e Pagar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

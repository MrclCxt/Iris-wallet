import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zx;
import '../../core/theme.dart';
import '../../core/bolt11.dart';
import '../../core/brcode.dart';
import '../../core/lnurl.dart';
import '../../core/tx_policy.dart';
import '../../services/wallet_service.dart';
import 'package:provider/provider.dart';
import '../../widgets/currency_toggle_btn.dart';
import 'pay_confirm_screen.dart';
import 'package:camera/camera.dart' as cam;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';

class ConsumerPayScreen extends StatefulWidget {
  const ConsumerPayScreen({super.key});

  @override
  State<ConsumerPayScreen> createState() => _ConsumerPayScreenState();
}

class _ConsumerPayScreenState extends State<ConsumerPayScreen> {
  final TextEditingController _invoiceCtrl = TextEditingController();

  // Câmera: sempre inicia desligada; o usuário liga quando quiser escanear.
  MobileScannerController? _scannerController;
  bool _cameraOn = false;
  bool _cameraDetected = false; // existe câmera conectada no dispositivo?
  bool _cameraProbeDone = false;
  bool _isNfcAvailable = false;
  bool _hasScanned = false;
  bool _isResolving = false;

  // Pipeline Windows: preview via camera_windows + captura periódica +
  // decodificação QR com ZXing (o mobile_scanner não tem backend Windows).
  cam.CameraController? _winCamCtrl;
  Timer? _winScanTimer;
  bool _winDecoding = false;

  bool get _useWindowsPipeline => Platform.isWindows;

  /// Linux não tem backend de câmera em nenhum dos plugins.
  bool get _cameraSupported => !Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _initNfc();
    _detectCamera();
  }

  /// Enumera as câmeras do dispositivo SEM abri-las: a opção de ligar só
  /// aparece se existir hardware de verdade; sem câmera, a área some.
  Future<void> _detectCamera() async {
    if (!_cameraSupported) {
      _cameraDetected = false;
      _cameraProbeDone = true;
      if (mounted) setState(() {});
      return;
    }
    try {
      final cameras = await cam.availableCameras();
      _cameraDetected = cameras.isNotEmpty;
    } on cam.CameraException {
      _cameraDetected = false;
    } catch (_) {
      // Plataforma sem enumeração (ex.: macOS): o scanner tem suporte,
      // então deixamos o usuário tentar ligar.
      _cameraDetected = !Platform.isWindows;
    }
    _cameraProbeDone = true;
    if (mounted) setState(() {});
  }

  // ---- Pipeline de scan do Windows (captura + ZXing) ----

  Future<void> _startWindowsCamera() async {
    final cameras = await cam.availableCameras();
    if (cameras.isEmpty) throw Exception('Nenhuma câmera encontrada.');
    final ctrl = cam.CameraController(
      cameras.first,
      cam.ResolutionPreset.medium,
      enableAudio: false,
    );
    await ctrl.initialize();
    _winCamCtrl = ctrl;
    // Captura um quadro por segundo e tenta decodificar o QR
    _winScanTimer = Timer.periodic(const Duration(seconds: 1), (_) => _winCaptureAndDecode());
  }

  Future<void> _stopWindowsCamera() async {
    _winScanTimer?.cancel();
    _winScanTimer = null;
    final ctrl = _winCamCtrl;
    _winCamCtrl = null;
    try {
      await ctrl?.dispose();
    } catch (_) {}
  }

  Future<void> _winCaptureAndDecode() async {
    final ctrl = _winCamCtrl;
    if (ctrl == null || _winDecoding || _hasScanned || _isResolving) return;
    _winDecoding = true;
    try {
      final shot = await ctrl.takePicture();
      final bytes = await shot.readAsBytes();
      try {
        await File(shot.path).delete();
      } catch (_) {}

      final text = await _decodeQrFromImage(bytes);
      if (text != null && mounted && !_hasScanned) {
        _hasScanned = true;
        setState(() => _invoiceCtrl.text = text);
        _toggleCamera(); // desliga após a leitura
        await _handlePay();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _hasScanned = false;
        });
      }
    } catch (e) {
      debugPrint('Scan Windows: $e');
    } finally {
      _winDecoding = false;
    }
  }

  /// Decodifica um QR de uma imagem capturada usando ZXing (Dart puro).
  Future<String?> _decodeQrFromImage(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final rgba = decoded.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
    final pixels = Int32List(decoded.width * decoded.height);
    for (int i = 0, p = 0; i < pixels.length; i++, p += 4) {
      pixels[i] = (0xFF << 24) | (rgba[p] << 16) | (rgba[p + 1] << 8) | rgba[p + 2];
    }
    final source = zx.RGBLuminanceSource(decoded.width, decoded.height, pixels);
    try {
      final result =
          zx.QRCodeReader().decode(zx.BinaryBitmap(zx.HybridBinarizer(source)));
      return result.text;
    } catch (_) {
      return null; // nenhum QR neste quadro
    }
  }

  Future<void> _initNfc() async {
    try {
      _isNfcAvailable = await NfcManager.instance.isAvailable();
    } catch (_) {
      _isNfcAvailable = false;
    }
    if (mounted) setState(() {});
  }

  void _toggleCamera() {
    if (!_cameraSupported || !_cameraDetected) return;
    if (_cameraOn) {
      if (_useWindowsPipeline) {
        _stopWindowsCamera();
      } else {
        _scannerController?.dispose();
        _scannerController = null;
      }
      setState(() => _cameraOn = false);
    } else {
      if (_useWindowsPipeline) {
        _startWindowsCamera().then((_) {
          if (mounted) setState(() => _cameraOn = true);
        }).catchError((e) {
          if (mounted) {
            _showError('Não foi possível abrir a câmera: $e');
          }
        });
      } else {
        _scannerController = MobileScannerController();
        setState(() => _cameraOn = true);
      }
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _stopWindowsCamera();
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

  /// Chave PIX avulsa: CPF (11 dígitos), telefone (+55...) ou chave aleatória
  /// (UUID). E-mails são tratados como Lightning Address (LUD-16).
  bool _looksLikePixKey(String input) {
    final s = input.trim();
    if (RegExp(r'^\d{11}$').hasMatch(s)) return true; // CPF
    if (RegExp(r'^\+\d{12,14}$').hasMatch(s)) return true; // telefone E.164
    if (RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false)
        .hasMatch(s)) return true; // chave aleatória
    return false;
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
      if (BrCode.looksLikeBrCode(input)) {
        // QR PIX (BR Code EMV): decodifica chave, nome e valor reais
        final decoded = BrCode.decode(input);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PayConfirmScreen(
              satsAmount: 0,
              destination: decoded.merchantName.isNotEmpty
                  ? decoded.merchantName
                  : decoded.pixKey,
              pixTarget: decoded.raw,
              pixAmountBrl: decoded.amountBrl,
              editableAmount: decoded.amountBrl == null,
            ),
          ),
        );
      } else if (Bolt11.looksLikeInvoice(input)) {
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
      } else if (_looksLikePixKey(input)) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PayConfirmScreen(
              satsAmount: 0,
              destination: input,
              pixTarget: input,
              editableAmount: true,
            ),
          ),
        );
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
        _showError('Código não reconhecido. Use fatura Lightning, LNURL, QR PIX, endereço Bitcoin ou Liquid.');
      }
    } on Bolt11ParseException catch (e) {
      _showError('Fatura inválida: ${e.message}');
    } on BrCodeException catch (e) {
      _showError('QR PIX inválido: ${e.message}');
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

            // Scanner Area — câmera sempre inicia desligada.
            // Sem câmera conectada: a área simplesmente não aparece.
            if (_cameraProbeDone && !_cameraDetected)
              const Spacer()
            else
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: IrisTheme.s1,
                    border: Border.all(color: IrisTheme.bdr),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: !_cameraOn
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.videocam_off_outlined,
                                      size: 48, color: IrisTheme.textTertiary),
                                  const SizedBox(height: 16),
                                  Text(
                                    !_cameraProbeDone ? 'Procurando câmera...' : 'Câmera desligada',
                                    style: const TextStyle(
                                        color: IrisTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_cameraDetected)
                                    ElevatedButton.icon(
                                      onPressed: _toggleCamera,
                                      icon: const Icon(Icons.videocam_outlined, size: 20),
                                      label: const Text('Ligar câmera'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 12),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : _useWindowsPipeline
                              ? Stack(
                                  alignment: Alignment.center,
                                  fit: StackFit.expand,
                                  children: [
                                    if (_winCamCtrl != null && _winCamCtrl!.value.isInitialized)
                                      // Preserva a proporção real da câmera:
                                      // preenche a área cortando as bordas
                                      // (cover), nunca esticando a imagem.
                                      Positioned.fill(
                                        child: FittedBox(
                                          fit: BoxFit.cover,
                                          clipBehavior: Clip.hardEdge,
                                          child: SizedBox(
                                            width: _winCamCtrl!.value.previewSize?.width ?? 1280,
                                            height: _winCamCtrl!.value.previewSize?.height ?? 720,
                                            child: cam.CameraPreview(_winCamCtrl!),
                                          ),
                                        ),
                                      ),
                                    const Positioned(
                                      bottom: 16,
                                      left: 0,
                                      right: 0,
                                      child: Text(
                                        'Aponte para o QR Code',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          backgroundColor: Colors.black54,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: IconButton(
                                        onPressed: _toggleCamera,
                                        tooltip: 'Desligar câmera',
                                        style: IconButton.styleFrom(
                                            backgroundColor: Colors.black54),
                                        icon: const Icon(Icons.videocam_off,
                                            color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ],
                                )
                              : Stack(
                              alignment: Alignment.center,
                              children: [
                                MobileScanner(
                                  controller: _scannerController!,
                                  errorBuilder: (context, error, child) => Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        'Não foi possível acessar a câmera: ${error.errorCode.name}',
                                        style: const TextStyle(
                                            color: IrisTheme.textSecondary, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
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
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: IconButton(
                                    onPressed: _toggleCamera,
                                    tooltip: 'Desligar câmera',
                                    style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54),
                                    icon: const Icon(Icons.videocam_off,
                                        color: Colors.white, size: 20),
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
                hintText: 'Lightning, PIX, LNURL ou endereço',
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

            // NFC: só aparece quando o dispositivo realmente tem o hardware
            if (_isNfcAvailable) ...[
            const SizedBox(height: 16),

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
            ],

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

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/brcode.dart';
import 'liquid_wallet_service.dart';
import 'swap_service.dart';

/// Entrada e saída de Reais via PIX.
///
/// Depósito:  PIX (BRL) -> provedor emite DEPIX na Liquid -> swap -> sats.
/// Saque:     sats -> L-BTC/DEPIX para o provedor -> provedor paga a chave
///            PIX do destinatário em BRL.
///
/// Provedores:
/// - [DepixAppProvider]: DePix App (api.depixapp.com) — provedor DEPIX real.
///   Chave `sk_test_` = sandbox oficial (QR sintético + simulate-payment);
///   chave `sk_live_` = dinheiro de verdade.
/// - [RestPixProvider]: contrato REST genérico para outros provedores DEPIX.
/// - [SimulatedPixProvider]: offline/testnet, sem provedor configurado.

enum PixChargeStatus { pending, paid, settled, expired, failed }

class PixCharge {
  final String id;
  final double amountBrl;
  final String qrCopiaECola;
  PixChargeStatus status;

  PixCharge({
    required this.id,
    required this.amountBrl,
    required this.qrCopiaECola,
    this.status = PixChargeStatus.pending,
  });
}

class PixWithdrawal {
  final String id;
  final double amountBrl;
  final String pixKey;
  final String depixAddress; // endereço Liquid do provedor para receber DEPIX
  final int feeCents;
  final String? feeAddress; // saída de taxa exigida pelo provedor (se houver)
  PixChargeStatus status;

  PixWithdrawal({
    required this.id,
    required this.amountBrl,
    required this.pixKey,
    required this.depixAddress,
    this.feeCents = 0,
    this.feeAddress,
    this.status = PixChargeStatus.pending,
  });
}

abstract class PixProvider {
  String get name;
  bool get isSimulated;

  /// Sandbox com simulação de pagamento disponível.
  bool get canSimulate;

  /// Provedor oferece QR fixo (sem valor) via API.
  bool get supportsStaticQr;

  /// Provedor exige CPF/CNPJ do pagador ao criar a cobrança.
  bool get requiresPayerTaxNumber;

  Future<PixCharge> getStaticDeposit({required String depixAddress});

  Future<PixCharge> createDeposit({
    required double amountBrl,
    required String depixAddress,
    String? payerTaxNumber,
  });

  Future<void> simulatePayment(String chargeId);

  Future<PixChargeStatus> getDepositStatus(String chargeId);

  Future<PixWithdrawal> createWithdrawal({
    required double amountBrl,
    required String pixKey,
    String? taxNumber,
  });
}

// ---------------------------------------------------------------------------
// Provedor simulado (sem credenciais): percorre os estados sem mover BRL
// ---------------------------------------------------------------------------

class SimulatedPixProvider implements PixProvider {
  @override
  String get name => 'Simulado (sem provedor)';
  @override
  bool get isSimulated => true;
  @override
  bool get canSimulate => true;
  @override
  bool get supportsStaticQr => true;
  @override
  bool get requiresPayerTaxNumber => false;

  final Map<String, PixCharge> _charges = {};

  @override
  Future<PixCharge> getStaticDeposit({required String depixAddress}) async {
    // BR Code fixo sem valor (tag 54 ausente): estrutura EMV e CRC16 reais.
    final qr = BrCode.build(
      pixKey: 'testnet@iris.wallet',
      merchantName: 'IRIS WALLET TESTNET',
      merchantCity: 'ITAPETININGA',
      txid: 'STATIC',
    );
    return PixCharge(id: 'static', amountBrl: 0, qrCopiaECola: qr);
  }

  @override
  Future<PixCharge> createDeposit({
    required double amountBrl,
    required String depixAddress,
    String? payerTaxNumber,
  }) async {
    final id = 'IRIS${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(999)}';
    final qr = BrCode.build(
      pixKey: 'testnet@iris.wallet',
      amountBrl: amountBrl,
      merchantName: 'IRIS WALLET TESTNET',
      merchantCity: 'ITAPETININGA',
      txid: id.length > 25 ? id.substring(0, 25) : id,
    );
    final charge = PixCharge(id: id, amountBrl: amountBrl, qrCopiaECola: qr);
    _charges[id] = charge;
    return charge;
  }

  @override
  Future<void> simulatePayment(String chargeId) async {
    _charges[chargeId]?.status = PixChargeStatus.paid;
  }

  @override
  Future<PixChargeStatus> getDepositStatus(String chargeId) async {
    return _charges[chargeId]?.status ?? PixChargeStatus.failed;
  }

  @override
  Future<PixWithdrawal> createWithdrawal({
    required double amountBrl,
    required String pixKey,
    String? taxNumber,
  }) async {
    return PixWithdrawal(
      id: 'simw_${DateTime.now().millisecondsSinceEpoch}',
      amountBrl: amountBrl,
      pixKey: pixKey,
      depixAddress: 'tlq1_endereco_simulado_do_provedor',
    );
  }
}

// ---------------------------------------------------------------------------
// DePix App (api.depixapp.com) — provedor DEPIX real
// Docs: https://depixapp.com/docs/
// ---------------------------------------------------------------------------

class DepixAppProvider implements PixProvider {
  static const String baseUrl = 'https://api.depixapp.com';
  final String apiKey;
  final http.Client _client;

  DepixAppProvider({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  bool get isTestKey => apiKey.startsWith('sk_test_');

  @override
  String get name => 'DePix App ${isTestKey ? '(sandbox)' : '(LIVE)'}';
  @override
  bool get isSimulated => false;
  @override
  bool get canSimulate => isTestKey;
  @override
  bool get supportsStaticQr => false; // emite QR por cobrança (checkout)
  @override
  bool get requiresPayerTaxNumber => true;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  Never _fail(http.Response r) {
    String message = 'HTTP ${r.statusCode}';
    try {
      final data = jsonDecode(r.body);
      message = data['response']?['errorMessage']?.toString() ??
          data['error']?['message']?.toString() ??
          message;
    } catch (_) {}
    throw Exception('DePix App: $message');
  }

  @override
  Future<PixCharge> getStaticDeposit({required String depixAddress}) {
    throw UnsupportedError(
        'O DePix App emite QR por cobrança — defina um valor para gerar o PIX.');
  }

  @override
  Future<PixCharge> createDeposit({
    required double amountBrl,
    required String depixAddress,
    String? payerTaxNumber,
  }) async {
    if (payerTaxNumber == null || payerTaxNumber.trim().isEmpty) {
      throw Exception('Informe o CPF/CNPJ do pagador (exigência do provedor).');
    }
    final cents = (amountBrl * 100).round();
    if (cents < 500) {
      throw Exception('O DePix App exige valor mínimo de R\$ 5,00.');
    }
    final r = await _client.post(
      Uri.parse('$baseUrl/api/checkouts'),
      headers: _headers,
      body: jsonEncode({
        'amount': cents,
        'payer_tax_number': payerTaxNumber.trim(),
        'description': 'Deposito Iris Wallet',
      }),
    );
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    final data = jsonDecode(r.body);
    final checkout = data['checkout'] ?? data;
    return PixCharge(
      id: checkout['id'].toString(),
      amountBrl: amountBrl,
      qrCopiaECola: checkout['pix']?['qr_code']?.toString() ?? '',
    );
  }

  @override
  Future<void> simulatePayment(String chargeId) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/api/checkouts/$chargeId/simulate-payment'),
      headers: _headers,
    );
    if (r.statusCode != 200) _fail(r);
  }

  @override
  Future<PixChargeStatus> getDepositStatus(String chargeId) async {
    final r = await _client.get(
      Uri.parse('$baseUrl/api/checkouts/$chargeId'),
      headers: _headers,
    );
    if (r.statusCode != 200) return PixChargeStatus.pending;
    final status =
        jsonDecode(r.body)['checkout']?['status']?.toString() ?? 'pending';
    switch (status) {
      case 'processing':
      case 'approved':
        return PixChargeStatus.paid;
      case 'completed':
        return PixChargeStatus.settled;
      case 'expired':
        return PixChargeStatus.expired;
      case 'cancelled':
        return PixChargeStatus.failed;
      default:
        return PixChargeStatus.pending;
    }
  }

  @override
  Future<PixWithdrawal> createWithdrawal({
    required double amountBrl,
    required String pixKey,
    String? taxNumber,
  }) async {
    if (taxNumber == null || taxNumber.trim().isEmpty) {
      throw Exception('Informe o CPF/CNPJ do favorecido (exigência do provedor).');
    }
    final r = await _client.post(
      Uri.parse('$baseUrl/api/withdraw'),
      headers: _headers,
      body: jsonEncode({
        'pixKey': pixKey,
        'payoutAmountInCents': (amountBrl * 100).round(),
        'taxNumber': taxNumber.trim(),
      }),
    );
    if (r.statusCode != 200 && r.statusCode != 201) _fail(r);
    final resp = jsonDecode(r.body)['response'] ?? jsonDecode(r.body);
    return PixWithdrawal(
      id: resp['withdrawalId'].toString(),
      amountBrl: amountBrl,
      pixKey: pixKey,
      depixAddress: resp['depositAddress']?.toString() ?? '',
      feeCents: (resp['fee_cents'] as num?)?.toInt() ?? 0,
      feeAddress: resp['fee_address']?.toString(),
    );
  }
}

// ---------------------------------------------------------------------------
// Provedor REST genérico (outros emissores DEPIX)
// ---------------------------------------------------------------------------

/// Contrato esperado (adaptável por provedor):
///   POST {base}/static    {"depix_address":".."} -> {"id","qr_copia_e_cola"}
///   POST {base}/deposit   {"amount_brl","depix_address"} -> {"id","qr_copia_e_cola"}
///   GET  {base}/deposit/{id} -> {"status":"pending|paid|settled|expired"}
///   POST {base}/withdraw  {"amount_brl","pix_key"} -> {"id","depix_address"}
/// Autenticação: Authorization: Bearer {apiKey}.
class RestPixProvider implements PixProvider {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  RestPixProvider({required this.baseUrl, required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  @override
  String get name => Uri.parse(baseUrl).host;
  @override
  bool get isSimulated => false;
  @override
  bool get canSimulate => false;
  @override
  bool get supportsStaticQr => true;
  @override
  bool get requiresPayerTaxNumber => false;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  @override
  Future<PixCharge> getStaticDeposit({required String depixAddress}) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/static'),
      headers: _headers,
      body: jsonEncode({'depix_address': depixAddress}),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Provedor PIX respondeu ${r.statusCode}: ${r.body}');
    }
    final data = jsonDecode(r.body);
    return PixCharge(
      id: data['id'].toString(),
      amountBrl: 0,
      qrCopiaECola: data['qr_copia_e_cola']?.toString() ?? '',
    );
  }

  @override
  Future<PixCharge> createDeposit({
    required double amountBrl,
    required String depixAddress,
    String? payerTaxNumber,
  }) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/deposit'),
      headers: _headers,
      body: jsonEncode({'amount_brl': amountBrl, 'depix_address': depixAddress}),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Provedor PIX respondeu ${r.statusCode}: ${r.body}');
    }
    final data = jsonDecode(r.body);
    return PixCharge(
      id: data['id'].toString(),
      amountBrl: amountBrl,
      qrCopiaECola: data['qr_copia_e_cola']?.toString() ?? data['qrCopiaECola']?.toString() ?? '',
    );
  }

  @override
  Future<void> simulatePayment(String chargeId) async {
    throw UnsupportedError('Este provedor não possui sandbox de simulação.');
  }

  @override
  Future<PixChargeStatus> getDepositStatus(String chargeId) async {
    final r = await _client.get(Uri.parse('$baseUrl/deposit/$chargeId'), headers: _headers);
    if (r.statusCode != 200) return PixChargeStatus.pending;
    final status = jsonDecode(r.body)['status']?.toString() ?? 'pending';
    switch (status) {
      case 'paid':
        return PixChargeStatus.paid;
      case 'settled':
        return PixChargeStatus.settled;
      case 'expired':
        return PixChargeStatus.expired;
      case 'failed':
        return PixChargeStatus.failed;
      default:
        return PixChargeStatus.pending;
    }
  }

  @override
  Future<PixWithdrawal> createWithdrawal({
    required double amountBrl,
    required String pixKey,
    String? taxNumber,
  }) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/withdraw'),
      headers: _headers,
      body: jsonEncode({'amount_brl': amountBrl, 'pix_key': pixKey}),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Provedor PIX respondeu ${r.statusCode}: ${r.body}');
    }
    final data = jsonDecode(r.body);
    return PixWithdrawal(
      id: data['id'].toString(),
      amountBrl: amountBrl,
      pixKey: pixKey,
      depixAddress: data['depix_address']?.toString() ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Orquestração
// ---------------------------------------------------------------------------

class PixService extends ChangeNotifier {
  final LiquidWalletService liquidWalletService;
  final SwapService swapService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  PixProvider _provider = SimulatedPixProvider();
  PixProvider get provider => _provider;

  PixCharge? activeCharge;
  PixCharge? staticCharge; // QR fixo da carteira (sem valor)
  Timer? _pollTimer;
  final List<String> logs = [];

  String? _payerTaxNumber; // CPF/CNPJ do usuário para depósitos
  String? get payerTaxNumber => _payerTaxNumber;

  PixService({required this.liquidWalletService, required this.swapService}) {
    _loadProviderConfig();
  }

  /// Descarta cobranças da conta que estava ativa. Um QR PIX aponta para um
  /// endereço Liquid de uma carteira específica: se sobrevivesse à troca de
  /// conta, o depósito cairia na carteira errada.
  void clearForAccountSwitch() {
    _pollTimer?.cancel();
    _pollTimer = null;
    activeCharge = null;
    staticCharge = null;
    notifyListeners();
  }

  void _log(String message) {
    logs.add(message);
    notifyListeners();
  }

  Future<void> _loadProviderConfig() async {
    final type = await _storage.read(key: 'pix_provider_type');
    final url = await _storage.read(key: 'pix_provider_url');
    final key = await _storage.read(key: 'pix_provider_key');
    _payerTaxNumber = await _storage.read(key: 'pix_payer_taxnumber');

    if (type == 'depixapp' && key != null && key.isNotEmpty) {
      _provider = DepixAppProvider(apiKey: key);
    } else if (type == 'rest' && url != null && url.isNotEmpty && key != null) {
      _provider = RestPixProvider(baseUrl: url, apiKey: key);
    }
    notifyListeners();
  }

  /// Configura o provedor. type: 'sim' | 'depixapp' | 'rest'.
  Future<void> configureProvider({
    required String type,
    String? baseUrl,
    String? apiKey,
  }) async {
    staticCharge = null;
    activeCharge = null;
    _pollTimer?.cancel();

    switch (type) {
      case 'depixapp':
        final key = (apiKey ?? '').trim();
        if (key.isEmpty) throw Exception('Informe a chave sk_test_/sk_live_ do DePix App.');
        await _storage.write(key: 'pix_provider_type', value: 'depixapp');
        await _storage.write(key: 'pix_provider_key', value: key);
        await _storage.delete(key: 'pix_provider_url');
        _provider = DepixAppProvider(apiKey: key);
        break;
      case 'rest':
        final url = (baseUrl ?? '').trim();
        if (url.isEmpty) throw Exception('Informe a URL base do provedor.');
        await _storage.write(key: 'pix_provider_type', value: 'rest');
        await _storage.write(key: 'pix_provider_url', value: url);
        await _storage.write(key: 'pix_provider_key', value: (apiKey ?? '').trim());
        _provider = RestPixProvider(baseUrl: url, apiKey: (apiKey ?? '').trim());
        break;
      default:
        await _storage.delete(key: 'pix_provider_type');
        await _storage.delete(key: 'pix_provider_url');
        await _storage.delete(key: 'pix_provider_key');
        _provider = SimulatedPixProvider();
    }
    notifyListeners();
  }

  Future<void> setPayerTaxNumber(String value) async {
    _payerTaxNumber = value.trim();
    await _storage.write(key: 'pix_payer_taxnumber', value: _payerTaxNumber!);
    notifyListeners();
  }

  /// Garante o QR PIX fixo da carteira (quando o provedor suporta).
  Future<PixCharge> ensureStaticDeposit() async {
    if (staticCharge != null) return staticCharge!;
    if (!_provider.supportsStaticQr) {
      throw UnsupportedError(
          '${_provider.name} emite QR por cobrança — defina um valor.');
    }
    String depixAddress;
    try {
      depixAddress = await liquidWalletService.getReceiveAddress();
    } catch (_) {
      depixAddress = 'indisponivel';
    }
    staticCharge = await _provider.getStaticDeposit(depixAddress: depixAddress);
    notifyListeners();
    return staticCharge!;
  }

  /// Volta ao QR fixo, descartando a cobrança temporária de valor definido.
  void clearActiveCharge() {
    _pollTimer?.cancel();
    activeCharge = null;
    notifyListeners();
  }

  /// Inicia um depósito: gera a cobrança PIX e acompanha até liquidar.
  Future<PixCharge> startDeposit(double amountBrl, {String? payerTaxNumber}) async {
    logs.clear();
    _log('[PIX] Gerando cobrança de R\$ ${amountBrl.toStringAsFixed(2)} (${_provider.name})');

    final taxNumber = (payerTaxNumber ?? _payerTaxNumber)?.trim();
    if (taxNumber != null && taxNumber.isNotEmpty) {
      await setPayerTaxNumber(taxNumber);
    }

    String depixAddress;
    try {
      depixAddress = await liquidWalletService.getReceiveAddress();
    } catch (_) {
      depixAddress = 'indisponivel';
    }

    final charge = await _provider.createDeposit(
      amountBrl: amountBrl,
      depixAddress: depixAddress,
      payerTaxNumber: taxNumber,
    );
    activeCharge = charge;
    _log('[PIX] Cobrança criada. Pague o QR/copia-e-cola no seu banco.');
    notifyListeners();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkDeposit());
    return charge;
  }

  Future<void> _checkDeposit() async {
    final charge = activeCharge;
    if (charge == null) return;
    final status = await _provider.getDepositStatus(charge.id);
    if (status == charge.status) return;
    charge.status = status;
    notifyListeners();

    if (status == PixChargeStatus.paid || status == PixChargeStatus.settled) {
      _pollTimer?.cancel();
      _log('[PIX] Pagamento confirmado! DEPIX ${status == PixChargeStatus.settled ? 'entregue' : 'a caminho'} na Liquid.');
      if (_provider.isSimulated) {
        _log('[SWAP] Roteando DEPIX -> L-BTC -> Lightning -> saldo em sats...');
        await swapService.executeFullRouting(charge.amountBrl);
      } else {
        _log('[LIQUID] Aguardando o DEPIX no seu endereço — o saldo em sats '
            'atualiza automaticamente quando chegar.');
        await liquidWalletService.syncWallet();
      }
      _log('[✅] Depósito concluído.');
    } else if (status == PixChargeStatus.expired || status == PixChargeStatus.failed) {
      _pollTimer?.cancel();
      _log('[PIX] Cobrança ${status == PixChargeStatus.expired ? 'expirou' : 'falhou'}.');
    }
  }

  /// Sandbox: confirma o pagamento (local ou via API oficial do provedor).
  Future<void> simulatePaymentReceived() async {
    final charge = activeCharge;
    if (charge == null || !_provider.canSimulate) return;
    try {
      await _provider.simulatePayment(charge.id);
      await _checkDeposit();
    } catch (e) {
      _log('[ERRO] Simulação falhou: $e');
    }
  }

  /// Saque: converte sats em BRL e paga o destino PIX.
  /// [pixTarget] aceita chave PIX ou BR Code completo (a chave é extraída).
  Future<void> startWithdrawal({
    required double amountBrl,
    required String pixTarget,
    String? taxNumber,
  }) async {
    logs.clear();

    String pixKey = pixTarget.trim();
    if (BrCode.looksLikeBrCode(pixKey)) {
      final decoded = BrCode.decode(pixKey);
      pixKey = decoded.pixKey;
      _log('[PIX] BR Code decodificado: ${decoded.merchantName.isNotEmpty ? decoded.merchantName : pixKey}');
    }

    _log('[PIX] Registrando envio de R\$ ${amountBrl.toStringAsFixed(2)} para $pixKey (${_provider.name})');

    final withdrawal = await _provider.createWithdrawal(
      amountBrl: amountBrl,
      pixKey: pixKey,
      taxNumber: taxNumber,
    );
    _log('[PIX] Saque aceito pelo provedor (id ${withdrawal.id}).');

    if (_provider.isSimulated) {
      _log('[SWAP] (simulado) Lightning -> L-BTC -> DEPIX para o provedor.');
      await Future.delayed(const Duration(seconds: 2));
      _log('[PIX] (simulado) Provedor pagou R\$ ${amountBrl.toStringAsFixed(2)} na chave $pixKey.');
      _log('[✅] Saque concluído (nenhum BRL real movido).');
      return;
    }

    // Provedor real: envia L-BTC/DEPIX para o endereço indicado.
    _log('[LIQUID] Enviando fundos para o endereço do provedor...');
    final sats = swapService.exchangeRateService.brlToSats(amountBrl);
    if (sats <= 0) throw Exception('Cotação indisponível.');
    final txid = await liquidWalletService.sendLbtc(
      toAddress: withdrawal.depixAddress,
      sats: sats,
    );
    _log('[LIQUID] Enviado (txid $txid).');

    if (withdrawal.feeAddress != null && withdrawal.feeCents > 0) {
      // O DePix App exige a taxa como saída separada na MESMA transação —
      // o LWK 0.1.7 não constrói multi-saída, então enviamos em transação
      // própria e registramos a limitação para conferência com o provedor.
      final feeSats = swapService.exchangeRateService.brlToSats(withdrawal.feeCents / 100);
      _log('[LIQUID] Enviando taxa do provedor (${withdrawal.feeCents} centavos)...');
      final feeTxid = await liquidWalletService.sendLbtc(
        toAddress: withdrawal.feeAddress!,
        sats: feeSats,
      );
      _log('[LIQUID] Taxa enviada (txid $feeTxid). Obs.: o provedor recomenda '
          'a taxa na mesma transação — confirme a liquidação no dashboard.');
    }

    _log('[✅] Aguarde o provedor liquidar o PIX em BRL.');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

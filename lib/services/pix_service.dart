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
/// Fluxo de depósito:  PIX (BRL) -> provedor emite DEPIX na Liquid para o
/// nosso endereço -> swap DEPIX/L-BTC -> Lightning -> saldo em sats.
/// Fluxo de saque:     sats -> L-BTC -> DEPIX para o provedor -> provedor
/// paga a chave PIX do destinatário em BRL.
///
/// O provedor é plugável:
/// - [SimulatedPixProvider]: testnet/desenvolvimento — não move BRL reais,
///   mas percorre o fluxo completo de estados.
/// - [RestPixProvider]: provedores DEPIX reais (ex.: depix.info) via REST,
///   configurável com URL base + chave de API nas configurações.

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
  PixChargeStatus status;

  PixWithdrawal({
    required this.id,
    required this.amountBrl,
    required this.pixKey,
    required this.depixAddress,
    this.status = PixChargeStatus.pending,
  });
}

abstract class PixProvider {
  String get name;
  bool get isSimulated;

  /// Cria cobrança PIX; o provedor emitirá DEPIX em [depixAddress] ao pagar.
  Future<PixCharge> createDeposit({required double amountBrl, required String depixAddress});

  Future<PixChargeStatus> getDepositStatus(String chargeId);

  /// Registra um saque: o provedor devolve o endereço Liquid que receberá o
  /// DEPIX e pagará [pixKey] em BRL.
  Future<PixWithdrawal> createWithdrawal({required double amountBrl, required String pixKey});
}

/// Provedor simulado (testnet): percorre os estados sem mover BRL.
class SimulatedPixProvider implements PixProvider {
  @override
  String get name => 'Simulado (testnet)';
  @override
  bool get isSimulated => true;

  final Map<String, PixCharge> _charges = {};

  @override
  Future<PixCharge> createDeposit({required double amountBrl, required String depixAddress}) async {
    final id = 'IRIS${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(999)}';
    // BR Code estruturalmente válido (EMV + CRC16 reais) — bancos conseguem
    // decodificar; apenas a chave é de demonstração enquanto não há provedor.
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

  /// No modo simulado o pagamento é confirmado manualmente pela UI.
  void simulatePayment(String chargeId) {
    _charges[chargeId]?.status = PixChargeStatus.paid;
  }

  @override
  Future<PixChargeStatus> getDepositStatus(String chargeId) async {
    return _charges[chargeId]?.status ?? PixChargeStatus.failed;
  }

  @override
  Future<PixWithdrawal> createWithdrawal({required double amountBrl, required String pixKey}) async {
    return PixWithdrawal(
      id: 'simw_${DateTime.now().millisecondsSinceEpoch}',
      amountBrl: amountBrl,
      pixKey: pixKey,
      depixAddress: 'tlq1_endereco_simulado_do_provedor',
    );
  }
}

/// Provedor DEPIX real via REST. Contrato esperado (adaptável por provedor):
///   POST {base}/deposit   {"amount_brl":.., "depix_address":".."}
///     -> {"id":"..","qr_copia_e_cola":".."}
///   GET  {base}/deposit/{id}  -> {"status":"pending|paid|settled|expired"}
///   POST {base}/withdraw  {"amount_brl":.., "pix_key":".."}
///     -> {"id":"..","depix_address":".."}
/// Autenticação: header Authorization: Bearer {apiKey}.
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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  @override
  Future<PixCharge> createDeposit({required double amountBrl, required String depixAddress}) async {
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
  Future<PixWithdrawal> createWithdrawal({required double amountBrl, required String pixKey}) async {
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

/// Orquestra depósitos e saques PIX ponta a ponta.
class PixService extends ChangeNotifier {
  final LiquidWalletService liquidWalletService;
  final SwapService swapService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  PixProvider _provider = SimulatedPixProvider();
  PixProvider get provider => _provider;

  PixCharge? activeCharge;
  Timer? _pollTimer;
  final List<String> logs = [];

  PixService({required this.liquidWalletService, required this.swapService}) {
    _loadProviderConfig();
  }

  void _log(String message) {
    logs.add(message);
    notifyListeners();
  }

  Future<void> _loadProviderConfig() async {
    final url = await _storage.read(key: 'pix_provider_url');
    final key = await _storage.read(key: 'pix_provider_key');
    if (url != null && url.isNotEmpty && key != null && key.isNotEmpty) {
      _provider = RestPixProvider(baseUrl: url, apiKey: key);
      notifyListeners();
    }
  }

  /// Configura provedor DEPIX real (URL + chave). Vazio volta ao simulado.
  Future<void> configureProvider({String? baseUrl, String? apiKey}) async {
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      await _storage.delete(key: 'pix_provider_url');
      await _storage.delete(key: 'pix_provider_key');
      _provider = SimulatedPixProvider();
    } else {
      await _storage.write(key: 'pix_provider_url', value: baseUrl.trim());
      await _storage.write(key: 'pix_provider_key', value: (apiKey ?? '').trim());
      _provider = RestPixProvider(baseUrl: baseUrl.trim(), apiKey: (apiKey ?? '').trim());
    }
    notifyListeners();
  }

  /// Inicia um depósito: gera a cobrança PIX e acompanha até liquidar.
  Future<PixCharge> startDeposit(double amountBrl) async {
    logs.clear();
    _log('[PIX] Gerando cobrança de R\$ ${amountBrl.toStringAsFixed(2)} (${_provider.name})');

    String depixAddress;
    try {
      depixAddress = await liquidWalletService.getReceiveAddress();
    } catch (_) {
      depixAddress = 'indisponivel';
    }

    final charge = await _provider.createDeposit(
      amountBrl: amountBrl,
      depixAddress: depixAddress,
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
      _log('[PIX] Pagamento confirmado! DEPIX emitido na Liquid.');
      _log('[SWAP] Roteando DEPIX -> L-BTC -> Lightning -> saldo em sats...');
      await swapService.executeFullRouting(charge.amountBrl);
      _log('[✅] Depósito concluído. O saldo será creditado pelo evento do nó.');
    } else if (status == PixChargeStatus.expired || status == PixChargeStatus.failed) {
      _pollTimer?.cancel();
      _log('[PIX] Cobrança ${status == PixChargeStatus.expired ? 'expirou' : 'falhou'}.');
    }
  }

  /// Modo simulado: confirma o pagamento do PIX manualmente.
  void simulatePaymentReceived() {
    final p = _provider;
    final charge = activeCharge;
    if (p is SimulatedPixProvider && charge != null) {
      p.simulatePayment(charge.id);
      _checkDeposit();
    }
  }

  /// Saque: converte sats em BRL e paga o destino PIX.
  /// [pixTarget] aceita chave PIX (CPF/e-mail/telefone/aleatória) ou o
  /// copia-e-cola completo (BR Code) — a chave é extraída do código.
  Future<void> startWithdrawal({required double amountBrl, required String pixTarget}) async {
    logs.clear();

    String pixKey = pixTarget.trim();
    if (BrCode.looksLikeBrCode(pixKey)) {
      final decoded = BrCode.decode(pixKey);
      pixKey = decoded.pixKey;
      _log('[PIX] BR Code decodificado: ${decoded.merchantName.isNotEmpty ? decoded.merchantName : pixKey}');
    }

    _log('[PIX] Registrando envio de R\$ ${amountBrl.toStringAsFixed(2)} para $pixKey (${_provider.name})');

    final withdrawal = await _provider.createWithdrawal(amountBrl: amountBrl, pixKey: pixKey);
    _log('[PIX] Saque aceito pelo provedor (id ${withdrawal.id}).');

    if (_provider.isSimulated) {
      _log('[SWAP] (simulado) Lightning -> L-BTC -> DEPIX para o provedor.');
      await Future.delayed(const Duration(seconds: 2));
      _log('[PIX] (simulado) Provedor pagou R\$ ${amountBrl.toStringAsFixed(2)} na chave $pixKey.');
      _log('[✅] Saque concluído (testnet: nenhum BRL real movido).');
      return;
    }

    // Provedor real: envia L-BTC/DEPIX para o endereço do provedor.
    _log('[LIQUID] Enviando fundos para o endereço do provedor...');
    final sats = swapService.exchangeRateService.brlToSats(amountBrl);
    if (sats <= 0) throw Exception('Cotação indisponível.');
    final txid = await liquidWalletService.sendLbtc(
      toAddress: withdrawal.depixAddress,
      sats: sats,
    );
    _log('[LIQUID] Enviado (txid $txid). O provedor liquidará o PIX em BRL.');
    _log('[✅] Aguarde a confirmação do provedor.');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

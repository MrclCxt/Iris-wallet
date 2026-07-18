import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'wallet_service.dart';
import 'liquid_wallet_service.dart';
import 'exchange_rate_service.dart';

/// Roteamento de liquidez BRL (DEPIX/Liquid) -> Lightning via Boltz
/// (Submarine Swap), tudo na testnet.
class SwapService extends ChangeNotifier {
  final WalletService walletService;
  final LiquidWalletService liquidWalletService;
  final ExchangeRateService exchangeRateService;

  SwapService({
    required this.walletService,
    required this.liquidWalletService,
    required this.exchangeRateService,
  });

  final List<String> _swapLogs = [];
  List<String> get swapLogs => _swapLogs;

  void _addLog(String message) {
    _swapLogs.add(message);
    notifyListeners();
  }

  void clearLogs() {
    _swapLogs.clear();
    notifyListeners();
  }

  /// Roteamento completo: BRL -> L-BTC (Liquid) -> Lightning BTC.
  Future<void> executeFullRouting(double brlAmount) async {
    clearLogs();
    _addLog('[+] BRL Depositado via PIX: R\$ ${brlAmount.toStringAsFixed(2)}');

    // Conversão pelo câmbio real (CoinGecko), não por taxa fixa simulada.
    final satsAmount = exchangeRateService.brlToSats(brlAmount);
    if (satsAmount <= 0) {
      _addLog('[ERRO] Cotação BTC/BRL indisponível. Tente novamente em instantes.');
      await exchangeRateService.fetchRate();
      return;
    }
    _addLog('[🔄] Câmbio atual: R\$ ${brlAmount.toStringAsFixed(2)} = $satsAmount sats');

    _addLog('[BOLTZ] Iniciando Submarine Swap: L-BTC -> Lightning...');
    await _executeBoltzSwap(satsAmount);
  }

  Future<void> _executeBoltzSwap(int expectedSats) async {
    try {
      // 1. Gera fatura Lightning real no nó local
      final invoice = await walletService.createInvoice(expectedSats, 'Boltz L-BTC Swap');
      _addLog('[LDK] Fatura de $expectedSats sats gerada internamente.');

      // 2. Chama a API da Boltz Exchange (testnet)
      final url = Uri.parse('https://api.testnet.boltz.exchange/v2/swap/submarine');
      final requestBody = {
        'from': 'L-BTC',
        'to': 'BTC',
        'invoice': invoice,
        'pairId': 'L-BTC/BTC',
        'routingFeeRate': 0,
      };

      _addLog('[BOLTZ] Negociando swap cross-chain...');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final boltzAddress = data['address'] as String?;
        final expectedAmount = (data['expectedAmount'] as num?)?.toInt();

        if (boltzAddress == null || expectedAmount == null) {
          _addLog('[ERRO] Resposta da Boltz sem endereço/valor: ${response.body}');
          return;
        }

        _addLog('[BOLTZ] Swap aceito. Enviando $expectedAmount sats L-BTC para: $boltzAddress');

        // 3. Envia L-BTC de verdade (build + sign + broadcast local)
        final txid = await liquidWalletService.sendLbtc(
          toAddress: boltzAddress,
          sats: expectedAmount,
        );
        _addLog('[LIQUID] Transação transmitida. txid: $txid');

        // 4. A Boltz detecta os fundos e paga a fatura Lightning.
        //    O crédito real chega pelo evento PaymentReceived do LDK.
        _addLog('[BOLTZ] Aguardando a Boltz liquidar a fatura Lightning...');
        _addLog('[ℹ️] O saldo será creditado automaticamente quando o pagamento chegar no nó.');
      } else {
        _addLog('[ERRO] Boltz API falhou: ${response.body}');
      }
    } catch (e) {
      _addLog('[ERRO] Falha no roteamento Boltz: $e');
    }
  }
}

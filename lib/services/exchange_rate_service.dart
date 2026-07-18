import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExchangeRateService extends ChangeNotifier {
  double _btcToBrlRate = 0.0;
  bool _isLoading = false;
  bool _isSatsDisplay = false;

  double get btcToBrlRate => _btcToBrlRate;
  bool get isLoading => _isLoading;
  bool get isSatsDisplay => _isSatsDisplay;

  void toggleCurrencyDisplay() {
    _isSatsDisplay = !_isSatsDisplay;
    notifyListeners();
  }

  Future<void> fetchRate() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Usando a API pública do CoinGecko (sem chaves, mantendo anonimidade)
      final url = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=brl');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _btcToBrlRate = (data['bitcoin']['brl'] as num).toDouble();
        debugPrint('Cotação BTC/BRL atualizada: R\$ $_btcToBrlRate');
      } else {
        debugPrint('Falha ao buscar cotação, status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erro ao buscar cotação BTC/BRL: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Converte um valor em Reais (BRL) para Satoshis (Sats)
  int brlToSats(double brlAmount) {
    if (_btcToBrlRate <= 0) return 0; // Fallback se a cotação falhar
    // 1 Bitcoin = 100,000,000 Sats
    double btcAmount = brlAmount / _btcToBrlRate;
    return (btcAmount * 100000000).round();
  }

  // Converte Satoshis (Sats) para Reais (BRL)
  double satsToBrl(int satsAmount) {
    if (_btcToBrlRate <= 0) return 0.0;
    double btcAmount = satsAmount / 100000000;
    return btcAmount * _btcToBrlRate;
  }
}

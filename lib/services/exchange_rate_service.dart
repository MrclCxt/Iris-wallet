import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService extends ChangeNotifier {
  double _btcToBrlRate = 0.0;
  bool _isLoading = false;
  bool _isSatsDisplay = false;
  Timer? _refreshTimer;

  double get btcToBrlRate => _btcToBrlRate;
  bool get isLoading => _isLoading;
  bool get isSatsDisplay => _isSatsDisplay;

  /// Cotação disponível e utilizável para gerar cobranças.
  bool get hasRate => _btcToBrlRate > 0;

  /// Busca imediata + atualização periódica (motor de conversão em tempo real).
  void startAutoRefresh({Duration interval = const Duration(seconds: 60)}) {
    loadDisplayPref();
    fetchRate();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) => fetchRate());
  }

  /// Carrega a preferência de moeda de exibição (persistida entre sessões).
  Future<void> loadDisplayPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isSatsDisplay = prefs.getBool('display_sats') ?? false;
      notifyListeners();
    } catch (_) {
      // Sem plugin (ex.: ambiente de teste): mantém o padrão em memória.
    }
  }

  Future<void> _persistDisplay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('display_sats', _isSatsDisplay);
    } catch (_) {
      // Persistência indisponível: não é fatal para a exibição.
    }
  }

  /// Define a moeda de exibição explicitamente (Perfil) e persiste.
  void setSatsDisplay(bool sats) {
    _isSatsDisplay = sats;
    _persistDisplay();
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void toggleCurrencyDisplay() {
    _isSatsDisplay = !_isSatsDisplay;
    _persistDisplay();
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

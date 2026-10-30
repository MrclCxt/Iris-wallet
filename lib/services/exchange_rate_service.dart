import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/cotacao.dart';

class _FonteCotacao {
  final String nome;
  final Uri url;
  final double Function(dynamic json) extrair;
  const _FonteCotacao(this.nome, this.url, this.extrair);
}

class ExchangeRateService extends ChangeNotifier {
  static const Duration validadeCotacao = Duration(minutes: 10);

  static final List<_FonteCotacao> _fontes = [
    _FonteCotacao(
      'CoinGecko',
      Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=brl'),
      (j) => (j['bitcoin']['brl'] as num).toDouble(),
    ),
    _FonteCotacao(
      'Binance',
      Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL'),
      (j) => double.parse(j['price'] as String),
    ),
    _FonteCotacao(
      'Mercado Bitcoin',
      Uri.parse(
          'https://api.mercadobitcoin.net/api/v4/tickers?symbols=BTC-BRL'),
      (j) => double.parse((j as List).first['last'] as String),
    ),
  ];

  double _btcToBrlRate = 0.0;
  DateTime? _confirmadaEm;
  bool _isLoading = false;
  bool _isSatsDisplay = false;
  bool _cotacaoLigada = true;
  Timer? _refreshTimer;

  double get btcToBrlRate => _btcToBrlRate;
  bool get isLoading => _isLoading;
  bool get isSatsDisplay => _isSatsDisplay;

  /// Desligada, o app não consulta nenhuma API de preço: ninguém fica sabendo
  /// que este IP usa Bitcoin. Sem cotação, valores em Real não são convertidos.
  bool get cotacaoLigada => _cotacaoLigada;

  /// Sem consenso recente entre as fontes, a última cotação continua servindo
  /// para exibir valores, mas não para converter Real em sats numa cobrança.
  bool get cotacaoIncerta =>
      _confirmadaEm == null ||
      DateTime.now().difference(_confirmadaEm!) > validadeCotacao;

  bool get hasRate => _btcToBrlRate > 0 && !cotacaoIncerta;

  void startAutoRefresh({Duration interval = const Duration(seconds: 60)}) {
    loadDisplayPref().then((_) => fetchRate());
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) => fetchRate());
    WidgetsBinding.instance.addObserver(_RetomadaCotacao(this));
  }

  void atualizarAgora() => fetchRate();

  Future<void> loadDisplayPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isSatsDisplay = prefs.getBool('display_sats') ?? false;
      _cotacaoLigada = prefs.getBool('cotacao_ligada') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistDisplay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('display_sats', _isSatsDisplay);
    } catch (_) {}
  }

  Future<void> setCotacaoLigada(bool ligada) async {
    _cotacaoLigada = ligada;
    if (!ligada) {
      _btcToBrlRate = 0;
      _confirmadaEm = null;
      _isSatsDisplay = true;
      _persistDisplay();
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cotacao_ligada', ligada);
    } catch (_) {}
    if (ligada) fetchRate();
  }

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
    if (!_cotacaoLigada) return;
    _isLoading = true;
    notifyListeners();

    try {
      final cotacoes = await Future.wait(_fontes.map(_consultar));
      final consenso =
          cotacaoDeConsenso(cotacoes.whereType<double>().toList());
      final detalhe = [
        for (var i = 0; i < _fontes.length; i++)
          '${_fontes[i].nome}=${cotacoes[i]?.toStringAsFixed(0) ?? 'falhou'}'
      ].join(' ');
      if (consenso != null) {
        _btcToBrlRate = consenso;
        _confirmadaEm = DateTime.now();
        debugPrint('Cotação BTC/BRL: R\$ ${consenso.toStringAsFixed(0)} '
            '(mediana; $detalhe)');
      } else {
        debugPrint('Cotação BTC/BRL sem consenso, mantendo a anterior ($detalhe)');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<double?> _consultar(_FonteCotacao fonte) async {
    try {
      final r =
          await http.get(fonte.url).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return fonte.extrair(json.decode(r.body));
    } catch (_) {
      return null;
    }
  }

  int brlToSats(double brlAmount) {
    if (!hasRate) return 0;

    double btcAmount = brlAmount / _btcToBrlRate;
    return (btcAmount * 100000000).round();
  }

  double satsToBrl(int satsAmount) {
    if (_btcToBrlRate <= 0) return 0.0;
    double btcAmount = satsAmount / 100000000;
    return btcAmount * _btcToBrlRate;
  }
}

class _RetomadaCotacao extends WidgetsBindingObserver {
  final ExchangeRateService _servico;
  _RetomadaCotacao(this._servico);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _servico.atualizarAgora();
  }
}

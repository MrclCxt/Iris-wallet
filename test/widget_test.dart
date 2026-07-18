// Testes do motor de conversão BRL <-> Sats (requisito: motor de conversão
// em tempo real com Satoshi como unidade de conta interna e paridade em BRL).

import 'package:flutter_test/flutter_test.dart';

import 'package:iris_wallet/services/exchange_rate_service.dart';

void main() {
  group('ExchangeRateService conversões', () {
    test('conversões retornam 0 como fallback sem cotação carregada', () {
      final service = ExchangeRateService();
      expect(service.brlToSats(100.0), 0);
      expect(service.satsToBrl(100000), 0.0);
    });

    test('toggleCurrencyDisplay alterna entre BRL e Sats', () {
      final service = ExchangeRateService();
      expect(service.isSatsDisplay, false);
      service.toggleCurrencyDisplay();
      expect(service.isSatsDisplay, true);
      service.toggleCurrencyDisplay();
      expect(service.isSatsDisplay, false);
    });
  });
}

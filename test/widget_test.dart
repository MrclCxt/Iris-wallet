// Testes dos componentes centrais dos requisitos:
// - Parser BOLT11 (QR dinâmico Lightning)
// - LNURL / Lightning Address (LUD-06 / LUD-16)
// - Motor de conversão BRL <-> Sats

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris_wallet/core/bolt11.dart';
import 'package:iris_wallet/core/lnurl.dart';
import 'package:iris_wallet/services/exchange_rate_service.dart';

// ---- helpers bech32 (encoder usado apenas nos testes) ----

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const _gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

int _polymod(List<int> values) {
  int chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (int i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= _gen[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) => [
      ...hrp.codeUnits.map((c) => c >> 5),
      0,
      ...hrp.codeUnits.map((c) => c & 31),
    ];

String bech32Encode(String hrp, List<int> data) {
  final poly = _polymod([..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [for (int i = 0; i < 6; i++) (poly >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...data, ...checksum].map((v) => _charset[v]).join()}';
}

List<int> to5bit(List<int> bytes) {
  int acc = 0, bits = 0;
  final out = <int>[];
  for (final b in bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.add((acc >> bits) & 31);
    }
  }
  if (bits > 0) out.add((acc << (5 - bits)) & 31);
  return out;
}

/// Monta uma fatura BOLT11 sintática e estruturalmente válida
/// (assinatura zerada — suficiente para testar o decoder).
String buildTestInvoice({
  required String hrp,
  required String description,
  int expirySecs = 7200,
}) {
  const ts = 1700000000;
  final tsGroups = [for (int i = 6; i >= 0; i--) (ts >> (5 * i)) & 31];

  final hashBytes = List<int>.filled(32, 0x01);
  final pGroups = to5bit(hashBytes); // 52 grupos
  final pField = [1, pGroups.length ~/ 32, pGroups.length % 32, ...pGroups];

  final dGroups = to5bit(utf8.encode(description));
  final dField = [13, dGroups.length ~/ 32, dGroups.length % 32, ...dGroups];

  final xGroups = <int>[];
  var e = expirySecs;
  while (e > 0) {
    xGroups.insert(0, e % 32);
    e ~/= 32;
  }
  final xField = [6, xGroups.length ~/ 32, xGroups.length % 32, ...xGroups];

  final signature = List<int>.filled(104, 0);

  return bech32Encode(hrp, [...tsGroups, ...pField, ...dField, ...xField, ...signature]);
}

void main() {
  group('Bolt11 parser', () {
    test('decodifica fatura testnet com valor, descrição, hash e expiração', () {
      final invoice = buildTestInvoice(hrp: 'lntb10u', description: 'Cafe teste');
      final parsed = Bolt11.decode(invoice);

      expect(parsed.network, 'tb');
      expect(parsed.isTestnet, true);
      expect(parsed.amountSats, 1000); // 10u = 10 micro-BTC = 1000 sats
      expect(parsed.description, 'Cafe teste');
      expect(parsed.paymentHashHex, '01' * 32);
      expect(parsed.expiry, const Duration(seconds: 7200));
    });

    test('fatura sem valor retorna amountSats null (valor aberto)', () {
      final invoice = buildTestInvoice(hrp: 'lntb', description: 'Valor aberto');
      final parsed = Bolt11.decode(invoice);
      expect(parsed.amountSats, isNull);
    });

    test('multiplicadores de valor (m/u/n) convertem corretamente', () {
      expect(Bolt11.decode(buildTestInvoice(hrp: 'lntb1m', description: 'x')).amountSats,
          100000); // 1 mili-BTC
      expect(Bolt11.decode(buildTestInvoice(hrp: 'lntb2500u', description: 'x')).amountSats,
          250000); // 2500 micro-BTC
      expect(Bolt11.decode(buildTestInvoice(hrp: 'lntb250n', description: 'x')).amountSats,
          25); // 250 nano-BTC
    });

    test('detecta rede mainnet vs testnet', () {
      final mainnet = Bolt11.decode(buildTestInvoice(hrp: 'lnbc1m', description: 'x'));
      expect(mainnet.isTestnet, false);
    });

    test('rejeita fatura com checksum corrompido', () {
      final invoice = buildTestInvoice(hrp: 'lntb10u', description: 'x');
      final corrupted =
          invoice.substring(0, invoice.length - 1) +
              (invoice.endsWith('q') ? 'p' : 'q');
      expect(() => Bolt11.decode(corrupted), throwsA(isA<Bolt11ParseException>()));
    });

    test('looksLikeInvoice reconhece prefixos válidos', () {
      expect(Bolt11.looksLikeInvoice(buildTestInvoice(hrp: 'lntb10u', description: 'x')), true);
      expect(Bolt11.looksLikeInvoice('naoehfatura'), false);
      expect(Bolt11.looksLikeInvoice('user@site.com'), false);
    });
  });

  group('LNURL / Lightning Address', () {
    test('decodifica LNURL bech32 para URL', () {
      const url = 'https://exemplo.com/lnurlp/maria';
      final lnurl = bech32Encode('lnurl', to5bit(utf8.encode(url)));
      expect(Lnurl.looksLikeLnurl(lnurl), true);
      expect(Lnurl.resolveUrl(lnurl), url);
    });

    test('resolve Lightning Address (LUD-16)', () {
      expect(Lnurl.looksLikeLnurl('maria@exemplo.com'), true);
      expect(Lnurl.resolveUrl('maria@exemplo.com'),
          'https://exemplo.com/.well-known/lnurlp/maria');
    });

    test('remove prefixo lightning: antes de resolver', () {
      expect(Lnurl.resolveUrl('lightning:maria@exemplo.com'),
          'https://exemplo.com/.well-known/lnurlp/maria');
    });

    test('metadata text/plain vira descrição', () {
      final params = LnurlPayParams(
        callback: 'https://exemplo.com/cb',
        minSendableMsat: 1000,
        maxSendableMsat: 5000000,
        metadata: '[["text/plain","Doação para a Maria"]]',
        domain: 'exemplo.com',
      );
      expect(params.description, 'Doação para a Maria');
      expect(params.minSendableSats, 1);
      expect(params.maxSendableSats, 5000);
      expect(params.isFixedAmount, false);
    });
  });

  group('ExchangeRateService conversões', () {
    test('conversões retornam 0 como fallback sem cotação carregada', () {
      final service = ExchangeRateService();
      expect(service.hasRate, false);
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

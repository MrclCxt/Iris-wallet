import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/bip21.dart';

/// O QR unificado tem de ser lido de volta pelas carteiras: endereço no
/// caminho, valor em BTC e a fatura no parâmetro `lightning`.
void main() {
  const endereco = 'tb1qknalcxsytxw8te4q7955932ft8cyeu3aljclg6';
  const fatura = 'lntb10u1p4w87h6dq5w3jhxar9ypjxzetddahq';

  test('com valor', () {
    final uri = Uri.parse(
        bip21Unificado(endereco: endereco, fatura: fatura, sats: 1000));
    expect(uri.scheme, 'bitcoin');
    expect(uri.path, endereco);
    expect(uri.queryParameters['amount'], '0.00001000');
    expect(uri.queryParameters['lightning'], fatura);
  });

  test('sem valor (cobrança aberta)', () {
    final s = bip21Unificado(endereco: endereco, fatura: fatura);
    expect(s, 'bitcoin:$endereco?lightning=$fatura');
  });
}

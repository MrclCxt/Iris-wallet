import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/esplora_servidores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrato da lista de servidores Esplora: os do usuário entram na frente,
/// sem duplicar os do padrão, e o padrão nunca depende de um só operador.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normaliza barras no fim', () {
    expect(EsploraServidores.normalizar(' https://x.io/api// '),
        'https://x.io/api');
  });

  test('aceita só http(s) com host', () {
    expect(EsploraServidores.formatoValido('https://x.io/api'), isTrue);
    expect(EsploraServidores.formatoValido('http://192.168.0.5:3002'), isTrue);
    expect(EsploraServidores.formatoValido('ftp://x.io'), isFalse);
    expect(EsploraServidores.formatoValido('x.io/api'), isFalse);
  });

  test('padrão tem mais de um operador', () {
    final hosts =
        EsploraServidores.padrao.map((u) => Uri.parse(u).host).toSet();
    expect(hosts.any((h) => h.contains('mempool.space')), isTrue);
    expect(hosts.any((h) => h.contains('blockstream.info')), isTrue);
  });

  test('servidores do usuário vêm primeiro e sem duplicar', () async {
    await EsploraServidores.salvarPersonalizados([
      'https://meu.no/api/',
      EsploraServidores.padrao.first,
    ]);
    final c = await EsploraServidores.candidatos();
    expect(c.first, 'https://meu.no/api');
    expect(c.where((u) => u == EsploraServidores.padrao.first).length, 1);
    expect(c.length, EsploraServidores.padrao.length + 1);
  });
}

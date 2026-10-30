import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iris_wallet/core/rede.dart';
import 'package:iris_wallet/services/node_backend.dart';

/// Contrato entre o app e o iris-noded: as respostas abaixo são as que o
/// daemon devolve de verdade (copiadas de uma execução na testnet4).
void main() {
  RemoteNodeApi api(Map<String, Object> rotas) => RemoteNodeApi(
        'http://127.0.0.1:8380',
        token: 'tok',
        client: MockClient((req) async {
          if (req.headers['X-Iris-Token'] != 'tok') {
            return http.Response('{"error":"token"}', 401);
          }
          final corpo = rotas[req.url.path];
          if (corpo == null) return http.Response('{"error":"rota"}', 500);
          return http.Response(jsonEncode(corpo), 200);
        }),
      );

  test('aceita daemon da mesma rede do build', () async {
    await api({
      '/health': {'status': 'ok', 'network': Rede.nome}
    }).start();
  });

  test('recusa daemon de outra rede', () async {
    const outra = Rede.principal ? 'testnet4' : 'bitcoin';
    expect(
        api({
          '/health': {'status': 'ok', 'network': outra}
        }).start(),
        throwsException);
  });

  test('recusa daemon antigo, que não informa a rede', () async {
    expect(api({'/health': {'status': 'ok'}}).start(), throwsException);
  });

  test('histórico vem do daemon, não vazio', () async {
    final lista = await api({
      '/payments': {
        'payments': [
          {
            'amount_sats': 21000,
            'id':
                '3f4f7e39ca83a69f58ef3732df4bb9234f309efffd650a91f6da8773957b79d8',
            'incoming': true,
            'onchain': false,
            'status': 'pending',
            'timestamp': 1793325818,
          }
        ]
      }
    }).listPayments();
    expect(lista, hasLength(1));
    expect(lista.single.amountSats, 21000);
    expect(lista.single.isIncoming, isTrue);
    expect(lista.single.isOnchain, isFalse);
    expect(lista.single.date.millisecondsSinceEpoch, 1793325818000);
  });

  test('offer indisponível vira null, não exceção', () async {
    expect(await api({}).createOffer(description: 'x'), isNull);
  });
}

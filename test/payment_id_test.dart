import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/node_backend.dart';

void main() {
  const txidReal =
      '4c3d71019a8226e7dbea0ebb7593f75c989e41df37b993390cbe6a225acd638d';

  const bytesDoNo = [
    141, 99, 205, 90, 34, 106, 190, 12, 57, 147, 185, 55, 223, 65, 158, 152, //
    92, 247, 147, 117, 187, 14, 234, 219, 231, 38, 130, 154, 1, 113, 61, 76
  ];

  group('id de pagamento on-chain', () {
    test('lista de bytes crua vira o txid de exibição', () {
      expect(EmbeddedNodeApi.idDePagamentoParaTeste(bytesDoNo, true), txidReal);
    });

    test('lista de bytes em forma de texto também', () {
      expect(
        EmbeddedNodeApi.idDePagamentoParaTeste(bytesDoNo.toString(), true),
        txidReal,
      );
    });

    test('hex na ordem interna é invertido para exibição', () {
      final interno = bytesDoNo
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(EmbeddedNodeApi.idDePagamentoParaTeste(interno, true), txidReal);
    });

    test('as três formas convergem para o MESMO id', () {
      final a = EmbeddedNodeApi.idDePagamentoParaTeste(bytesDoNo, true);
      final b =
          EmbeddedNodeApi.idDePagamentoParaTeste(bytesDoNo.toString(), true);
      final c = EmbeddedNodeApi.idDePagamentoParaTeste(
          bytesDoNo.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
          true);
      expect(a, b);
      expect(b, c);
    });
  });

  group('id Lightning não é invertido', () {
    test('mantém a ordem original', () {
      final r = EmbeddedNodeApi.idDePagamentoParaTeste(bytesDoNo, false);
      expect(r, isNot(txidReal));
      expect(
        r,
        bytesDoNo.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
    });
  });

  group('entradas estranhas não quebram', () {
    test('texto qualquer volta como veio', () {
      expect(EmbeddedNodeApi.idDePagamentoParaTeste('abc', true), 'abc');
    });

    test('lista malformada volta como veio', () {
      expect(
        EmbeddedNodeApi.idDePagamentoParaTeste('[1, 2, xyz]', true),
        '[1, 2, xyz]',
      );
    });

    test('lista com tamanho diferente de 32 não é invertida', () {
      final r = EmbeddedNodeApi.idDePagamentoParaTeste([1, 2, 3], true);
      expect(r, '010203');
    });
  });
}

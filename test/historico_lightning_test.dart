import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/node_backend.dart';
import 'package:iris_wallet/services/wallet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recebimentos Lightning no histórico: cobrança não paga não é movimentação,
/// e o mesmo recebimento nunca é anunciado duas vezes — nem depois de o app
/// reiniciar.
void main() {
  PaymentRecord registro(String id, String status,
          {bool entrada = true, bool onchain = false}) =>
      PaymentRecord(
        id: id,
        amountSats: 311,
        isIncoming: entrada,
        status: status,
        date: DateTime(2026, 9, 11),
        isOnchain: onchain,
      );

  Transaction linha(String id, String status, {String emoji = '⚡'}) =>
      Transaction(
        id: id,
        title: 'Recebido via Lightning',
        emoji: emoji,
        amountSats: 311,
        isIncoming: true,
        date: DateTime(2026, 9, 11),
        status: status,
      );

  final h1 = 'a' * 64, h2 = 'b' * 64, h3 = 'c' * 64;

  group('cobrança Lightning não paga', () {
    test('é reconhecida: entrada Lightning que o nó não marcou como paga', () {
      expect(WalletService.ehCobrancaLightningNaoPaga(registro(h1, 'pending')), isTrue);
      expect(WalletService.ehCobrancaLightningNaoPaga(registro(h1, 'failed')), isTrue);
      expect(WalletService.ehCobrancaLightningNaoPaga(registro(h1, 'confirmed')), isFalse);
      expect(
          WalletService.ehCobrancaLightningNaoPaga(
              registro(h1, 'pending', onchain: true)),
          isFalse,
          reason: 'on-chain pendente é dinheiro a caminho de verdade');
      expect(
          WalletService.ehCobrancaLightningNaoPaga(
              registro(h1, 'pending', entrada: false)),
          isFalse,
          reason: 'envio pendente continua aparecendo');
    });

    test('a linha "aguardando confirmação" de 11/09 sai do histórico', () {
      final lista = [linha(h1, 'pending'), linha(h2, 'confirmed'), linha(h3, 'pending')];
      final saiu = WalletService.removerCobrancasNaoPagas(
          lista, [registro(h1, 'pending'), registro(h2, 'confirmed')],
          agora: DateTime(2026, 9, 11, 12));
      expect(saiu, 1);
      expect(lista.map((t) => t.id), [h2, h3],
          reason: 'só sai o que o nó diz não pago; o recente que ele não '
              'conhece ainda fica');
    });

    test('pendente há mais de 24 h que o nó nem conhece também sai', () {
      final hoje = DateTime(2026, 10, 30);
      final lista = [
        linha(h1, 'pending'), // 11/09, nó não conhece (pasta antiga)
        Transaction(
            id: h2,
            title: 'Recebido via Lightning',
            emoji: '⚡',
            amountSats: 10,
            isIncoming: true,
            date: hoje.subtract(const Duration(hours: 2)),
            status: 'pending'),
      ];
      WalletService.removerCobrancasNaoPagas(lista, const [], agora: hoje);
      expect(lista.map((t) => t.id), [h2],
          reason: 'recente fica (pode estar chegando); a de 11/09 sai');
    });

    test('nunca apaga recebimento confirmado nem on-chain', () {
      final lista = [linha(h1, 'confirmed'), linha(h2, 'pending', emoji: '₿')];
      WalletService.removerCobrancasNaoPagas(
          lista, [registro(h1, 'pending'), registro(h2, 'pending')]);
      expect(lista, hasLength(2));
    });
  });

  test('pagamento que chega confirma a linha existente', () {
    final lista = [linha(h1, 'pending')];
    expect(WalletService.confirmarRecebimentoExistente(lista, h1), isTrue);
    expect(lista.single.status, 'confirmed');
    expect(WalletService.confirmarRecebimentoExistente(lista, h2), isFalse);
  });

  group('anúncio de recebimento', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a mesma fase só é anunciada uma vez', () async {
      final a = RecebimentosAnunciados();
      expect(await a.registrar('$h1:recebido'), isTrue);
      expect(await a.registrar('$h1:recebido'), isFalse);
      expect(await a.registrar('$h2:recebido'), isTrue);
    });

    test('depois de reiniciar o app, não anuncia de novo', () async {
      expect(await RecebimentosAnunciados().registrar('$h1:recebido'), isTrue);
      // Nova instância = app reaberto; o nó reentrega o mesmo evento.
      expect(await RecebimentosAnunciados().registrar('$h1:recebido'), isFalse);
    });

    test('dois anúncios simultâneos na abertura viram um só', () async {
      final a = RecebimentosAnunciados();
      final r = await Future.wait(
          [a.registrar('$h3:recebido'), a.registrar('$h3:recebido')]);
      expect(r.where((x) => x), hasLength(1));
    });
  });
}

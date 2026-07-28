import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/services/wallet_service.dart';

/// Contrato de quando um zero lido do nó pode substituir o saldo já conhecido.
///
/// Sintoma que originou estes testes: o app mostrava o saldo real antes de
/// sincronizar e zerava todas as carteiras depois, com o dinheiro confirmado
/// na cadeia. O sync incremental só confere os índices de endereço que o
/// aparelho já revelou, então ele repetia zero indefinidamente — e a regra
/// antiga, baseada em contar leituras zeradas seguidas, acabava aceitando.
void main() {
  test('sem saldo conhecido, zero passa direto (carteira nova)', () {
    expect(
      zeroPodeApagarSaldoDaTela(
        tinhaSaldoConhecido: false,
        aposVarreduraCompleta: false,
        houveSaidaRegistrada: false,
      ),
      isTrue,
    );
  });

  test('sync incremental zerado contra saldo conhecido NÃO apaga a tela', () {
    expect(
      zeroPodeApagarSaldoDaTela(
        tinhaSaldoConhecido: true,
        aposVarreduraCompleta: false,
        houveSaidaRegistrada: false,
      ),
      isFalse,
    );
  });

  test('repetir a leitura incremental não muda nada — o zero segue suspeito',
      () {
    for (var leitura = 1; leitura <= 10; leitura++) {
      expect(
        zeroPodeApagarSaldoDaTela(
          tinhaSaldoConhecido: true,
          aposVarreduraCompleta: false,
          houveSaidaRegistrada: false,
        ),
        isFalse,
        reason: 'leitura $leitura não deveria autorizar o zero',
      );
    }
  });

  test('varredura completa bem-sucedida autoriza o zero', () {
    expect(
      zeroPodeApagarSaldoDaTela(
        tinhaSaldoConhecido: true,
        aposVarreduraCompleta: true,
        houveSaidaRegistrada: false,
      ),
      isTrue,
    );
  });

  test('envio registrado pelo app autoriza o zero sem varredura', () {
    expect(
      zeroPodeApagarSaldoDaTela(
        tinhaSaldoConhecido: true,
        aposVarreduraCompleta: false,
        houveSaidaRegistrada: true,
      ),
      isTrue,
    );
  });

  test('gastar tudo e depois varrer continua zerando (sem saldo fantasma)', () {
    expect(
      zeroPodeApagarSaldoDaTela(
        tinhaSaldoConhecido: true,
        aposVarreduraCompleta: true,
        houveSaidaRegistrada: true,
      ),
      isTrue,
    );
  });
}

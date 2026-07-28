import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrato do "último saldo salvo": o app grava o saldo verificado e, enquanto
/// o nó não está pronto (boot, troca de conta, reinício por sync degradado),
/// mostra esse valor em vez de zero.
///
/// O formato gravado é `total:spendable:lightning` sob a chave
/// `last_balance_tn4_<fingerprint-da-seed>` — ver `WalletService`.
void main() {
  const fp = 'b0f7554713b2fb94';
  const chave = 'last_balance_tn4_$fp';

  ({int total, int spendable, int lightning})? ler(String? raw) {
    if (raw == null) return null;
    final p = raw.split(':');
    if (p.length != 3) return null;
    return (
      total: int.parse(p[0]),
      spendable: int.parse(p[1]),
      lightning: int.parse(p[2]),
    );
  }

  String gravar(int total, int spendable, int lightning) =>
      '$total:$spendable:$lightning';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('grava e recupera o saldo verificado', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chave, gravar(297431, 0, 1500));

    final r = ler(prefs.getString(chave));
    expect(r, isNotNull);
    expect(r!.total, 297431);
    expect(r.spendable, 0); // ainda no mempool
    expect(r.lightning, 1500);
  });

  test('sem gravação anterior devolve null (não inventa saldo)', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(ler(prefs.getString(chave)), isNull);
  });

  test('cada semente tem seu próprio saldo salvo', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_balance_tn4_aaa', gravar(1000, 1000, 0));
    await prefs.setString('last_balance_tn4_bbb', gravar(50, 50, 0));

    expect(ler(prefs.getString('last_balance_tn4_aaa'))!.total, 1000);
    expect(ler(prefs.getString('last_balance_tn4_bbb'))!.total, 50);
  });

  test('uma leitura nova sobrescreve a anterior', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chave, gravar(1000, 1000, 0));
    // Chegou depósito e o sync confirmou um valor maior.
    await prefs.setString(chave, gravar(298431, 1000, 0));

    expect(ler(prefs.getString(chave))!.total, 298431);
  });

  test('valor corrompido devolve null em vez de explodir', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chave, 'lixo');
    expect(ler(prefs.getString(chave)), isNull);
  });
}

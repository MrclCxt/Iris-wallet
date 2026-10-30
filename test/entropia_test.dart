import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris_wallet/core/entropia.dart';

/// A semente nova não pode ser previsível, repetível nem enviesada.
///
/// Qui-quadrado por byte com 255 graus de liberdade: o limite 330,5
/// corresponde a p = 0,001 (gerador honesto passa em 99,9% das execuções).
const double limiteQui = 330.5;

double quiQuadrado(List<int> contagem) {
  final total = contagem.fold<int>(0, (a, b) => a + b);
  final esperado = total / 256;
  return contagem.fold<double>(0, (a, c) => a + (c - esperado) * (c - esperado) / esperado);
}

List<int> contarBytes(Iterable<List<int>> amostras) {
  final c = List<int>.filled(256, 0);
  for (final a in amostras) {
    for (final b in a) {
      c[b]++;
    }
  }
  return c;
}

List<int> entropiaDe(String frase) {
  final hex = bip39.mnemonicToEntropy(frase);
  return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

void main() {
  test('o gerador antigo (bip39 1.0.6) tem o defeito: 0xFF nunca sai', () {
    // Prova de que o problema era real, não teórico.
    final frases = List.generate(3000, (_) => bip39.generateMnemonic());
    final c = contarBytes(frases.map(entropiaDe));
    expect(c[255], 0, reason: 'nextInt(255) nunca sorteia 255');
  });

  test('10.000 sementes novas: sem viés, com 0xFF, sem repetição', () {
    final frases = List.generate(10000, (_) => Entropia.mnemonica());
    expect(frases.toSet().length, 10000, reason: 'nenhuma semente repetida');
    final c = contarBytes(frases.map(entropiaDe));
    expect(c[255], greaterThan(0), reason: 'o byte 0xFF aparece');
    expect(c.every((x) => x > 0), isTrue, reason: 'todos os 256 valores aparecem');
    expect(quiQuadrado(c), lessThan(limiteQui));
    for (final f in frases.take(200)) {
      expect(bip39.validateMnemonic(f), isTrue);
    }
  });

  test('24 palavras também sem viés', () {
    final frases = List.generate(3000, (_) => Entropia.mnemonica(palavras: 24));
    expect(frases.first.split(' '), hasLength(24));
    expect(frases.toSet().length, 3000);
    expect(quiQuadrado(contarBytes(frases.map(entropiaDe))), lessThan(limiteQui));
  });

  test('os bytes do sistema cobrem 0 a 255 sem viés', () {
    final c = contarBytes([Entropia.doSistema(256 * 600)]);
    expect(quiQuadrado(c), lessThan(limiteQui));
  });

  test('dados/moeda só SOMAM: a entropia do sistema sempre entra', () {
    // Mesmos dados, gerador do sistema diferente → sementes diferentes:
    // quem conhece as jogadas não consegue prever a semente.
    final a = Entropia.mnemonica(doUsuario: '3,6,1,4,2,5');
    final b = Entropia.mnemonica(doUsuario: '3,6,1,4,2,5');
    expect(a, isNot(b));
    // Com o gerador fixado (só em teste), mudar os dados muda a semente.
    final x = Entropia.mnemonica(doUsuario: '1111', gerador: Random(7));
    final y = Entropia.mnemonica(doUsuario: '1112', gerador: Random(7));
    expect(x, isNot(y));
    // Separadores não importam; só os símbolos de dado/moeda.
    final z = Entropia.mnemonica(doUsuario: '1 1 1 1', gerador: Random(7));
    expect(z, x);
  });

  test('vetores oficiais BIP39 (Trezor) na conversão entropia → palavras', () {
    String h(int b, int n) => List.filled(n, b.toRadixString(16).padLeft(2, '0')).join();
    expect(bip39.entropyToMnemonic(h(0x00, 16)),
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about');
    expect(bip39.entropyToMnemonic(h(0x7f, 16)),
        'legal winner thank year wave sausage worth useful legal winner thank yellow');
    expect(bip39.entropyToMnemonic(h(0x80, 16)),
        'letter advice cage absurd amount doctor acoustic avoid letter advice cage above');
    expect(bip39.entropyToMnemonic(h(0xff, 16)),
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong');
    expect(bip39.entropyToMnemonic(h(0xff, 32)),
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote');
  });

  test('bits que dados e moeda acrescentam (informativo)', () {
    expect(Entropia.bitsDoUsuario('123456'), closeTo(15.5, 0.01));
    expect(Entropia.bitsDoUsuario('CKCK'), 4);
    expect(Entropia.gerar(16), isA<Uint8List>());
  });
}

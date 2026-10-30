import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';

/// Entropia da semente, feita para não repetir os erros que custaram fundos
/// reais em outras carteiras:
///
/// - Milk Sad (Libbitcoin `bx seed`, 2023): gerador Mersenne Twister semeado
///   com 32 bits do relógio — 2^32 sementes possíveis, varridas em horas.
/// - Randstorm (BitcoinJS e derivados, 2011–2015): `Math.random()` do
///   navegador, sem garantia criptográfica.
/// - Trust Wallet (2023): mesma família do Milk Sad, MT19937 com semente de
///   32 bits.
/// - E o defeito do próprio pacote bip39 que a Iris usava (1.0.6):
///   `Random.secure().nextInt(255)` sorteia de 0 a 254 — o byte 0xFF nunca
///   sai. Viés pequeno (≈0,1 bit em 128), mas real e detectável.
///
/// Regras daqui:
/// 1. A base é SEMPRE o gerador criptográfico do sistema operacional
///    (`Random.secure()`: /dev/urandom, BCryptGenRandom, SecRandomCopyBytes),
///    sorteando o byte inteiro (`nextInt(256)`), sem viés.
/// 2. Dados ou moeda do usuário são OPCIONAIS e só se SOMAM: entram num
///    SHA-256 junto com os bytes do sistema. Um dado viciado, uma moeda
///    ruim ou um app adulterado do outro lado não conseguem reduzir a
///    entropia — para prever a semente seria preciso prever as duas fontes.
/// 3. Nada de relógio, contador ou identificador do aparelho como fonte.
class Entropia {
  /// Bytes do gerador criptográfico do sistema, cada um de 0 a 255.
  static Uint8List doSistema(int n, {Random? gerador}) {
    final r = gerador ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// Entropia final de [bytes] bytes (16 = 12 palavras, 32 = 24 palavras).
  /// [doUsuario]: resultados de dados/moeda (ex.: "3,6,1,4" ou "CKKC"), opcional.
  static Uint8List gerar(int bytes, {String? doUsuario, Random? gerador}) {
    if (bytes != 16 && bytes != 32) {
      throw ArgumentError('A semente usa 16 ou 32 bytes de entropia.');
    }
    final sistema = doSistema(32, gerador: gerador);
    final usuario = _normalizar(doUsuario);
    // Rótulo de domínio + tamanhos: duas entradas diferentes nunca colidem
    // por concatenação ambígua.
    final mistura = <int>[
      ...'iris-semente-v1'.codeUnits,
      sistema.length,
      ...sistema,
      ..._u32(usuario.length),
      ...usuario,
    ];
    final h = sha256.convert(mistura).bytes;
    if (bytes == 16) return Uint8List.fromList(h.sublist(0, 16));
    // 24 palavras: um segundo bloco independente do mesmo material.
    final h2 = sha256.convert([...mistura, 0x02]).bytes;
    return Uint8List.fromList([...h.sublist(0, 16), ...h2.sublist(0, 16)]);
  }

  /// Frase-semente BIP39 a partir de [gerar].
  static String mnemonica({int palavras = 12, String? doUsuario, Random? gerador}) {
    final e = gerar(palavras == 24 ? 32 : 16, doUsuario: doUsuario, gerador: gerador);
    return bip39.entropyToMnemonic(_hex(e));
  }

  /// Quantos bits os dados/moeda informados acrescentam, se forem honestos.
  /// Só para mostrar ao usuário — a segurança não depende disto.
  static double bitsDoUsuario(String? entrada) {
    final s = (entrada ?? '').toUpperCase();
    final dados = RegExp(r'[1-6]').allMatches(s).length;
    final moedas = RegExp(r'[CK]').allMatches(s).length;
    return dados * 2.584962500721156 + moedas * 1.0;
  }

  static List<int> _normalizar(String? s) {
    if (s == null) return const [];
    // Só os símbolos que importam (1–6 de dado, C/K de cara/coroa): espaços
    // e separadores não mudam o resultado.
    return s
        .toUpperCase()
        .split('')
        .where((c) => '123456CK'.contains(c))
        .join()
        .codeUnits;
  }

  static List<int> _u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

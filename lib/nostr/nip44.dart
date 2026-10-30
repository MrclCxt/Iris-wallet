import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'chaves.dart';

/// Cifragem NIP-44 v2: ECDH secp256k1 → HKDF-SHA256 → ChaCha20 + HMAC-SHA256,
/// com preenchimento que esconde o tamanho da mensagem. É como o Bro e o
/// Mostro trocam ordens e comprovantes sem que os relays leiam o conteúdo.
class Nip44 {
  static const int _versao = 2;

  /// Chave da conversa entre [privada] e [publicaDoOutro] (x-only, hex).
  static Uint8List chaveDaConversa(String privada, String publicaDoOutro) {
    final ponto = secp256k1.curve.decodePoint([2, ...deHex(publicaDoOutro)])!;
    final compartilhado = (ponto * BigInt.parse(privada, radix: 16))!;
    final x = bytesDe(compartilhado.x!.toBigInteger()!);
    return _hmac256(utf8.encode('nip44-v2'), x); // HKDF-extract
  }

  static ({Uint8List chave, Uint8List nonce, Uint8List mac}) chavesDaMensagem(
      Uint8List conversa, Uint8List nonce) {
    final okm = _hkdfExpand(conversa, nonce, 76);
    return (
      chave: okm.sublist(0, 32),
      nonce: okm.sublist(32, 44),
      mac: okm.sublist(44, 76),
    );
  }

  static int tamanhoPreenchido(int n) {
    if (n <= 32) return 32;
    final proxima = 1 << ((log(n - 1) / ln2).floor() + 1);
    final bloco = proxima <= 256 ? 32 : proxima ~/ 8;
    return bloco * (((n - 1) ~/ bloco) + 1);
  }

  static String cifrar(String texto, Uint8List conversa, {Uint8List? nonce}) {
    final n = nonce ?? _aleatorio(32);
    final k = chavesDaMensagem(conversa, n);
    final bruto = utf8.encode(texto);
    if (bruto.isEmpty || bruto.length > 65535) {
      throw ArgumentError('mensagem NIP-44 deve ter de 1 a 65535 bytes');
    }
    final preenchido = Uint8List(2 + tamanhoPreenchido(bruto.length))
      ..[0] = bruto.length >> 8
      ..[1] = bruto.length & 0xff
      ..setRange(2, 2 + bruto.length, bruto);
    final cifrado = _chacha(k.chave, k.nonce, preenchido);
    final mac = _hmac256(k.mac, [...n, ...cifrado]);
    return base64.encode([_versao, ...n, ...cifrado, ...mac]);
  }

  static String decifrar(String carga, Uint8List conversa) {
    if (carga.isEmpty || carga.startsWith('#')) {
      throw const FormatException('versão NIP-44 desconhecida');
    }
    if (carga.length < 132 || carga.length > 87472) {
      throw const FormatException('tamanho de carga NIP-44 inválido');
    }
    final d = base64.decode(carga);
    if (d.length < 99 || d.length > 65603 || d[0] != _versao) {
      throw const FormatException('carga NIP-44 inválida');
    }
    final nonce = d.sublist(1, 33);
    final cifrado = d.sublist(33, d.length - 32);
    final mac = d.sublist(d.length - 32);
    final k = chavesDaMensagem(conversa, nonce);
    if (!_iguais(_hmac256(k.mac, [...nonce, ...cifrado]), mac)) {
      throw const FormatException('MAC NIP-44 inválido');
    }
    final p = _chacha(k.chave, k.nonce, cifrado);
    final n = (p[0] << 8) | p[1];
    if (n == 0 || p.length != 2 + tamanhoPreenchido(n)) {
      throw const FormatException('preenchimento NIP-44 inválido');
    }
    return utf8.decode(p.sublist(2, 2 + n));
  }

  static Uint8List _chacha(Uint8List chave, Uint8List nonce, List<int> dados) {
    final c = ChaCha7539Engine()
      ..init(true, ParametersWithIV(KeyParameter(chave), nonce));
    final entrada = Uint8List.fromList(dados);
    final out = Uint8List(entrada.length);
    c.processBytes(entrada, 0, entrada.length, out, 0);
    return out;
  }

  static Uint8List _hmac256(List<int> chave, List<int> dados) {
    final h = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List.fromList(chave)));
    final out = Uint8List(32);
    h.update(Uint8List.fromList(dados), 0, dados.length);
    h.doFinal(out, 0);
    return out;
  }

  static Uint8List _hkdfExpand(Uint8List prk, List<int> info, int tamanho) {
    final out = <int>[];
    var t = <int>[];
    for (var i = 1; out.length < tamanho; i++) {
      t = _hmac256(prk, [...t, ...info, i]);
      out.addAll(t);
    }
    return Uint8List.fromList(out.sublist(0, tamanho));
  }

  static bool _iguais(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }

  static Uint8List _aleatorio(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}

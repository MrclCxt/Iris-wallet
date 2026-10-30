import 'dart:convert';
import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/export.dart';

final ECDomainParameters secp256k1 = ECDomainParameters('secp256k1');

/// Identidade Nostr derivada da mesma semente da carteira, pelo NIP-06
/// (m/44'/1237'/0'/0/0). É a mesma chave que o Bro e outros clientes geram com
/// a mesma semente: nada novo para anotar, e funciona em qualquer app Nostr.
class ChavesNostr {
  final String privada;
  final String publica;

  const ChavesNostr._(this.privada, this.publica);

  factory ChavesNostr.daSemente(String mnemonica, {String senha = ''}) {
    final semente = bip39.mnemonicToSeed(mnemonica.trim(), passphrase: senha);
    var no = _mestre(Uint8List.fromList(semente));
    for (final i in const [
      0x8000002C, // 44'
      0x800004D5, // 1237' (Nostr)
      0x80000000, // 0'
      0,
      0,
    ]) {
      no = _filho(no, i);
    }
    final privada = _hex(no.chave);
    return ChavesNostr._(privada, bip340.getPublicKey(privada));
  }

  factory ChavesNostr.daPrivada(String privadaHex) =>
      ChavesNostr._(privadaHex, bip340.getPublicKey(privadaHex));
}

class _No {
  final Uint8List chave;
  final Uint8List cadeia;
  const _No(this.chave, this.cadeia);
}

Uint8List _hmac512(List<int> chave, List<int> dados) {
  final h = HMac(SHA512Digest(), 128)..init(KeyParameter(Uint8List.fromList(chave)));
  final out = Uint8List(64);
  h.update(Uint8List.fromList(dados), 0, dados.length);
  h.doFinal(out, 0);
  return out;
}

_No _mestre(Uint8List semente) {
  final i = _hmac512(utf8.encode('Bitcoin seed'), semente);
  return _No(i.sublist(0, 32), i.sublist(32));
}

_No _filho(_No pai, int indice) {
  final dados = <int>[
    if (indice >= 0x80000000) ...[0, ...pai.chave] else ..._pubComprimida(pai.chave),
    (indice >> 24) & 0xff,
    (indice >> 16) & 0xff,
    (indice >> 8) & 0xff,
    indice & 0xff,
  ];
  final i = _hmac512(pai.cadeia, dados);
  final il = _int(i.sublist(0, 32));
  final k = (il + _int(pai.chave)) % secp256k1.n;
  // BIP32: chave inválida (probabilidade ~2^-127) — passa ao índice seguinte.
  if (il >= secp256k1.n || k == BigInt.zero) return _filho(pai, indice + 1);
  return _No(bytesDe(k), i.sublist(32));
}

List<int> _pubComprimida(Uint8List privada) {
  final p = (secp256k1.G * _int(privada))!;
  final y = p.y!.toBigInteger()!;
  return [y.isOdd ? 3 : 2, ...bytesDe(p.x!.toBigInteger()!)];
}

BigInt _int(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

Uint8List bytesDe(BigInt n, [int tamanho = 32]) {
  final out = Uint8List(tamanho);
  var v = n;
  for (var i = tamanho - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List deHex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
    ]);

String paraHex(List<int> b) => _hex(b);

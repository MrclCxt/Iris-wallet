import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../nostr/chaves.dart';

/// Varredura de chave avulsa (WIF): resgata um voucher Bitcoin ou uma
/// carteira de papel, mandando tudo o que a chave tem para a carteira do
/// usuário numa única transação, assinada no aparelho.
///
/// Aceita os dois formatos mais comuns em papel: SegWit nativo (P2WPKH, com
/// chave comprimida) e legado (P2PKH, comprimida ou não).
class ChaveAvulsa {
  final Uint8List privada;
  final bool comprimida;
  final bool principal;

  ChaveAvulsa._(this.privada, this.comprimida, this.principal);

  static ChaveAvulsa deWif(String wif) {
    final d = _base58Check(wif.trim());
    if (d == null) throw const FormatException('Chave inválida (checksum).');
    final versao = d[0];
    if (versao != 0x80 && versao != 0xef) {
      throw const FormatException('Isto não é uma chave privada WIF.');
    }
    if (d.length == 34 && d[33] == 0x01) {
      return ChaveAvulsa._(Uint8List.fromList(d.sublist(1, 33)), true, versao == 0x80);
    }
    if (d.length == 33) {
      return ChaveAvulsa._(Uint8List.fromList(d.sublist(1, 33)), false, versao == 0x80);
    }
    throw const FormatException('Tamanho de chave WIF inválido.');
  }

  BigInt get _d => _int(privada);

  Uint8List get publica {
    final p = (secp256k1.G * _d)!;
    return Uint8List.fromList(p.getEncoded(comprimida));
  }

  Uint8List get hash160 => _hash160(publica);

  /// Gera uma chave nova (voucher). [principal]: rede principal ou de testes.
  static ChaveAvulsa nova({required bool principal}) {
    final r = Random.secure();
    while (true) {
      final b = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
      final d = _int(b);
      if (d > BigInt.zero && d < secp256k1.n) {
        return ChaveAvulsa._(b, true, principal);
      }
    }
  }

  String get wif {
    final corpo = [principal ? 0x80 : 0xef, ...privada, if (comprimida) 0x01];
    final soma = sha256.convert(sha256.convert(corpo).bytes).bytes.sublist(0, 4);
    final dados = [...corpo, ...soma];
    var n = _int(dados);
    var out = '';
    while (n > BigInt.zero) {
      out = _alfabeto[(n % BigInt.from(58)).toInt()] + out;
      n = n ~/ BigInt.from(58);
    }
    for (final x in dados) {
      if (x != 0) break;
      out = '1$out';
    }
    return out;
  }

  /// Endereço SegWit (P2WPKH) desta chave na rede [hrp].
  String enderecoSegwit(String hrp) {
    if (!comprimida) throw StateError('chave não comprimida não tem SegWit');
    return _bech32(hrp, 0, hash160);
  }

  /// Parece uma chave WIF? (formato; a validade vem de [deWif]).
  static bool pareceWif(String s) =>
      RegExp(r'^[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}$').hasMatch(s.trim());

  /// Scripts que esta chave pode controlar, do mais comum ao menos.
  List<Uint8List> get scripts => [
        if (comprimida) Uint8List.fromList([0x00, 0x14, ...hash160]),
        Uint8List.fromList([0x76, 0xa9, 0x14, ...hash160, 0x88, 0xac]),
      ];
}

class Utxo {
  final String txid;
  final int vout;
  final int valor;
  final Uint8List script;
  const Utxo(this.txid, this.vout, this.valor, this.script);

  bool get segwit => script.length == 22 && script[0] == 0 && script[1] == 0x14;
}

/// Monta e assina a transação que leva todos os [utxos] para [destino]
/// (scriptPubKey), pagando [satsPorVbyte]. Devolve o hex.
String varrer({
  required ChaveAvulsa chave,
  required List<Utxo> utxos,
  required Uint8List destino,
  required double satsPorVbyte,
}) {
  if (utxos.isEmpty) throw const FormatException('A chave não tem saldo.');
  final total = utxos.fold<int>(0, (a, u) => a + u.valor);
  final temSegwit = utxos.any((u) => u.segwit);
  final vbytes = (temSegwit ? 10.5 : 10) +
      utxos.fold<double>(0, (a, u) => a + (u.segwit ? 68 : (chave.comprimida ? 148 : 180))) +
      9 + destino.length;
  final taxa = (vbytes * satsPorVbyte).ceil();
  final saida = total - taxa;
  if (saida < 546) {
    throw FormatException('Saldo ($total sats) não cobre a taxa da rede ($taxa sats).');
  }

  final entradas = [
    for (final u in utxos) [..._le(_hex(u.txid)).reversed, ..._u32(u.vout)]
  ];
  const sequencia = 0xfffffffd;
  final saidaBytes = [..._u64(saida), ..._varint(destino.length), ...destino];

  final assinaturas = <List<int>>[];
  final testemunhas = <List<List<int>>>[];
  for (var i = 0; i < utxos.length; i++) {
    final u = utxos[i];
    final Uint8List hash;
    if (u.segwit) {
      hash = _sighashBip143(
        entradas: entradas,
        indice: i,
        codigo: [0x76, 0xa9, 0x14, ...chave.hash160, 0x88, 0xac],
        valor: u.valor,
        sequencia: sequencia,
        saidas: saidaBytes,
      );
    } else {
      hash = _sighashLegado(
        entradas: entradas,
        indice: i,
        script: u.script,
        sequencia: sequencia,
        saidas: saidaBytes,
      );
    }
    final assinatura = [...assinarDer(chave._d, hash), 0x01];
    if (u.segwit) {
      assinaturas.add(const []);
      testemunhas.add([assinatura, chave.publica]);
    } else {
      assinaturas.add([
        ..._push(assinatura),
        ..._push(chave.publica),
      ]);
      testemunhas.add(const []);
    }
  }

  final out = <int>[..._u32(2)];
  if (temSegwit) out.addAll([0x00, 0x01]);
  out.addAll(_varint(utxos.length));
  for (var i = 0; i < utxos.length; i++) {
    out
      ..addAll(entradas[i])
      ..addAll(_varint(assinaturas[i].length))
      ..addAll(assinaturas[i])
      ..addAll(_u32(sequencia));
  }
  out.addAll(_varint(1));
  out.addAll(saidaBytes);
  if (temSegwit) {
    for (final w in testemunhas) {
      out.addAll(_varint(w.length));
      for (final item in w) {
        out
          ..addAll(_varint(item.length))
          ..addAll(item);
      }
    }
  }
  out.addAll(_u32(0));
  return paraHex(out);
}

/// sha256 do script, com bytes invertidos: o índice que o Esplora usa.
String scripthashEsplora(Uint8List script) =>
    paraHex(sha256.convert(script).bytes.reversed.toList());

/// scriptPubKey de um endereço SegWit (bech32/bech32m) da rede [hrp].
Uint8List scriptDeEndereco(String endereco, String hrp) {
  final a = endereco.trim().toLowerCase();
  final pos = a.lastIndexOf('1');
  if (pos < 1 || a.substring(0, pos) != hrp) {
    throw const FormatException('Endereço de destino de outra rede.');
  }
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final dados = [for (final c in a.substring(pos + 1).split('')) charset.indexOf(c)];
  if (dados.contains(-1) || dados.length < 7) {
    throw const FormatException('Endereço de destino inválido.');
  }
  final versao = dados[0];
  final programa = _converterBits(dados.sublist(1, dados.length - 6), 5, 8);
  if (programa == null || programa.length < 2 || programa.length > 40 || versao > 16) {
    throw const FormatException('Endereço de destino inválido.');
  }
  return Uint8List.fromList(
      [versao == 0 ? 0 : 0x50 + versao, programa.length, ...programa]);
}

/// ECDSA determinística (RFC 6979) com S baixo, codificada em DER.
List<int> assinarDer(BigInt d, Uint8List hash32) {
  final signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter(ECPrivateKey(d, secp256k1)));
  final sig = signer.generateSignature(hash32) as ECSignature;
  var s = sig.s;
  if (s > secp256k1.n >> 1) s = secp256k1.n - s;
  List<int> inteiro(BigInt v) {
    var b = bytesDe(v).toList();
    while (b.length > 1 && b[0] == 0 && b[1] < 0x80) {
      b = b.sublist(1);
    }
    if (b[0] >= 0x80) b = [0, ...b];
    return [0x02, b.length, ...b];
  }

  final corpo = [...inteiro(sig.r), ...inteiro(s)];
  return [0x30, corpo.length, ...corpo];
}

Uint8List _sighashBip143({
  required List<List<int>> entradas,
  required int indice,
  required List<int> codigo,
  required int valor,
  required int sequencia,
  required List<int> saidas,
}) {
  final prevouts = _sha256d([for (final e in entradas) ...e]);
  final seqs = _sha256d([for (final _ in entradas) ..._u32(sequencia)]);
  final outs = _sha256d(saidas);
  return _sha256d([
    ..._u32(2),
    ...prevouts,
    ...seqs,
    ...entradas[indice],
    ..._varint(codigo.length),
    ...codigo,
    ..._u64(valor),
    ..._u32(sequencia),
    ...outs,
    ..._u32(0),
    ..._u32(1),
  ]);
}

Uint8List _sighashLegado({
  required List<List<int>> entradas,
  required int indice,
  required List<int> script,
  required int sequencia,
  required List<int> saidas,
}) {
  final b = <int>[..._u32(2), ..._varint(entradas.length)];
  for (var i = 0; i < entradas.length; i++) {
    b.addAll(entradas[i]);
    final s = i == indice ? script : const <int>[];
    b
      ..addAll(_varint(s.length))
      ..addAll(s)
      ..addAll(_u32(sequencia));
  }
  b
    ..addAll(_varint(1))
    ..addAll(saidas)
    ..addAll(_u32(0))
    ..addAll(_u32(1));
  return _sha256d(b);
}

/// Exposto para o teste do vetor oficial do BIP143.
Uint8List sighashBip143ParaTeste({
  required int versao,
  required List<int> prevouts,
  required List<int> sequencias,
  required List<int> entrada,
  required List<int> codigo,
  required int valor,
  required int sequencia,
  required List<int> saidas,
  required int locktime,
}) =>
    _sha256d([
      ..._u32(versao),
      ..._sha256d(prevouts),
      ..._sha256d(sequencias),
      ...entrada,
      ...codigo,
      ..._u64(valor),
      ..._u32(sequencia),
      ..._sha256d(saidas),
      ..._u32(locktime),
      ..._u32(1),
    ]);

List<int> _push(List<int> dados) => [dados.length, ...dados];

Uint8List _sha256d(List<int> b) =>
    Uint8List.fromList(sha256.convert(sha256.convert(b).bytes).bytes);

Uint8List _hash160(List<int> b) {
  final r = RIPEMD160Digest();
  final s = Uint8List.fromList(sha256.convert(b).bytes);
  return r.process(s);
}

List<int> _u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

List<int> _u64(int v) => [
      for (var i = 0; i < 8; i++) ((BigInt.from(v) >> (8 * i)) & BigInt.from(0xff)).toInt()
    ];

List<int> _varint(int n) {
  if (n < 0xfd) return [n];
  if (n <= 0xffff) return [0xfd, n & 0xff, n >> 8];
  return [0xfe, ..._u32(n)];
}

List<int> _hex(String s) => deHex(s);
List<int> _le(List<int> b) => b;

BigInt _int(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

List<int>? _converterBits(List<int> dados, int de, int para,
    {bool preencher = false}) {
  var acc = 0, bits = 0;
  final out = <int>[];
  final max = (1 << para) - 1;
  for (final v in dados) {
    acc = (acc << de) | v;
    bits += de;
    while (bits >= para) {
      bits -= para;
      out.add((acc >> bits) & max);
    }
  }
  if (preencher) {
    if (bits > 0) out.add((acc << (para - bits)) & max);
    return out;
  }
  if (bits >= de || ((acc << (para - bits)) & max) != 0) return null;
  return out;
}

String _bech32(String hrp, int versao, List<int> programa) {
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  int polymod(List<int> v) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final x in v) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ x;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) chk ^= gen[i];
      }
    }
    return chk;
  }

  final dados = [versao, ..._converterBits(programa, 8, 5, preencher: true)!];
  final expandido = [
    for (final c in hrp.codeUnits) c >> 5,
    0,
    for (final c in hrp.codeUnits) c & 31,
  ];
  final mod = polymod([...expandido, ...dados, 0, 0, 0, 0, 0, 0]) ^ 1;
  final soma = [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...dados, ...soma].map((d) => charset[d]).join()}';
}

const _alfabeto = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

List<int>? _base58Check(String s) {
  var n = BigInt.zero;
  for (final c in s.split('')) {
    final v = _alfabeto.indexOf(c);
    if (v < 0) return null;
    n = n * BigInt.from(58) + BigInt.from(v);
  }
  final bytes = <int>[];
  while (n > BigInt.zero) {
    bytes.insert(0, (n & BigInt.from(0xff)).toInt());
    n >>= 8;
  }
  for (final c in s.split('')) {
    if (c != '1') break;
    bytes.insert(0, 0);
  }
  if (bytes.length < 5) return null;
  final corpo = bytes.sublist(0, bytes.length - 4);
  final soma = sha256.convert(sha256.convert(corpo).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (soma[i] != bytes[bytes.length - 4 + i]) return null;
  }
  return corpo;
}

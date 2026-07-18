import 'dart:convert';

/// Decoder BOLT11 puro em Dart.
///
/// Extrai da fatura Lightning: rede, valor (sats/msats), descrição,
/// payment hash, timestamp e expiração — sem depender do nó LDK,
/// permitindo exibir os dados reais antes de confirmar o pagamento.
class Bolt11ParseException implements Exception {
  final String message;
  Bolt11ParseException(this.message);
  @override
  String toString() => 'Bolt11ParseException: $message';
}

class Bolt11Data {
  final String network; // bc | tb | tbs | bcrt
  final int? amountMsat; // null = fatura de valor aberto
  final String description;
  final String paymentHashHex;
  final DateTime timestamp;
  final Duration expiry;

  Bolt11Data({
    required this.network,
    required this.amountMsat,
    required this.description,
    required this.paymentHashHex,
    required this.timestamp,
    required this.expiry,
  });

  int? get amountSats => amountMsat == null ? null : amountMsat! ~/ 1000;
  bool get isTestnet => network == 'tb' || network == 'tbs' || network == 'bcrt';
  bool get isExpired => DateTime.now().isAfter(timestamp.add(expiry));
}

class Bolt11 {
  static const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// Verifica se a string tem cara de fatura BOLT11.
  static bool looksLikeInvoice(String input) {
    final s = input.trim().toLowerCase();
    return RegExp(r'^ln(bc|tb|tbs|bcrt)[0-9munp]*1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{6,}$')
        .hasMatch(s);
  }

  /// Decodifica uma fatura BOLT11 completa.
  static Bolt11Data decode(String invoice) {
    final s = invoice.trim().toLowerCase();
    final sepIdx = s.lastIndexOf('1');
    if (sepIdx < 3) throw Bolt11ParseException('Separador bech32 não encontrado');

    final hrp = s.substring(0, sepIdx);
    final dataPart = s.substring(sepIdx + 1);
    if (dataPart.length < 110) {
      // 7 (timestamp) + 104 (assinatura) + checksum(6) mínimos
      throw Bolt11ParseException('Fatura curta demais');
    }

    final data = <int>[];
    for (final c in dataPart.split('')) {
      final v = _charset.indexOf(c);
      if (v == -1) throw Bolt11ParseException('Caractere inválido: $c');
      data.add(v);
    }

    if (!_verifyChecksum(hrp, data)) {
      throw Bolt11ParseException('Checksum bech32 inválido');
    }

    // Remove checksum (6 grupos) e assinatura (104 grupos)
    final payload = data.sublist(0, data.length - 6);
    if (payload.length < 7 + 104) throw Bolt11ParseException('Payload incompleto');
    final tagged = payload.sublist(7, payload.length - 104);

    // HRP: ln + rede + valor opcional
    final hrpMatch = RegExp(r'^ln(bc|tb|tbs|bcrt)(\d+)?([munp])?$').firstMatch(hrp);
    if (hrpMatch == null) throw Bolt11ParseException('HRP inválido: $hrp');
    final network = hrpMatch.group(1)!;
    final amountMsat = _parseAmountMsat(hrpMatch.group(2), hrpMatch.group(3));

    // Timestamp: primeiros 35 bits
    int ts = 0;
    for (int i = 0; i < 7; i++) {
      ts = ts * 32 + payload[i];
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);

    // Campos taggeados
    String description = '';
    String paymentHashHex = '';
    Duration expiry = const Duration(seconds: 3600); // default do BOLT11

    int i = 0;
    while (i + 3 <= tagged.length) {
      final type = tagged[i];
      final len = tagged[i + 1] * 32 + tagged[i + 2];
      if (i + 3 + len > tagged.length) break;
      final fieldData = tagged.sublist(i + 3, i + 3 + len);

      switch (type) {
        case 1: // 'p' payment hash
          final bytes = _convertBits(fieldData, 5, 8, false);
          paymentHashHex =
              bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          break;
        case 13: // 'd' descrição
          final bytes = _convertBits(fieldData, 5, 8, false);
          description = utf8.decode(bytes, allowMalformed: true);
          break;
        case 6: // 'x' expiração
          int e = 0;
          for (final v in fieldData) {
            e = e * 32 + v;
          }
          expiry = Duration(seconds: e);
          break;
      }
      i += 3 + len;
    }

    return Bolt11Data(
      network: network,
      amountMsat: amountMsat,
      description: description,
      paymentHashHex: paymentHashHex,
      timestamp: timestamp,
      expiry: expiry,
    );
  }

  /// Converte a parte de valor do HRP para msats.
  /// Multiplicadores BOLT11: m=0.001, u=0.000001, n=1e-9, p=1e-12 BTC.
  static int? _parseAmountMsat(String? digits, String? multiplier) {
    if (digits == null || digits.isEmpty) return null;
    final value = BigInt.parse(digits);
    // 1 BTC = 10^11 msat
    BigInt msat;
    switch (multiplier) {
      case 'm':
        msat = value * BigInt.from(100000000); // 1e11 / 1e3
        break;
      case 'u':
        msat = value * BigInt.from(100000); // 1e11 / 1e6
        break;
      case 'n':
        msat = value * BigInt.from(100); // 1e11 / 1e9
        break;
      case 'p':
        if (value % BigInt.from(10) != BigInt.zero) {
          throw Bolt11ParseException('Valor em pico-BTC deve ser múltiplo de 10');
        }
        msat = value ~/ BigInt.from(10); // 1e11 / 1e12
        break;
      default:
        msat = value * BigInt.from(100000000000); // BTC inteiro
    }
    return msat.toInt();
  }

  // ---- bech32 ----

  static const List<int> _gen = [
    0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3
  ];

  static int _polymod(List<int> values) {
    int chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (int i = 0; i < 5; i++) {
        if (((top >> i) & 1) == 1) chk ^= _gen[i];
      }
    }
    return chk;
  }

  static List<int> _hrpExpand(String hrp) {
    final result = <int>[];
    for (final c in hrp.codeUnits) {
      result.add(c >> 5);
    }
    result.add(0);
    for (final c in hrp.codeUnits) {
      result.add(c & 31);
    }
    return result;
  }

  static bool _verifyChecksum(String hrp, List<int> data) {
    return _polymod([..._hrpExpand(hrp), ...data]) == 1;
  }

  /// Reagrupa bits (ex.: grupos de 5 bits -> bytes de 8 bits).
  static List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0;
    int bits = 0;
    final result = <int>[];
    final maxv = (1 << to) - 1;
    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw Bolt11ParseException('Valor fora do intervalo em convertBits');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad && bits > 0) {
      result.add((acc << (to - bits)) & maxv);
    }
    return result;
  }

  /// Decodifica bech32 genérico (usado pelo LNURL). Retorna (hrp, bytes).
  static (String, List<int>) decodeBech32(String input, {bool ignoreLength = true}) {
    final s = input.trim().toLowerCase();
    final sepIdx = s.lastIndexOf('1');
    if (sepIdx < 1) throw Bolt11ParseException('Separador bech32 não encontrado');
    final hrp = s.substring(0, sepIdx);
    final dataPart = s.substring(sepIdx + 1);
    final data = <int>[];
    for (final c in dataPart.split('')) {
      final v = _charset.indexOf(c);
      if (v == -1) throw Bolt11ParseException('Caractere bech32 inválido: $c');
      data.add(v);
    }
    if (!_verifyChecksum(hrp, data)) {
      throw Bolt11ParseException('Checksum bech32 inválido');
    }
    final bytes = _convertBits(data.sublist(0, data.length - 6), 5, 8, false);
    return (hrp, bytes);
  }
}

class BrCodeException implements Exception {
  final String message;
  BrCodeException(this.message);
  @override
  String toString() => 'BrCodeException: $message';
}

class BrCodeData {
  final String pixKey;
  final double? amountBrl;
  final String merchantName;
  final String merchantCity;
  final String txid;
  final String raw;

  BrCodeData({
    required this.pixKey,
    required this.amountBrl,
    required this.merchantName,
    required this.merchantCity,
    required this.txid,
    required this.raw,
  });
}

class BrCode {
  static bool looksLikeBrCode(String input) {
    final s = input.trim();
    return s.startsWith('000201') && s.toLowerCase().contains('br.gov.bcb.pix');
  }

  static Map<String, String> _parseTlv(String payload) {
    final fields = <String, String>{};
    int i = 0;
    while (i + 4 <= payload.length) {
      final tag = payload.substring(i, i + 2);
      final len = int.tryParse(payload.substring(i + 2, i + 4));
      if (len == null || i + 4 + len > payload.length) {
        throw BrCodeException('TLV malformado na posição $i');
      }
      fields[tag] = payload.substring(i + 4, i + 4 + len);
      i += 4 + len;
    }
    return fields;
  }

  static int crc16(String data) {
    int crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= byte << 8;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  static BrCodeData decode(String input) {
    final s = input.trim();
    if (!looksLikeBrCode(s)) {
      throw BrCodeException('Não é um BR Code PIX');
    }

    final crcIdx = s.lastIndexOf('6304');
    if (crcIdx == -1 || crcIdx + 8 != s.length) {
      throw BrCodeException('Campo CRC (63) ausente ou mal posicionado');
    }
    final expected = s.substring(crcIdx + 4).toUpperCase();
    final computed = crc16(s.substring(0, crcIdx + 4))
        .toRadixString(16)
        .toUpperCase()
        .padLeft(4, '0');
    if (computed != expected) {
      throw BrCodeException(
          'CRC inválido (esperado $expected, calculado $computed)');
    }

    final fields = _parseTlv(s);

    String pixKey = '';
    for (int t = 26; t <= 51; t++) {
      final tag = t.toString().padLeft(2, '0');
      final value = fields[tag];
      if (value == null) continue;
      final sub = _parseTlv(value);
      if ((sub['00'] ?? '').toLowerCase() == 'br.gov.bcb.pix') {
        pixKey = sub['01'] ?? '';
        break;
      }
    }
    if (pixKey.isEmpty) {
      throw BrCodeException('Chave PIX não encontrada no BR Code');
    }

    String txid = '***';
    final additional = fields['62'];
    if (additional != null) {
      final sub = _parseTlv(additional);
      txid = sub['05'] ?? '***';
    }

    return BrCodeData(
      pixKey: pixKey,
      amountBrl: fields['54'] != null ? double.tryParse(fields['54']!) : null,
      merchantName: fields['59'] ?? '',
      merchantCity: fields['60'] ?? '',
      txid: txid,
      raw: s,
    );
  }

  static String _tlv(String tag, String value) =>
      '$tag${value.length.toString().padLeft(2, '0')}$value';

  static String build({
    required String pixKey,
    double? amountBrl,
    required String merchantName,
    required String merchantCity,
    String txid = '***',
  }) {
    final name =
        merchantName.length > 25 ? merchantName.substring(0, 25) : merchantName;
    final city =
        merchantCity.length > 15 ? merchantCity.substring(0, 15) : merchantCity;

    final buffer = StringBuffer()
      ..write(_tlv('00', '01'))
      ..write(_tlv('26', _tlv('00', 'br.gov.bcb.pix') + _tlv('01', pixKey)))
      ..write(_tlv('52', '0000'))
      ..write(_tlv('53', '986'));
    if (amountBrl != null && amountBrl > 0) {
      buffer.write(_tlv('54', amountBrl.toStringAsFixed(2)));
    }
    buffer
      ..write(_tlv('58', 'BR'))
      ..write(_tlv('59', name))
      ..write(_tlv('60', city))
      ..write(_tlv('62', _tlv('05', txid)));

    final partial = '${buffer.toString()}6304';
    final crc = crc16(partial).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$partial$crc';
  }
}

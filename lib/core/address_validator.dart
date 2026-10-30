import 'package:crypto/crypto.dart';
import 'rede.dart';

class ResultadoEndereco {
  final bool valido;
  final String? motivo;
  final String? tipo;

  const ResultadoEndereco.ok(this.tipo)
      : valido = true,
        motivo = null;
  const ResultadoEndereco.erro(this.motivo)
      : valido = false,
        tipo = null;
}

class AddressValidator {
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  static int _polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) chk ^= gen[i];
      }
    }
    return chk;
  }

  static List<int> _hrpExpand(String hrp) {
    final out = <int>[];
    for (final c in hrp.codeUnits) {
      out.add(c >> 5);
    }
    out.add(0);
    for (final c in hrp.codeUnits) {
      out.add(c & 31);
    }
    return out;
  }

  static ResultadoEndereco validar(String entrada) =>
      Rede.principal ? validarPrincipal(entrada) : validarTestnet(entrada);

  static const _base58 =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static List<int>? _base58Check(String s) {
    var n = BigInt.zero;
    for (final c in s.split('')) {
      final v = _base58.indexOf(c);
      if (v < 0) return null;
      n = n * BigInt.from(58) + BigInt.from(v);
    }
    final bytes = <int>[];
    while (n > BigInt.zero) {
      bytes.insert(0, (n % BigInt.from(256)).toInt());
      n = n ~/ BigInt.from(256);
    }
    for (final c in s.split('')) {
      if (c != '1') break;
      bytes.insert(0, 0);
    }
    if (bytes.length != 25) return null;
    final corpo = bytes.sublist(0, 21);
    final soma = sha256.convert(sha256.convert(corpo).bytes).bytes;
    for (var i = 0; i < 4; i++) {
      if (soma[i] != bytes[21 + i]) return null;
    }
    return corpo;
  }

  static ResultadoEndereco validarPrincipal(String entrada) {
    final addr = entrada.trim();
    if (addr.isEmpty) return const ResultadoEndereco.erro('Endereço vazio.');

    if (addr.contains(RegExp(r'\s'))) {
      return const ResultadoEndereco.erro(
          'O endereço contém espaços. Verifique se colou completo.');
    }

    final minusculo = addr.toLowerCase();

    if (minusculo.startsWith('tb1') ||
        minusculo.startsWith('bcrt1') ||
        RegExp(r'^[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(addr)) {
      return const ResultadoEndereco.erro(
          'Este é um endereço de rede de testes. '
          'Enviar bitcoin de verdade para ele perderia os fundos.');
    }

    if (minusculo.startsWith('ltc1') || minusculo.startsWith('ln')) {
      return const ResultadoEndereco.erro(
          'Isto não é um endereço on-chain. Use a tela de Lightning.');
    }

    if (minusculo.startsWith('bc1')) {
      if (addr != minusculo && addr != addr.toUpperCase()) {
        return const ResultadoEndereco.erro(
            'Endereço com maiúsculas e minúsculas misturadas é inválido.');
      }
      final r = _validarBech32(minusculo);
      if (!r.valido) return r;
      return ResultadoEndereco.ok(r.tipo!.replaceAll('(testnet)', '').trim());
    }

    if (RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(addr)) {
      final corpo = _base58Check(addr);
      if (corpo == null) {
        return const ResultadoEndereco.erro(
            'Endereço inválido: a verificação de integridade falhou. '
            'Algum caractere está errado — confira ou peça de novo.');
      }
      if (corpo[0] == 0x00) return const ResultadoEndereco.ok('legado');
      if (corpo[0] == 0x05) return const ResultadoEndereco.ok('script (P2SH)');
      return const ResultadoEndereco.erro('Endereço de versão desconhecida.');
    }

    return const ResultadoEndereco.erro(
        'Endereço não reconhecido. Endereços Bitcoin começam com "bc1", "1" ou "3".');
  }

  static ResultadoEndereco validarTestnet(String entrada) {
    final addr = entrada.trim();
    if (addr.isEmpty) return const ResultadoEndereco.erro('Endereço vazio.');

    if (addr.contains(RegExp(r'\s'))) {
      return const ResultadoEndereco.erro(
          'O endereço contém espaços. Verifique se colou completo.');
    }

    final minusculo = addr.toLowerCase();

    if (minusculo.startsWith('bc1') ||
        RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(addr)) {
      return const ResultadoEndereco.erro(
          'Este é um endereço da rede principal (mainnet). '
          'Enviar para ele nesta rede perderia os fundos.');
    }

    if (minusculo.startsWith('bcrt1')) {
      return const ResultadoEndereco.erro(
          'Este é um endereço de regtest, não da testnet.');
    }

    if (minusculo.startsWith('ltc1') ||
        minusculo.startsWith('lnbc') ||
        minusculo.startsWith('lntb')) {
      return const ResultadoEndereco.erro(
          'Isto não é um endereço on-chain. Use a tela de Lightning.');
    }

    if (minusculo.startsWith('tb1')) {
      return _validarBech32(minusculo);
    }

    if (RegExp(r'^[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(addr)) {
      return const ResultadoEndereco.ok('legado (testnet)');
    }

    return const ResultadoEndereco.erro(
        'Endereço não reconhecido. Endereços desta rede começam com "tb1".');
  }

  static ResultadoEndereco _validarBech32(String addr) {
    final pos = addr.lastIndexOf('1');
    if (pos < 1 || pos + 7 > addr.length || addr.length > 90) {
      return const ResultadoEndereco.erro('Endereço com tamanho inválido.');
    }

    final hrp = addr.substring(0, pos);
    final dados = <int>[];
    for (final c in addr.substring(pos + 1).split('')) {
      final v = _charset.indexOf(c);
      if (v == -1) {
        return ResultadoEndereco.erro(
            'O endereço contém o caractere "$c", que não existe neste formato. '
            'Provável erro de digitação.');
      }
      dados.add(v);
    }

    final chk = _polymod([..._hrpExpand(hrp), ...dados]);
    if (chk != 1 && chk != 0x2bc830a3) {
      return const ResultadoEndereco.erro(
          'Endereço inválido: a verificação de integridade falhou. '
          'Algum caractere está errado — confira ou peça de novo.');
    }

    final versao = dados[0];
    final ehBech32m = chk == 0x2bc830a3;

    if (versao == 0 && ehBech32m) {
      return const ResultadoEndereco.erro(
          'Endereço inválido: formato incompatível com a versão.');
    }
    if (versao != 0 && !ehBech32m) {
      return const ResultadoEndereco.erro(
          'Endereço inválido: formato incompatível com a versão.');
    }

    if (versao == 0) return const ResultadoEndereco.ok('SegWit (testnet)');
    if (versao == 1) return const ResultadoEndereco.ok('Taproot (testnet)');
    return ResultadoEndereco.ok('SegWit v$versao (testnet)');
  }
}

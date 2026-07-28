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

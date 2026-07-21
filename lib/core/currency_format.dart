import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _satsFormat = NumberFormat('#,##0', 'pt_BR');
  static final NumberFormat _brlFormat = NumberFormat('#,##0.00', 'pt_BR');
  // Exibição de BTC com 2 casas decimais (parte inteira agrupada com ".").
  static final NumberFormat _btcFormat = NumberFormat('#,##0.00', 'pt_BR');
  // Número compacto (mi/bi/tri): até 2 casas, sem zeros supérfluos.
  static final NumberFormat _compactFormat = NumberFormat('#,##0.##', 'pt_BR');

  /// 1 BTC = 100.000.000 sats. Acima disso o valor é exibido em BTC.
  static const int satsPerBtc = 100000000;

  static String formatSats(int sats) {
    return _satsFormat.format(sats);
  }

  static String formatBrl(double brl) {
    return _brlFormat.format(brl);
  }

  /// Valor em BTC (8 casas), ex.: 150000000 sats -> "1,50000000".
  static String formatBtc(int sats) {
    return _btcFormat.format(sats / satsPerBtc);
  }

  /// Exibição inteligente do valor em bitcoin: até 99.999.999 mostra em sats;
  /// a partir de 100.000.000 (1 BTC) passa a exibir em BTC com 8 casas.
  /// Inclui o sufixo da unidade ("sats" ou "BTC").
  static String formatBtcOrSats(int sats) {
    if (sats.abs() >= satsPerBtc) {
      return '${formatBtc(sats)} BTC';
    }
    return '${formatSats(sats)} sats';
  }

  /// Reais abreviado para saldo/resumos: a partir de 1 milhão vira "mi",
  /// bilhão "bi", trilhão "tri". Abaixo disso usa o formato normal.
  /// Retorna só o número + sufixo (sem "R$"), para casar com "R\$ ${...}".
  static String formatBrlCompact(double brl) {
    final abs = brl.abs();
    if (abs >= 1e12) return '${_compactFormat.format(brl / 1e12)} tri';
    if (abs >= 1e9) return '${_compactFormat.format(brl / 1e9)} bi';
    if (abs >= 1e6) return '${_compactFormat.format(brl / 1e6)} mi';
    return formatBrl(brl);
  }
}

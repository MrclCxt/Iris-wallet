import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _satsFormat = NumberFormat('#,##0', 'pt_BR');
  static final NumberFormat _brlFormat = NumberFormat('#,##0.00', 'pt_BR');

  static final NumberFormat _btcFormat = NumberFormat('#,##0.00', 'pt_BR');

  static final NumberFormat _compactFormat = NumberFormat('#,##0.##', 'pt_BR');

  static const int satsPerBtc = 100000000;

  static String formatSats(int sats) {
    return _satsFormat.format(sats);
  }

  static String formatBrl(double brl) {
    return _brlFormat.format(brl);
  }

  static String formatBtc(int sats) {
    return _btcFormat.format(sats / satsPerBtc);
  }

  static String formatBtcOrSats(int sats) {
    if (sats.abs() >= satsPerBtc) {
      return '${formatBtc(sats)} BTC';
    }
    return '${formatSats(sats)} sats';
  }

  static String formatBrlCompact(double brl) {
    final abs = brl.abs();
    if (abs >= 1e12) return '${_compactFormat.format(brl / 1e12)} tri';
    if (abs >= 1e9) return '${_compactFormat.format(brl / 1e9)} bi';
    if (abs >= 1e6) return '${_compactFormat.format(brl / 1e6)} mi';
    return formatBrl(brl);
  }
}

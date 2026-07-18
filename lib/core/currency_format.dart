import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _satsFormat = NumberFormat('#,##0', 'pt_BR');
  static final NumberFormat _brlFormat = NumberFormat('#,##0.00', 'pt_BR');

  static String formatSats(int sats) {
    return _satsFormat.format(sats);
  }

  static String formatBrl(double brl) {
    return _brlFormat.format(brl);
  }
}

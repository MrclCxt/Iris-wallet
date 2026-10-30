const double divergenciaMaxima = 0.03;

double _mediana(List<double> valores) {
  final v = [...valores]..sort();
  final meio = v.length ~/ 2;
  return v.length.isOdd ? v[meio] : (v[meio - 1] + v[meio]) / 2;
}

/// Cotação de consenso entre fontes independentes: descarta quem se afasta
/// mais de [divergenciaMaxima] da mediana e só aceita com pelo menos duas
/// fontes coerentes. Uma fonte sozinha nunca define o preço.
double? cotacaoDeConsenso(List<double> cotacoes) {
  final validas = cotacoes.where((c) => c.isFinite && c > 0).toList();
  if (validas.length < 2) return null;
  final referencia = _mediana(validas);
  final coerentes = validas
      .where((c) => (c - referencia).abs() / referencia <= divergenciaMaxima)
      .toList();
  if (coerentes.length < 2) return null;
  return _mediana(coerentes);
}

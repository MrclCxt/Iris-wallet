/// QR unificado (BIP21 com `lightning=`): uma única imagem que qualquer
/// carteira paga do jeito que souber — Lightning se entender o parâmetro,
/// on-chain se não. Quem cobra não precisa escolher a rede.
String bip21Unificado({
  required String endereco,
  required String fatura,
  int? sats,
}) {
  final params = <String>[
    if (sats != null && sats > 0)
      'amount=${(sats / 100000000).toStringAsFixed(8)}',
    'lightning=$fatura',
  ];
  return 'bitcoin:$endereco?${params.join('&')}';
}

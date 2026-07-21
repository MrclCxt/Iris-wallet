/// Política de roteamento de transações do Iris Wallet.
///
/// - Transações do dia a dia: Lightning Network (instantâneo, taxa ~zero).
/// - Grandes valores: rede Bitcoin on-chain (liquidação na camada base,
///   mais adequada para montantes altos).
/// - Entrada/saída em Reais: PIX -> DEPIX (Liquid) -> sats, e o inverso.
class TxPolicy {
  /// Acima deste valor a transação é roteada/sugerida para on-chain.
  /// 1.000.000 sats = 0,01 BTC — ajuste conforme a validação do projeto.
  static const int onchainThresholdSats = 1000000;

  /// A partir de 1 BTC (100.000.000 sats) o valor é exibido em BTC e o envio
  /// é obrigatoriamente pela rede Bitcoin on-chain (não cabe em Lightning).
  static const int btcScaleThresholdSats = 100000000;

  /// true quando o valor deve ir pela rede Bitcoin (on-chain).
  static bool shouldUseOnchain(int sats) => sats >= onchainThresholdSats;

  /// true quando o valor está em escala BTC (>= 1 BTC) e, portanto, só pode
  /// ser enviado on-chain.
  static bool isBtcScale(int sats) => sats >= btcScaleThresholdSats;
}

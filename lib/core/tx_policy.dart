class TxPolicy {
  static const int onchainThresholdSats = 1000000;

  static const int btcScaleThresholdSats = 100000000;

  static bool shouldUseOnchain(int sats) => sats >= onchainThresholdSats;

  static bool isBtcScale(int sats) => sats >= btcScaleThresholdSats;
}

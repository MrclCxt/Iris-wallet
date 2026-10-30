/// Rede Bitcoin do build, escolhida na compilação e nunca em tempo de
/// execução: `--dart-define=IRIS_REDE=bitcoin` gera o build da rede principal;
/// sem isso o app é testnet4. Tudo que depende da rede sai daqui.
///
/// Os dados de cada rede ficam em chaves e pastas próprias. A testnet4 mantém
/// exatamente os nomes que já existiam, para nada se perder na atualização.
/// Contas, sementes e PIN são compartilhados: a mesma semente BIP39 deriva
/// carteiras diferentes em cada rede.
class Rede {
  static const String nome =
      String.fromEnvironment('IRIS_REDE', defaultValue: 'testnet4') == 'bitcoin'
          ? 'bitcoin'
          : 'testnet4';

  static const bool principal = nome == 'bitcoin';

  static const String rotulo = principal ? 'Bitcoin' : 'testnet4';

  static const String genesis = principal
      ? '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f'
      : '00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043';

  static const List<String> esploraPadrao = principal
      ? [
          'https://mempool.space/api',
          'https://blockstream.info/api',
          'https://mempool.va1.mempool.space/api',
        ]
      : [
          'https://mempool.space/testnet4/api',
          'https://blockstream.info/testnet4/api',
          'https://mempool.va1.mempool.space/testnet4/api',
        ];

  /// Prefixo bech32 dos endereços on-chain.
  static const String hrpEndereco = principal ? 'bc' : 'tb';

  /// Prefixos BOLT11 aceitos (testnet3 e testnet4 compartilham `tb`).
  static const List<String> hrpFatura = principal ? ['bc'] : ['tb', 'tbs'];

  static const String _tag = principal ? 'main' : 'tn4';
  static const String _tagNo = principal ? 'main' : 'tn4n';

  static String pastaNo(String fingerprint) => 'ldk_${_tagNo}_$fingerprint';
  static String chaveUltimoSaldo(String fp) => 'last_balance_${_tag}_$fp';
  static String chaveEnderecosProprios(String fp) => 'meus_enderecos_${_tag}_$fp';
  static String chaveFaturaFixa(String id) => 'fixed_invoice_${_tagNo}_$id';
  static String chaveEnderecoOnchain(String id) => 'onchain_addr_${_tag}_$id';
  static String chaveHistorico(String id) =>
      principal ? 'tx_hist_main_v2_$id' : 'tx_hist_v2_$id';
  static const String chaveEsploraProprios = 'esplora_custom_$_tag';
  static const String chaveFilaTransmissao = 'tx_fila_$_tag';
  static const String chaveRecebimentosAnunciados = 'recebimentos_anunciados_$_tag';
}

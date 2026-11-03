/// Rede Bitcoin do build, escolhida na compilação e nunca em tempo de
/// execução. Três valores aceitos em `--dart-define=IRIS_REDE=...`:
///   - `bitcoin`  → rede principal (BTC real)
///   - `signet`   → Mutinynet (signet confiável; PADRÃO desde que a testnet4
///                  foi abandonada por instabilidade/429)
///   - `testnet4` → legado, mantido só para não perder dados antigos
///
/// Sem define, o app é **signet (Mutinynet)**. Os dados de cada rede ficam em
/// chaves e pastas próprias — a mesma semente BIP39 deriva carteiras diferentes
/// em cada rede, então trocar de rede nunca mistura saldos. A testnet4 mantém
/// exatamente os nomes que já existiam, para nada se perder.
class Rede {
  static const String _def =
      String.fromEnvironment('IRIS_REDE', defaultValue: 'signet');

  static const String nome = _def == 'bitcoin'
      ? 'bitcoin'
      : (_def == 'testnet4' ? 'testnet4' : 'signet');

  static const bool principal = nome == 'bitcoin';
  static const bool ehSignet = nome == 'signet';
  static const bool ehTestnet4 = nome == 'testnet4';

  static const String rotulo =
      principal ? 'Bitcoin' : (ehSignet ? 'Mutinynet' : 'testnet4');

  static const String genesis = principal
      ? '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f'
      : (ehSignet
          // Mutinynet usa o genesis padrão da signet, então o ChainHash do
          // Lightning bate sem patch (provado no daemon em 2026-11-01).
          ? '00000008819873e925422c1ff0f99f7cc9bbb232af63a077a480a3633bee1ef6'
          : '00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043');

  static const List<String> esploraPadrao = principal
      ? [
          'https://mempool.space/api',
          'https://blockstream.info/api',
          'https://mempool.va1.mempool.space/api',
        ]
      : (ehSignet
          ? [
              'https://mutinynet.com/api',
              'https://mutinynet.ltbl.io/api',
            ]
          : [
              'https://mempool.space/testnet4/api',
              'https://blockstream.info/testnet4/api',
              'https://mempool.va1.mempool.space/testnet4/api',
            ]);

  /// Prefixo bech32 dos endereços on-chain. Signet usa `tb`, igual à testnet.
  static const String hrpEndereco = principal ? 'bc' : 'tb';

  /// Prefixos BOLT11 aceitos. Signet usa `tbs` (lntbs); testnet usa `tb`
  /// (lntb). A testnet4 aceita os dois por compatibilidade histórica.
  static const List<String> hrpFatura =
      principal ? ['bc'] : (ehSignet ? ['tbs'] : ['tb', 'tbs']);

  /// Hub padrão da rede: 1º canal de toda carteira e LSP dos canais JIT. Só a
  /// signet tem hub por enquanto; o endereço é o do hub de testes na rede local
  /// e pode ser trocado na compilação (`--dart-define=IRIS_HUB_HOST=...`) ou no
  /// app (Avançado → LSP).
  static const String? hubPubkey = ehSignet
      ? '0311234b076cb64b62a80d2b6d15ad9a51a659fa4283be9e811a5eecebdd8bd7bd'
      : null;
  static const String hubHost =
      String.fromEnvironment('IRIS_HUB_HOST', defaultValue: '192.168.50.136');
  static const int hubPort = 9740;

  static String chaveHubLigado(String fp) => 'hub_ligado_${_tagNo}_$fp';

  static const String _tag =
      principal ? 'main' : (ehSignet ? 'sig' : 'tn4');
  // Sufixo "d" = nó POR APARELHO: pastas novas ganham um sal próprio (patch no
  // ldk-node vendorizado, `iris_node_salt`), então a mesma carteira em dois
  // aparelhos vira dois nós Lightning diferentes. As pastas antigas (sem "d")
  // ficam no disco, intactas, para não perder nada que ainda dependa delas. A
  // carteira on-chain é a mesma em qualquer aparelho (sai só da semente).
  static const String _tagNo =
      principal ? 'maind' : (ehSignet ? 'signd' : 'tn4nd');

  static String pastaNo(String fingerprint) => 'ldk_${_tagNo}_$fingerprint';
  static String chaveUltimoSaldo(String fp) => 'last_balance_${_tag}_$fp';
  // Signet com sufixo novo: as versões anteriores gravaram nestas chaves dados do
  // nó de outra conta durante a troca de carteira (endereço e histórico iguais em
  // contas diferentes). As contas recomeçam do próprio nó; o que estava gravado
  // fica nas chaves antigas, sem uso.
  static const String _tagDados = ehSignet ? 'sig2' : _tag;
  static String chaveEnderecosProprios(String fp) =>
      'meus_enderecos_${_tagDados}_$fp';
  static String chaveFaturaFixa(String id) =>
      'fixed_invoice_${ehSignet ? 'signd2' : _tagNo}_$id';
  static String chaveEnderecoOnchain(String id) =>
      'onchain_addr_${_tagDados}_$id';
  static String chaveHistorico(String id) => principal
      ? 'tx_hist_main_v2_$id'
      : (ehSignet ? 'tx_hist_sig_v3_$id' : 'tx_hist_v2_$id');
  static const String chaveEsploraProprios = 'esplora_custom_$_tag';
  static const String chaveFilaTransmissao = 'tx_fila_$_tag';
  static const String chaveRecebimentosAnunciados =
      'recebimentos_anunciados_$_tag';
}

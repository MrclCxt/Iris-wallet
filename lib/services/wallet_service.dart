import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart' show SecretKey;

import '../core/bolt11.dart';
import '../core/seed_crypto.dart';
import '../core/vault_crypto.dart';
import 'node_backend.dart';
import 'product_image_store.dart';
import 'avatar_image_store.dart';
import 'background_service_android.dart';
import 'notification_service.dart';

class Product {
  final String id;
  String name;
  double price;
  bool isActive;
  String description;

  /// Nome do arquivo da foto dentro de [ProductImageStore] — não o caminho
  /// absoluto, que muda entre instalações. Os bytes são os originais, sem
  /// recompressão. Na exportação a foto é embutida em base64 para viajar.
  String? image;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.isActive = true,
    this.description = '',
    this.image,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'isActive': isActive,
        'description': description,
        if (image != null) 'image': image,
      };

  /// Tolerante com campos ausentes: produtos gravados por versões anteriores
  /// não têm descrição nem imagem e precisam continuar carregando. O antigo
  /// campo 'emoji' é simplesmente ignorado.
  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'],
        name: json['name'],
        price: json['price'],
        isActive: json['isActive'],
        description:
            json['description'] is String ? json['description'] as String : '',
        image: json['image'] is String ? json['image'] as String : null,
      );
}

/// Produto lido de um arquivo de catálogo, com a foto ainda em base64 — ela só
/// vira arquivo local depois que o produto é aceito.
class _ProdutoImportado {
  final Product produto;
  final String? fotoBase64;
  final String extensao;

  const _ProdutoImportado({
    required this.produto,
    required this.fotoBase64,
    required this.extensao,
  });
}

/// Retorno de uma importação de catálogo, para a tela dar um resumo honesto
/// do que entrou.
class CatalogImportResult {
  final int adicionados;
  final int atualizados;
  final int ignorados;

  const CatalogImportResult({
    required this.adicionados,
    required this.atualizados,
    required this.ignorados,
  });

  int get total => adicionados + atualizados;
}

class Transaction {
  final String id;
  String title; // muda quando uma entrada pendente confirma
  final String emoji;
  final int amountSats;
  final bool isIncoming;
  final DateTime date;
  String status; // pending | confirmed | failed

  Transaction({
    required this.id,
    required this.title,
    required this.emoji,
    required this.amountSats,
    required this.isIncoming,
    required this.date,
    this.status = 'confirmed',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'amountSats': amountSats,
        'isIncoming': isIncoming,
        'date': date.toIso8601String(),
        'status': status,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '₿',
        amountSats: (j['amountSats'] as num?)?.toInt() ?? 0,
        isIncoming: j['isIncoming'] as bool? ?? true,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        status: j['status'] as String? ?? 'confirmed',
      );
}

class AccountProfile {
  final String id;

  /// Nome de exibição — editável pelo usuário a qualquer momento.
  String name;

  /// Cor de destaque do avatar (hex), usada como anel ao redor da foto.
  /// Opcional. O ícone em si é a foto (se houver) ou o ícone do app.
  String? avatarColor;

  /// Semente em texto puro — SÓ EM MEMÓRIA, populada no unlock. Fica `''`
  /// enquanto a conta está bloqueada. Nunca é persistida quando há [encSeed].
  String seed;

  /// Semente cifrada (AES-GCM + PIN via [SeedCrypto]) — o que vai para o disco.
  String? encSeed;

  String pinHash;

  AccountProfile({
    required this.id,
    required this.name,
    this.avatarColor,
    this.seed = '',
    this.encSeed,
    required this.pinHash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pinHash': pinHash,
        if (avatarColor != null) 'avatarColor': avatarColor,
        // Enquanto não há blob cifrado (conta legada ainda não migrada),
        // preserva o texto puro para não perder a semente. Assim que o unlock
        // cifra, só [encSeed] é gravado e o texto puro some do disco.
        if (encSeed != null) 'encSeed': encSeed else 'seed': seed,
      };

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        id: json['id'],
        name: json['name'],
        avatarColor: json['avatarColor'] as String?,
        seed:
            (json['seed'] as String?) ?? '', // legado; migra no primeiro unlock
        encSeed: json['encSeed'] as String?,
        pinHash: json['pinHash'],
      );
}

/// Notificação de pagamento recebido (Lightning ou on-chain).
class ReceivedPayment {
  final bool isMerchant;
  final String paymentHashHex; // vazio para recebimentos on-chain
  final int amountSats;
  final bool isOnchain;

  /// Chegou mas ainda está no mempool, sem confirmação em bloco. A UI avisa
  /// de forma diferente: "recebendo" (pendente) x "recebido" (confirmado).
  final bool isPending;

  /// Não é dinheiro novo: é uma entrada que ESTAVA pendente e acabou de
  /// confirmar. Serve para notificar a confirmação sem somar duas vezes.
  final bool isConfirmation;

  ReceivedPayment({
    required this.isMerchant,
    required this.paymentHashHex,
    required this.amountSats,
    this.isOnchain = false,
    this.isPending = false,
    this.isConfirmation = false,
  });
}

/// Encapsula um nó por perfil (consumidor ou lojista), cada um com a
/// própria seed e diretório de dados — princípio não-custodial por conta.
/// O backend pode ser embarcado (FFI) ou um daemon local (RPC em 127.0.0.1).
class _NodeHandle {
  NodeApi? api;
  bool isRunning = false;
  bool isMock = false; // fallback de UI quando o motor nativo não carrega
  String? lastStartError; // motivo real da falha de inicialização (diagnóstico)
  bool isMerchant = false;
  bool isRemote = false; // true quando conectado ao daemon local
  int lightningBalanceSats = 0;
  int onchainBalanceSats = 0; // total (inclui o que ainda não confirmou)

  /// Parte do saldo on-chain já confirmada e gastável. A diferença para o
  /// total é exatamente o que está pendente no mempool.
  int onchainSpendableSats = 0;
  bool balancesInitialized = false;
  String? fixedInvoice;

  /// Endereço on-chain atual para receber. Só troca depois de um recebimento
  /// (ver [WalletService._refreshBalances]) — sem isto, cada tela de recebe
  /// aberta chamava `newOnchainAddress()` de novo (índice `AddressIndex::New`
  /// do BDK sempre avança), e o app parecia "trocar o endereço sozinho" a
  /// cada abertura, além de queimar índices de derivação sem necessidade.
  String? cachedOnchainAddress;

  /// De qual semente é o nó que está rodando. Como existe um nó só, é isto que
  /// diz se o saldo exibido pertence mesmo ao perfil que está na tela.
  String? runningSeedFingerprint;

  /// Semente em texto puro do nó em execução — só para poder REINICIAR o nó
  /// (ver [WalletService._ensureSyncTimer]) sem depender de decifrar de novo.
  /// Não é exposição nova: a seed já vive em memória em [AccountProfile.seed]
  /// durante a sessão desbloqueada.
  String? runningSeed;

  /// Falhas de sincronização seguidas. Cresce a cada tick que falha, zera no
  /// primeiro sucesso — usado para detectar um backend Esplora degradado (ex.:
  /// começou a limitar por taxa) e disparar a recuperação automática.
  int consecutiveSyncFailures = 0;

  /// Já houve pelo menos um sync bem-sucedido nesta execução do nó. Antes
  /// disso, um saldo zero é suspeito (o ldk_node pode estar devolvendo cache
  /// enquanto sincroniza) e não deve apagar o último valor conhecido.
  bool saldoConfirmadoPorSync = false;
  bool _eventLoopActive = false;

  /// Saldo total do nó em sats: Lightning + Bitcoin on-chain.
  int get totalSats => lightningBalanceSats + onchainBalanceSats;

  Future<void> stop() async {
    _eventLoopActive = false;
    try {
      await api?.stop();
    } catch (_) {}
    api = null;
    isRunning = false;
    balancesInitialized = false;
    saldoConfirmadoPorSync = false;
    lightningBalanceSats = 0;
    onchainBalanceSats = 0;
    onchainSpendableSats = 0;
    // A fatura fixa pertence à conta que estava ativa. Se ficasse aqui, a
    // próxima conta exibiria o QR estático da anterior e o pagamento cairia
    // na carteira errada.
    fixedInvoice = null;
    // Mesmo raciocínio: o endereço on-chain é da conta que saiu.
    cachedOnchainAddress = null;
    lastStartError = null;
    runningSeedFingerprint = null;
    runningSeed = null;
    consecutiveSyncFailures = 0;
  }
}

class WalletService extends ChangeNotifier with WidgetsBindingObserver {
  WalletService() {
    // Observa o ciclo de vida para sincronizar ao voltar do segundo plano —
    // ver [didChangeAppLifecycleState].
    WidgetsBinding.instance.addObserver(this);
  }

  /// Sincroniza assim que o app volta ao primeiro plano.
  ///
  /// A MESMA carteira roda em vários aparelhos (mesma semente), mas cada um
  /// tem seu próprio banco do BDK e só descobre o que o outro fez ao
  /// sincronizar. Gastar no PC e depois abrir o celular mostrava o saldo
  /// anterior até o tick periódico (até 2 min). Sincronizar no retorno cobre
  /// exatamente o momento em que o usuário troca de aparelho.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final emUso = state == AppLifecycleState.resumed;
    if (emUso != _appEmPrimeiroPlano) {
      _appEmPrimeiroPlano = emUso;
      if (_syncTimer != null) _reagendarSyncTimer();
    }
    if (!emUso) return;
    final agora = DateTime.now();
    // Guarda contra rajadas: alternar janelas no desktop dispara `resumed`
    // várias vezes seguidas, e cada sync é caro.
    if (_ultimoSyncPorRetorno != null &&
        agora.difference(_ultimoSyncPorRetorno!) < const Duration(seconds: 20)) {
      return;
    }
    _ultimoSyncPorRetorno = agora;
    unawaited(_dispararSync?.call() ?? Future.value());
  }

  DateTime? _ultimoSyncPorRetorno;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<AccountProfile> _consumerAccounts = [];
  List<AccountProfile> _merchantAccounts = [];

  String? _activeConsumerId;
  String? _activeMerchantId;

  String? _tempConsumerSeed; // Usada durante a criação

  /// A semente em criação veio de uma RESTAURAÇÃO (usuário digitou as palavras)
  /// e não de uma geração nova. Faz diferença: uma carteira restaurada pode ter
  /// histórico em índices de derivação altos, que o BDK não enxerga sem uma
  /// varredura profunda (ver [deepScan]). Uma carteira nova nasce vazia e não
  /// precisa de nada disso.
  bool _tempSeedEhRestauracao = false;

  /// Varredura pós-restauração em andamento. A UI usa isto para explicar por
  /// que o saldo ainda pode aparecer zerado logo depois de restaurar.
  bool _restaurandoCarteira = false;
  bool get restaurandoCarteira => _restaurandoCarteira;

  bool _isUnlocked = false;
  bool _isMerchantUnlocked = false;
  bool _isNfcEnabled = false;
  String _lastSessionType = 'consumer';

  // --- Proteção contra brute-force do PIN (anti-força-bruta / anti-pentest) ---
  // Contador e bloqueio persistidos: reiniciar o app NÃO zera. O bloqueio é por
  // tempo, com backoff progressivo; opcionalmente apaga a carteira após N erros.
  int _pinFailedAttempts = 0;
  DateTime? _pinLockedUntil;

  /// Tentativas livres antes de o bloqueio temporal começar (tolera erro de
  /// digitação). Editável pelo usuário.
  int _pinFreeAttempts = 4;

  /// Política opcional: apagar todos os dados locais após [_autoWipeThreshold]
  /// tentativas erradas (defesa anti-roubo). Desligada por padrão. Editável.
  bool _autoWipeEnabled = false;
  int _autoWipeThreshold = 10;

  /// Backoff de bloqueio por tempo, aplicado a cada erro além das tentativas
  /// livres. O último valor é o teto.
  static const List<Duration> _pinLockSchedule = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  bool get isPinLocked =>
      _pinLockedUntil != null && DateTime.now().isBefore(_pinLockedUntil!);
  Duration get pinLockRemaining =>
      isPinLocked ? _pinLockedUntil!.difference(DateTime.now()) : Duration.zero;
  int get pinFailedAttempts => _pinFailedAttempts;
  int get pinFreeAttempts => _pinFreeAttempts;
  bool get autoWipeEnabled => _autoWipeEnabled;
  int get autoWipeThreshold => _autoWipeThreshold;

  /// Tentativas restantes antes do apagamento automático (−1 se desligado).
  int get pinAttemptsRemainingBeforeWipe => _autoWipeEnabled
      ? (_autoWipeThreshold - _pinFailedAttempts).clamp(0, _autoWipeThreshold)
      : -1;

  Duration _lockFor(int attempts) {
    final over = attempts - _pinFreeAttempts;
    if (over <= 0) return Duration.zero;
    return over - 1 < _pinLockSchedule.length
        ? _pinLockSchedule[over - 1]
        : _pinLockSchedule.last;
  }

  /// Registra uma tentativa de PIN errada: incrementa, aplica bloqueio e, se
  /// configurado, dispara o apagamento. Mutação em memória síncrona; persiste
  /// em segundo plano (serve tanto o caminho sync quanto o async).
  void _registerPinFailure() {
    _pinFailedAttempts++;
    final lock = _lockFor(_pinFailedAttempts);
    if (lock > Duration.zero) _pinLockedUntil = DateTime.now().add(lock);
    _persistPinGuard();
    if (_autoWipeEnabled && _pinFailedAttempts >= _autoWipeThreshold) {
      wipeAllData();
    }
    notifyListeners();
  }

  void _resetPinAttempts() {
    if (_pinFailedAttempts == 0 && _pinLockedUntil == null) return;
    _pinFailedAttempts = 0;
    _pinLockedUntil = null;
    _persistPinGuard();
    notifyListeners();
  }

  Future<void> _persistPinGuard() async {
    await _storage.write(
        key: 'pin_failed_attempts', value: '$_pinFailedAttempts');
    if (_pinLockedUntil != null) {
      await _storage.write(
          key: 'pin_locked_until', value: _pinLockedUntil!.toIso8601String());
    } else {
      await _storage.delete(key: 'pin_locked_until');
    }
  }

  /// Configuração da política de segurança do PIN — editável a qualquer momento.
  Future<void> setPinSecurityPolicy({
    int? freeAttempts,
    bool? autoWipeEnabled,
    int? autoWipeThreshold,
  }) async {
    if (freeAttempts != null) _pinFreeAttempts = freeAttempts.clamp(1, 10);
    if (autoWipeEnabled != null) _autoWipeEnabled = autoWipeEnabled;
    if (autoWipeThreshold != null) {
      _autoWipeThreshold = autoWipeThreshold.clamp(5, 100);
    }
    await _storage.write(key: 'pin_free_attempts', value: '$_pinFreeAttempts');
    await _storage.write(
        key: 'auto_wipe_enabled', value: _autoWipeEnabled ? '1' : '0');
    await _storage.write(
        key: 'auto_wipe_threshold', value: '$_autoWipeThreshold');
    notifyListeners();
  }

  // --- Bloqueio automático PASSIVO (substitui o botão manual "Bloquear") ---
  // O app tranca sozinho: por tempo de inatividade e/ou quando volta de
  // segundo plano (proxy prático de "o dispositivo foi bloqueado" — o Flutter
  // não recebe um sinal direto de tela travada, mas ir para segundo plano é o
  // sinal mais próximo disponível em todas as plataformas).

  /// Minutos de inatividade até travar sozinho. 0 = desligado (nunca por
  /// inatividade — ainda pode travar por [lockOnSuspend]).
  int _autoLockMinutes = 5;

  /// Tranca ao voltar de segundo plano (app minimizado, troca de app,
  /// dispositivo suspenso). Ligado por padrão.
  bool _lockOnSuspend = true;

  int get autoLockMinutes => _autoLockMinutes;
  bool get lockOnSuspend => _lockOnSuspend;

  Future<void> setAutoLockPolicy({int? minutes, bool? lockOnSuspend}) async {
    if (minutes != null) _autoLockMinutes = minutes.clamp(0, 120);
    if (lockOnSuspend != null) _lockOnSuspend = lockOnSuspend;
    await _storage.write(key: 'auto_lock_minutes', value: '$_autoLockMinutes');
    await _storage.write(
        key: 'lock_on_suspend', value: _lockOnSuspend ? '1' : '0');
    notifyListeners();
  }

  // --- Nó em segundo plano no Android ---
  // LIGADO por padrão: é o que permite avisar de um pagamento com o app
  // fechado. Sem o serviço em primeiro plano o Android suspende o processo, o
  // nó para de sincronizar e nenhuma notificação sai. O custo é a notificação
  // persistente "Nó Lightning ativo" — exigência do próprio Android, não uma
  // escolha do app. O usuário ainda pode desligar em Segurança.
  bool _keepNodeAliveInBackground = true;
  bool get keepNodeAliveInBackground => _keepNodeAliveInBackground;

  Future<void> setKeepNodeAliveInBackground(bool enabled) async {
    _keepNodeAliveInBackground = enabled;
    await _storage.write(
        key: 'keep_node_alive_background', value: enabled ? '1' : '0');
    if (enabled && _deviceNode.isRunning && _deviceNode.api != null) {
      await BackgroundServiceAndroid.start();
    } else if (!enabled) {
      await BackgroundServiceAndroid.stop();
    }
    notifyListeners();
  }

  // --- Privacidade: esconder o saldo na tela (opt-in) ---
  bool _hideBalance = false;
  bool get hideBalance => _hideBalance;

  Future<void> setHideBalance(bool hide) async {
    _hideBalance = hide;
    await _storage.write(key: 'hide_balance', value: hide ? '1' : '0');
    notifyListeners();
  }

  // --- Última aba de navegação (sobrevive a bloqueio/reabertura) ---
  // Guardado no serviço (singleton), então persiste enquanto o app vive —
  // inclusive ao travar e destravar. Também gravado em disco para sobreviver
  // ao app ser fechado por completo. Zerado ao trocar de conta (a nova conta
  // começa no Início). Sem notifyListeners: quem escreve é a própria Home,
  // que já gerencia o próprio setState.
  int _consumerTab = 0;
  int _merchantTab = 0;
  int get consumerTab => _consumerTab;
  int get merchantTab => _merchantTab;

  void setConsumerTab(int i) {
    _consumerTab = i;
    _storage.write(key: 'consumer_tab', value: '$i');
  }

  void setMerchantTab(int i) {
    _merchantTab = i;
    _storage.write(key: 'merchant_tab', value: '$i');
  }

  /// Apaga TODOS os dados locais sensíveis. A carteira só volta pela seed que o
  /// usuário anotou. Usado no apagamento automático anti-roubo e disponível
  /// como ação manual.
  Future<void> wipeAllData() async {
    try {
      await _consumerNode.stop();
    } catch (_) {}
    await _storage.deleteAll();
    _consumerAccounts = [];
    _merchantAccounts = [];
    _activeConsumerId = null;
    _activeMerchantId = null;
    _deviceSeed = null;
    _tempConsumerSeed = null;
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    _pinFailedAttempts = 0;
    _pinLockedUntil = null;
    notifyListeners();
  }

  double _cartTotal = 0;
  double _pendingChargeAmount = 0;

  /// Disparado ao trocar/criar/apagar conta, para que serviços externos
  /// (PIX, por exemplo) descartem estado da conta anterior. Ligado no main.dart
  /// — assim o WalletService não precisa conhecer o PixService.
  VoidCallback? onAccountChanged;

  /// Disparado ao importar um catálogo. Cobranças em cache pertencem à sessão
  /// anterior; depois de importar, todo QR precisa ser gerado de novo contra a
  /// carteira DESTE aparelho. Ligado no main.dart.
  VoidCallback? onCatalogImported;

  /// UM nó por dispositivo, não por conta.
  ///
  /// Dois nós LDK sobre a mesma seed é a forma clássica de perder fundos em
  /// Lightning: estados de canal divergentes permitem que a contraparte puna
  /// a publicação de um estado antigo. E, mesmo com seeds distintas, dois nós
  /// no mesmo aparelho disputavam portas e recursos à toa.
  ///
  /// Consequência do modelo: a carteira pessoal e a loja são PERFIS sobre a
  /// mesma carteira — mesmo saldo, mesmo nó, mesma seed do dispositivo.
  final _NodeHandle _deviceNode = _NodeHandle();

  _NodeHandle get _consumerNode => _deviceNode;
  _NodeHandle get _merchantNode => _deviceNode;

  /// Semente com que o aparelho começou. Serve só para a migração das pastas
  /// antigas — cada conta continua com a sua, e a loja escolhe a dela.
  String? _deviceSeed;
  String? get deviceSeed => _deviceSeed;

  /// Nome da pasta de dados derivado da SEMENTE, não da conta.
  ///
  /// É isso que faz duas contas com a mesma semente compartilharem carteira
  /// (e saldo) sem nunca rodarem dois nós: elas apontam para os mesmos dados.
  /// Sementes diferentes ficam em pastas diferentes, cada uma intacta.
  ///
  /// O prefixo `tn4_` isola os dados da testnet4: as pastas antigas (`ldk_…`,
  /// da testnet3) deixam de ser lidas. Reaproveitar o mesmo diretório entre
  /// cadeias diferentes corromperia a sincronização — o BDK teria UTXOs de uma
  /// rede e o LDK blocos de outra. As pastas velhas ficam no disco, inertes,
  /// até serem apagadas de propósito.
  /// Pasta de dados do nó, com a rede no nome.
  ///
  /// `tn4n` = testnet4 NATIVA (ldk-node 0.7.0). As pastas `ldk_tn4_` antigas
  /// foram criadas quando o app ainda anunciava o ChainHash da testnet3 — o
  /// estado do LDK lá dentro pertence a outra cadeia e ele recusaria abrir.
  /// Prefixo novo = começar limpo, sem apagar nada do que já existe no disco.
  ///
  /// Os fundos não se perdem: eles vivem na blockchain, e a carteira é
  /// reconstruída da mesma semente (ver a varredura em [deepScan] para índices
  /// de endereço altos).
  static String _nodeDirFor(String seed) =>
      'ldk_tn4n_${_seedFingerprint(seed)}';

  /// Identificador curto e estável da semente. Hash, nunca a semente em si —
  /// o nome da pasta não pode vazar a chave da carteira.
  static String _seedFingerprint(String seed) {
    final normal = seed.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return sha256.convert(utf8.encode(normal)).toString().substring(0, 16);
  }

  Timer? _syncTimer;

  final StreamController<ReceivedPayment> _paymentsCtrl =
      StreamController<ReceivedPayment>.broadcast();

  /// Stream de pagamentos recebidos (eventos reais do LDK).
  Stream<ReceivedPayment> get paymentsReceived => _paymentsCtrl.stream;

  /// Distingue um offer BOLT12 (prefixo `lno`) de uma fatura BOLT11
  /// (`lnbc`/`lntb`/`lnbcrt`). O offer é reutilizável; a fatura, não.
  static bool ehOfferBolt12(String? codigo) =>
      codigo != null && codigo.trim().toLowerCase().startsWith('lno');

  /// True quando o QR Lightning exibido pode ser reusado indefinidamente.
  bool get qrLightningEhReutilizavel => ehOfferBolt12(_deviceNode.fixedInvoice);

  /// Publica o recebimento: no stream (avisos dentro do app) e na bandeja do
  /// sistema. Fica aqui, e não na UI, para o aviso sair mesmo com o app em
  /// segundo plano ou numa tela que não escuta o stream.
  void _emitirRecebimento(ReceivedPayment p) {
    _paymentsCtrl.add(p);
    unawaited(_notificarNoSistema(p));
  }

  Future<void> _notificarNoSistema(ReceivedPayment p) async {
    final valor = '${_formatarSats(p.amountSats)} sats';
    final via = p.isOnchain ? 'on-chain' : 'Lightning';
    final conta = p.isMerchant ? 'Loja' : 'Carteira pessoal';

    late final String titulo;
    late final String corpo;
    if (p.isConfirmation) {
      titulo = 'Transação confirmada';
      corpo = '$valor $via já disponível · $conta';
    } else if (p.isPending) {
      titulo = 'Recebendo $valor';
      corpo = 'Aguardando confirmação da rede $via · $conta';
    } else {
      titulo = 'Você recebeu $valor';
      corpo = 'Via $via · $conta';
    }

    // Um id por (conta, tipo de rede): a confirmação SUBSTITUI o aviso de
    // pendente do mesmo depósito em vez de empilhar dois na bandeja.
    final id = (p.isMerchant ? 200 : 100) + (p.isOnchain ? 1 : 0);
    await NotificationService.mostrarRecebimento(
        id: id, titulo: titulo, corpo: corpo);
  }

  static String _formatarSats(int sats) {
    final s = sats.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  bool get isNodeRunning => _consumerNode.isRunning;
  bool get isMerchantNodeRunning => _merchantNode.isRunning;

  String? get mainWalletFixedInvoice => _consumerNode.fixedInvoice;
  String? get merchantFixedInvoice => _merchantNode.fixedInvoice;

  AccountProfile? get activeConsumer {
    try {
      return _consumerAccounts.firstWhere((a) => a.id == _activeConsumerId);
    } catch (e) {
      return null;
    }
  }

  AccountProfile? get activeMerchant {
    try {
      return _merchantAccounts.firstWhere((a) => a.id == _activeMerchantId);
    } catch (e) {
      return null;
    }
  }

  List<AccountProfile> get consumerAccounts => _consumerAccounts;
  List<AccountProfile> get merchantAccounts => _merchantAccounts;

  bool get hasConsumerPin =>
      activeConsumer != null || _tempConsumerSeed != null;
  bool get isUnlocked => _isUnlocked;

  /// A semente é do dispositivo. Durante a criação, mostra a temporária.
  String? get consumerSeed => _tempConsumerSeed ?? activeConsumer?.seed;

  /// True quando já existe uma semente recém-gerada esperando confirmação.
  /// A tela de criação usa isto para saber se ainda precisa perguntar o
  /// tamanho — [consumerSeed] não serve, porque devolve a seed do aparelho.
  bool get temSementeEmCriacao => _tempConsumerSeed != null;

  bool get hasMerchant => _merchantAccounts.isNotEmpty;
  bool get isMerchantUnlocked => _isMerchantUnlocked;
  bool get isNfcEnabled => _isNfcEnabled;
  String? get activeConsumerId => _activeConsumerId;
  String get lastSessionType => _lastSessionType;

  double get cartTotal => _cartTotal;
  double get pendingChargeAmount => _pendingChargeAmount;

  void addToCart(double amount) {
    _cartTotal += amount;
    notifyListeners();
  }

  void clearCart() {
    _cartTotal = 0;
    notifyListeners();
  }

  void setPendingCharge(double amount) {
    _pendingChargeAmount = amount;
    notifyListeners();
  }

  void clearPendingCharge() {
    _pendingChargeAmount = 0;
    notifyListeners();
  }

  /// A loja tem a semente que o lojista escolheu — nova ou importada. Se ele
  /// importar a da carteira pessoal, as duas passam a compartilhar carteira e
  /// saldo, porque a pasta do nó é derivada da semente.
  String? get merchantSeed => activeMerchant?.seed;
  String? get merchantName => activeMerchant?.name;

  List<Product> _merchantProducts = [];
  List<Product> get merchantProducts => _merchantProducts;

  final List<Transaction> _consumerTransactions = [];
  final List<Transaction> _merchantTransactions = [];

  /// Saldo unificado em sats (moeda principal do app): Lightning + on-chain.
  /// O saldo L-BTC da Liquid é somado na camada de UI via LiquidWalletService.
  /// O saldo só é atribuído a um perfil se o nó no ar for o DELE. Existe um nó
  /// só; sem esta checagem, ao abrir a loja o app mostraria na carteira pessoal
  /// o saldo da loja. Quando as duas usam a mesma semente, ambas batem — que é
  /// justamente o caso de saldo compartilhado.
  bool _noEDoPerfil(String? seed) =>
      seed != null &&
      _deviceNode.runningSeedFingerprint == _seedFingerprint(seed);

  // Quando o nó no ar não é o do perfil (boot, troca de conta, reinício por
  // sync degradado), mostramos o ÚLTIMO saldo verificado daquela semente em vez
  // de zero. Zerar a tela por alguns segundos assusta sem motivo — o dinheiro
  // não sumiu, é o nó que ainda não está pronto. Ver [_saldoDeReserva].
  int get consumerBalance => _noEDoPerfil(activeConsumer?.seed)
      ? _deviceNode.totalSats
      : _somaReserva(activeConsumer?.seed);
  int get merchantBalance => _noEDoPerfil(activeMerchant?.seed)
      ? _deviceNode.totalSats
      : _somaReserva(activeMerchant?.seed);
  int get consumerLightningSats => _noEDoPerfil(activeConsumer?.seed)
      ? _deviceNode.lightningBalanceSats
      : _saldoDeReserva(activeConsumer?.seed).lightning;
  int get consumerOnchainSats => _noEDoPerfil(activeConsumer?.seed)
      ? _deviceNode.onchainBalanceSats
      : _saldoDeReserva(activeConsumer?.seed).total;
  int get merchantLightningSats => _noEDoPerfil(activeMerchant?.seed)
      ? _deviceNode.lightningBalanceSats
      : _saldoDeReserva(activeMerchant?.seed).lightning;
  int get merchantOnchainSats => _noEDoPerfil(activeMerchant?.seed)
      ? _deviceNode.onchainBalanceSats
      : _saldoDeReserva(activeMerchant?.seed).total;

  int _somaReserva(String? seed) {
    final r = _saldoDeReserva(seed);
    return r.total + r.lightning;
  }

  /// True quando o número na tela é o último valor verificado e não uma
  /// leitura ao vivo — o nó do perfil ainda está subindo. A UI avisa em vez de
  /// deixar o usuário achar que o saldo está errado.
  bool get saldoDesatualizado {
    final seed = _isMerchantUnlocked && !_isUnlocked
        ? activeMerchant?.seed
        : activeConsumer?.seed;
    return seed != null && seed.isNotEmpty && !_noEDoPerfil(seed);
  }

  /// Sats on-chain que já apareceram na carteira mas ainda estão no mempool.
  ///
  /// Vem da soma das entradas marcadas como pendentes, e NÃO de
  /// `total - gastável`: o ldk_node desconta a reserva dos canais âncora do
  /// saldo gastável, então aquela subtração acusaria um pendente fantasma do
  /// tamanho da reserva sempre que houvesse um canal aberto.
  int _pendingOnchainDe(List<Transaction> txs) => txs
      .where((t) => t.isIncoming && t.status == 'pending')
      .fold(0, (soma, t) => soma + t.amountSats);

  int get consumerPendingOnchainSats =>
      _noEDoPerfil(activeConsumer?.seed) && _consumerTransactions.isNotEmpty
          ? _pendingOnchainDe(_consumerTransactions)
          : 0;
  int get merchantPendingOnchainSats =>
      _noEDoPerfil(activeMerchant?.seed) && _merchantTransactions.isNotEmpty
          ? _pendingOnchainDe(_merchantTransactions)
          : 0;

  int pendingOnchainSats({required bool isMerchant}) =>
      isMerchant ? merchantPendingOnchainSats : consumerPendingOnchainSats;

  // --- Histórico persistido e cifrado --------------------------------------
  //
  // Todo movimento fica gravado, sem limite de quantidade, cifrado com
  // AES-256-GCM por uma chave exclusiva da conta (ver [VaultCrypto]). Antes
  // disso o histórico só existia em memória e sumia a cada abertura do app.

  final Map<String, SecretKey> _chavesDeHistorico = {};

  Future<SecretKey?> _chaveDoHistorico(bool isMerchant) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return null;
    final conta = isMerchant ? activeMerchant : activeConsumer;
    final seed = conta?.seed;
    if (seed == null || seed.isEmpty) return null; // bloqueada: sem chave
    final cache = _chavesDeHistorico[id];
    if (cache != null) return cache;
    final k = await VaultCrypto.deriveKey(seed: seed, accountId: id);
    _chavesDeHistorico[id] = k;
    return k;
  }

  String? _chaveDeArmazenamentoHistorico(bool isMerchant) {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    return id == null ? null : 'tx_hist_v2_$id';
  }

  Future<void> _carregarHistorico(bool isMerchant) async {
    final storeKey = _chaveDeArmazenamentoHistorico(isMerchant);
    final cryptoKey = await _chaveDoHistorico(isMerchant);
    final destino = isMerchant ? _merchantTransactions : _consumerTransactions;
    if (storeKey == null || cryptoKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final blob = prefs.getString(storeKey);
      if (blob == null || blob.isEmpty) return;
      final claro = await VaultCrypto.decrypt(blob, cryptoKey);
      if (claro == null) {
        debugPrint('Histórico ilegível (chave não confere) — começando vazio.');
        return;
      }
      final lista = (jsonDecode(claro) as List<dynamic>)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList();
      // Mais recente sempre no topo. Ordenar aqui (e não só ao inserir) cobre
      // o extrato que veio do disco e o reconstruído do nó, que chegam em
      // ordem qualquer.
      lista.sort((a, b) => b.date.compareTo(a.date));
      destino
        ..clear()
        ..addAll(lista);
    } catch (e) {
      debugPrint('Falha ao carregar histórico: $e');
    }
  }

  /// Grava o histórico cifrado. Sem corte por quantidade: tudo que aconteceu
  /// na carteira continua disponível.
  Future<void> _salvarHistorico(bool isMerchant) async {
    final storeKey = _chaveDeArmazenamentoHistorico(isMerchant);
    final cryptoKey = await _chaveDoHistorico(isMerchant);
    if (storeKey == null || cryptoKey == null) return;
    try {
      final lista = isMerchant ? _merchantTransactions : _consumerTransactions;
      final json = jsonEncode(lista.map((t) => t.toJson()).toList());
      final blob = await VaultCrypto.encrypt(json, cryptoKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storeKey, blob);
    } catch (e) {
      debugPrint('Falha ao salvar histórico: $e');
    }
  }

  Future<void> _apagarHistoricoDaConta(String accountId) async {
    _chavesDeHistorico.remove(accountId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('tx_hist_v2_$accountId');
    } catch (e) {
      debugPrint('Falha ao apagar histórico da conta: $e');
    }
  }

  /// Quantos endereços cada aparelho precisa ter em cache para enxergar o que
  /// os outros usaram. O BDK só consulta na rede os endereços que já tem
  /// gravados, e CADA aparelho tem seu próprio contador de derivação: um
  /// endereço criado no celular pode cair fora da janela do PC, e aí o PC
  /// nunca pergunta por ele — foi essa a causa dos saldos diferentes entre
  /// dispositivos da MESMA carteira.
  static const int _janelaDeEnderecos = 200;

  /// Amplia a janela uma única vez por carteira (registrado em disco), porque
  /// revelar endereços avança o contador e não deve virar rotina.
  Future<void> _garantirJanelaDeEnderecos(_NodeHandle handle) async {
    final fp = handle.runningSeedFingerprint;
    if (fp == null || handle.api == null) return;
    // Progresso é gravado a cada lote. Uma versão anterior fazia as 200
    // chamadas de uma vez e só marcava "pronto" no fim — se o processo caísse
    // no meio (visto no Android: 4 crashes seguidos logo após o start do nó),
    // a próxima abertura recomeçava do zero e caía de novo, virando um ciclo.
    // Retomar de onde parou quebra esse ciclo.
    final chaveFeitos = 'janela_enderecos_v2_$fp';
    const porLote = 25;
    try {
      final prefs = await SharedPreferences.getInstance();
      var feitos = prefs.getInt(chaveFeitos) ?? 0;
      if (feitos >= _janelaDeEnderecos) return; // já completo nesta carteira

      while (feitos < _janelaDeEnderecos) {
        final alvo = (feitos + porLote).clamp(0, _janelaDeEnderecos);
        for (; feitos < alvo; feitos++) {
          try {
            final addr = await handle.api!.newOnchainAddress();
            await _registrarEnderecoProprio(addr);
          } catch (e) {
            // Uma falha isolada não pode derrubar a ampliação inteira.
            debugPrint('Endereço $feitos da janela falhou: $e');
          }
        }
        await prefs.setInt(chaveFeitos, feitos);
        // Respira entre lotes: 200 chamadas nativas em rajada competem com a
        // thread de UI e com o próprio boot do nó.
        await Future.delayed(const Duration(milliseconds: 200));
      }

      debugPrint(
          'Janela de $_janelaDeEnderecos endereços garantida — este aparelho '
          'passa a enxergar o que os outros usaram.');
      await atualizarAgora();
    } catch (e) {
      debugPrint('Falha ao ampliar a janela de endereços: $e');
    }
  }

  /// Reconstrói o extrato Lightning a partir do que o NÓ guardou em disco.
  ///
  /// Duas situações em que isso salva o usuário:
  ///  - versões antigas do app não persistiam nada, então todo o histórico
  ///    sumia a cada abertura;
  ///  - ao restaurar a carteira em outro aparelho, o extrato local nasce vazio.
  ///
  /// O registro do LDK vive no diretório do nó e é independente do nosso, o
  /// que o torna uma fonte de verdade para recuperar o que perdemos. Entradas
  /// que já existem são ignoradas (o `id` é o mesmo), então rodar de novo não
  /// duplica nada.
  Future<int> reconstruirHistoricoDoNo({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (handle.api == null) return 0;

    final lista =
        forMerchant ? _merchantTransactions : _consumerTransactions;
    var recuperadas = 0;
    try {
      for (final p in await handle.api!.listPayments()) {
        if (p.amountSats <= 0) continue;
        if (lista.any((t) => t.id == p.id)) continue;
        // Rotular pelo tipo REAL do movimento. Antes tudo virava "Lightning",
        // o que fazia a carteira exibir recebimentos Lightning sem nunca ter
        // tido um canal aberto — os movimentos eram on-chain.
        lista.add(Transaction(
          id: p.id,
          title: p.isOnchain
              ? (p.isIncoming
                  ? 'Recebido on-chain (Bitcoin)'
                  : 'Envio on-chain (Bitcoin)')
              : (p.isIncoming
                  ? (forMerchant ? 'Venda recebida' : 'Recebido via Lightning')
                  : 'Pagamento Lightning'),
          emoji: p.isOnchain ? '₿' : '⚡',
          amountSats: p.amountSats,
          isIncoming: p.isIncoming,
          date: p.date,
          status: p.status,
        ));
        recuperadas++;
      }
      if (recuperadas > 0) {
        // Mais recentes primeiro, como o resto do app espera.
        lista.sort((a, b) => b.date.compareTo(a.date));
        await _salvarHistorico(forMerchant);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Falha ao reconstruir histórico: $e');
    }
    return recuperadas;
  }

  /// Registra um movimento: entra na lista da carteira certa e é gravado
  /// cifrado na hora. Único ponto por onde o histórico cresce.
  void _registrarTransacao(Transaction tx, {required bool isMerchant}) {
    final lista = isMerchant ? _merchantTransactions : _consumerTransactions;
    // Idempotência: eventos repetidos do LDK (ou um sync que reprocessa)
    // não podem duplicar a mesma linha no extrato.
    if (tx.id.isNotEmpty && lista.any((t) => t.id == tx.id)) return;
    lista.add(tx);
    // Ordena por data em vez de só inserir no topo: um movimento pode chegar
    // com data anterior à do último registrado (ex.: extrato reconstruído do
    // nó, ou evento processado fora de ordem).
    lista.sort((a, b) => b.date.compareTo(a.date));
    unawaited(_salvarHistorico(isMerchant));
  }

  /// Transações que ainda aguardam confirmação, mais recentes primeiro.
  List<Transaction> pendingTransactions({required bool isMerchant}) =>
      (isMerchant ? _merchantTransactions : _consumerTransactions)
          .where((t) => t.status == 'pending')
          .toList();

  List<Transaction> get consumerTransactions => _consumerTransactions;
  List<Transaction> get merchantTransactions => _merchantTransactions;

  // ---------------------------------------------------------------------
  // PIN: PBKDF2-HMAC-SHA256 com salt (migração automática do legado SHA-256)
  // ---------------------------------------------------------------------

  static const int _pbkdf2Iterations = 20000;

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexToBytes(String hexStr) => [
        for (int i = 0; i < hexStr.length; i += 2)
          int.parse(hexStr.substring(i, i + 2), radix: 16)
      ];

  static List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    // Um bloco de 32 bytes é suficiente para length <= 32
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final output = List<int>.from(u);
    for (int i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < output.length; j++) {
        output[j] ^= u[j];
      }
    }
    return output.sublist(0, length);
  }

  static String hashPin(String pin) {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = _pbkdf2(utf8.encode(pin), salt, _pbkdf2Iterations, 32);
    return 'v2\$$_pbkdf2Iterations\$${_bytesToHex(salt)}\$${_bytesToHex(hash)}';
  }

  static bool verifyPin(String pin, String stored) {
    if (stored.startsWith('v2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]) ?? _pbkdf2Iterations;
      final salt = _hexToBytes(parts[2]);
      final expected = parts[3];
      final hash = _bytesToHex(_pbkdf2(utf8.encode(pin), salt, iterations, 32));
      // Comparação em tempo constante
      if (hash.length != expected.length) return false;
      int diff = 0;
      for (int i = 0; i < hash.length; i++) {
        diff |= hash.codeUnitAt(i) ^ expected.codeUnitAt(i);
      }
      return diff == 0;
    }
    // Legado: SHA-256 puro
    return sha256.convert(utf8.encode(pin)).toString() == stored;
  }

  bool _isLegacyHash(String stored) => !stored.startsWith('v2\$');

  // ---------------------------------------------------------------------
  // Persistência de contas
  // ---------------------------------------------------------------------

  Future<void> _saveConsumers() async {
    final encoded =
        jsonEncode(_consumerAccounts.map((e) => e.toJson()).toList());
    await _storage.write(key: 'consumer_accounts', value: encoded);
    if (_activeConsumerId != null) {
      await _storage.write(
          key: 'active_consumer_id', value: _activeConsumerId!);
    } else {
      await _storage.delete(key: 'active_consumer_id');
    }
  }

  Future<void> _saveMerchants() async {
    final encoded =
        jsonEncode(_merchantAccounts.map((e) => e.toJson()).toList());
    await _storage.write(key: 'merchant_accounts', value: encoded);
    if (_activeMerchantId != null) {
      await _storage.write(
          key: 'active_merchant_id', value: _activeMerchantId!);
    } else {
      await _storage.delete(key: 'active_merchant_id');
    }
  }

  Future<void> _saveLastSession() async {
    await _storage.write(key: 'last_session_type', value: _lastSessionType);
  }

  Future<void> initWallet() async {
    // Estado da proteção anti-brute-force (persistido entre reinícios).
    _pinFailedAttempts =
        int.tryParse(await _storage.read(key: 'pin_failed_attempts') ?? '') ??
            0;
    final lockedUntilStr = await _storage.read(key: 'pin_locked_until');
    _pinLockedUntil =
        lockedUntilStr != null ? DateTime.tryParse(lockedUntilStr) : null;
    _pinFreeAttempts =
        int.tryParse(await _storage.read(key: 'pin_free_attempts') ?? '') ?? 4;
    _autoWipeEnabled = (await _storage.read(key: 'auto_wipe_enabled')) == '1';
    _autoWipeThreshold =
        int.tryParse(await _storage.read(key: 'auto_wipe_threshold') ?? '') ??
            10;
    _autoLockMinutes =
        int.tryParse(await _storage.read(key: 'auto_lock_minutes') ?? '') ?? 5;
    // Padrão ligado: só desliga se o usuário explicitamente gravou '0'.
    _lockOnSuspend = (await _storage.read(key: 'lock_on_suspend')) != '0';
    // Mesma regra do lock: ligado por padrão, só desliga se o usuário gravou
    // '0'. É o que sustenta as notificações de recebimento com o app fechado.
    _keepNodeAliveInBackground =
        (await _storage.read(key: 'keep_node_alive_background')) != '0';
    _hideBalance = (await _storage.read(key: 'hide_balance')) == '1';
    _consumerTab =
        int.tryParse(await _storage.read(key: 'consumer_tab') ?? '') ?? 0;
    _merchantTab =
        int.tryParse(await _storage.read(key: 'merchant_tab') ?? '') ?? 0;

    final consumersStr = await _storage.read(key: 'consumer_accounts');
    if (consumersStr != null) {
      final List decoded = jsonDecode(consumersStr);
      _consumerAccounts =
          decoded.map((e) => AccountProfile.fromJson(e)).toList();
      _activeConsumerId = await _storage.read(key: 'active_consumer_id');

      final nfcSaved = await _storage.read(key: 'nfc_enabled');
      if (nfcSaved != null) {
        _isNfcEnabled = nfcSaved == 'true';
      }
    } else {
      final legacySeed = await _storage.read(key: 'consumer_seed');
      final legacyPin = await _storage.read(key: 'consumer_pin_hash');
      if (legacySeed != null && legacyPin != null) {
        final profile = AccountProfile(
            id: 'legacy_consumer',
            name: 'Carteira Pessoal 1',
            seed: legacySeed,
            pinHash: legacyPin);
        _consumerAccounts.add(profile);
        _activeConsumerId = profile.id;
        await _saveConsumers();
      }
    }

    final merchantsStr = await _storage.read(key: 'merchant_accounts');
    if (merchantsStr != null) {
      final List decoded = jsonDecode(merchantsStr);
      _merchantAccounts =
          decoded.map((e) => AccountProfile.fromJson(e)).toList();
      _activeMerchantId = await _storage.read(key: 'active_merchant_id');
      // Dados vindos de versões antigas podem ter lojas salvas sem o id ativo,
      // ou apontar para uma loja que já não existe. Sem um id válido a chave do
      // catálogo fica nula e os produtos somem. Cai na primeira loja.
      final idValido = _activeMerchantId != null &&
          _merchantAccounts.any((a) => a.id == _activeMerchantId);
      if (!idValido && _merchantAccounts.isNotEmpty) {
        _activeMerchantId = _merchantAccounts.first.id;
        await _saveMerchants();
      }
    } else {
      final legacySeed = await _storage.read(key: 'merchant_seed');
      final legacyPin = await _storage.read(key: 'merchant_pin_hash');
      final legacyName =
          await _storage.read(key: 'merchant_name') ?? 'Minha Loja 1';
      if (legacySeed != null && legacyPin != null) {
        final profile = AccountProfile(
            id: 'legacy_merchant',
            name: legacyName,
            seed: legacySeed,
            pinHash: legacyPin);
        _merchantAccounts.add(profile);
        _activeMerchantId = profile.id;
        await _saveMerchants();
      }
    }

    // Catálogo da loja: carregado AQUI, junto do perfil, e não mais dentro do
    // _startNode. Antes, se o nó falhasse ou demorasse a subir, os produtos
    // nunca eram carregados e pareciam apagados a cada abertura do app.
    _deviceSeed = await _storage.read(key: 'device_seed');
    // Cada carteira passa a viver na pasta derivada da própria semente.
    await _migrarPastasDoNo();

    ProductImageStore.definirLoja(_activeMerchantId);
    await _loadMerchantProducts();
    // Versões anteriores guardavam as fotos numa pasta única; traz para a
    // pasta desta loja as que ela referencia.
    await ProductImageStore.migrarDaRaiz(
      _merchantProducts.map((p) => p.image).whereType<String>().toSet(),
    );

    final lastSession = await _storage.read(key: 'last_session_type');
    if (lastSession != null) {
      _lastSessionType = lastSession;
    } else {
      if (_consumerAccounts.isNotEmpty) {
        _lastSessionType = 'consumer';
      } else if (_merchantAccounts.isNotEmpty) {
        _lastSessionType = 'merchant';
      }
    }
  }

  Future<void> setLastSessionType(String type) async {
    _lastSessionType = type;
    await _saveLastSession();
  }

  /// Edita o perfil ATIVO (nome e/ou cor de destaque). Editável a qualquer
  /// momento. A foto é gerenciada à parte, em [AvatarImageStore].
  Future<void> updateActiveProfile({
    required bool isMerchant,
    String? name,
    String? avatarColor,
  }) async {
    final p = isMerchant ? activeMerchant : activeConsumer;
    if (p == null) return;
    if (name != null && name.trim().isNotEmpty) p.name = name.trim();
    if (avatarColor != null) {
      p.avatarColor = avatarColor.isEmpty ? null : avatarColor;
    }
    if (isMerchant) {
      await _saveMerchants();
    } else {
      await _saveConsumers();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Troca de PIN
  // ---------------------------------------------------------------------

  /// Troca o PIN de uma conta. Como a seed fica cifrada com uma chave
  /// derivada do PIN ([SeedCrypto]), isto não é só trocar um hash: decifra
  /// com o PIN atual e recifra com o novo. Se esta conta compartilha a
  /// semente do dispositivo, o `device_seed` cifrado também é atualizado —
  /// senão outras contas na mesma semente perderiam acesso a ela.
  Future<bool> _changePin({
    required AccountProfile? account,
    required String oldPin,
    required String newPin,
    required Future<void> Function() persist,
  }) async {
    if (account == null) return false;
    if (isPinLocked) return false; // sob bloqueio anti-força-bruta
    if (newPin.trim().length < 4) return false;

    String seed;
    if (SeedCrypto.isEncrypted(account.encSeed)) {
      try {
        seed = await SeedCrypto.decryptInBackground(account.encSeed!, oldPin);
      } on SeedDecryptException {
        _registerPinFailure();
        return false;
      }
    } else {
      // Legado: ainda não migrado para cifrado.
      if (!verifyPin(oldPin, account.pinHash)) {
        _registerPinFailure();
        return false;
      }
      seed = account.seed;
    }

    account.seed = seed;
    account.encSeed = await SeedCrypto.encryptInBackground(seed, newPin);
    account.pinHash = hashPin(newPin);

    // Esta conta é dona da semente do dispositivo? Recifra com o novo PIN.
    if (_deviceSeed != null && _deviceSeed == seed) {
      await _definirSeedDoDispositivo(seed, newPin);
    }

    await persist();
    _resetPinAttempts();
    notifyListeners();
    return true;
  }

  Future<bool> changeConsumerPin(String oldPin, String newPin) => _changePin(
        account: activeConsumer,
        oldPin: oldPin,
        newPin: newPin,
        persist: _saveConsumers,
      );

  Future<bool> changeMerchantPin(String oldPin, String newPin) => _changePin(
        account: activeMerchant,
        oldPin: oldPin,
        newPin: newPin,
        persist: _saveMerchants,
      );

  // ---------------------------------------------------------------------
  // Backup de perfil (transferir configurações entre dispositivos/contas)
  // ---------------------------------------------------------------------

  /// Versão do formato do backup. Só perfil e preferências trafegam — nunca
  /// seed, PIN ou qualquer chave: um arquivo exportado não dá acesso à
  /// carteira nem move fundos.
  static const int profileBackupFormatVersion = 1;

  /// Serializa o perfil ativo (nome, avatar, preferências de segurança que não
  /// são segredo) para transferir a outro dispositivo ou outra conta.
  Future<String> exportProfileBackup({required bool isMerchant}) async {
    final p = isMerchant ? activeMerchant : activeConsumer;
    if (p == null) throw StateError('Nenhum perfil ativo para exportar.');

    final json = <String, dynamic>{
      'iris_profile_backup': profileBackupFormatVersion,
      'exportado_em': DateTime.now().toIso8601String(),
      'name': p.name,
      if (p.avatarColor != null) 'avatarColor': p.avatarColor,
      // Preferências de segurança (não-secretas): úteis de levar junto, mas
      // sem nenhum dado que abra a carteira.
      'pinFreeAttempts': _pinFreeAttempts,
      'autoWipeEnabled': _autoWipeEnabled,
      'autoWipeThreshold': _autoWipeThreshold,
      'autoLockMinutes': _autoLockMinutes,
      'lockOnSuspend': _lockOnSuspend,
    };

    final avatarBytes = await AvatarImageStore.lerBytes(p.id);
    if (avatarBytes != null) {
      json['avatarImage'] = base64Encode(avatarBytes);
    }

    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Aplica um backup exportado ao perfil ATIVO (não recria contas nem toca
  /// em seed/PIN). [isMerchant] escolhe se afeta o perfil pessoal ou de loja.
  Future<void> importProfileBackup(String raw,
      {required bool isMerchant}) async {
    final p = isMerchant ? activeMerchant : activeConsumer;
    if (p == null) {
      throw StateError('Nenhum perfil ativo para receber o backup.');
    }

    final texto = raw.trim();
    if (texto.isEmpty) throw const FormatException('Conteúdo vazio.');

    dynamic decodificado;
    try {
      decodificado = jsonDecode(texto);
    } catch (_) {
      throw const FormatException(
          'Isso não é um backup de perfil do Iris. Verifique se o texto foi copiado por inteiro.');
    }
    if (decodificado is! Map<String, dynamic>) {
      throw const FormatException('Formato de backup não reconhecido.');
    }
    final versao = decodificado['iris_profile_backup'];
    if (versao is! int) {
      throw const FormatException('Isso não é um backup de perfil do Iris.');
    }
    if (versao > profileBackupFormatVersion) {
      throw FormatException(
          'Backup criado numa versão mais nova do app (formato $versao). Atualize o Iris neste aparelho.');
    }

    final name = decodificado['name'];
    await updateActiveProfile(
      isMerchant: isMerchant,
      name: name is String ? name : null,
      avatarColor: (decodificado['avatarColor'] as String?) ?? '',
    );

    final avatarB64 = decodificado['avatarImage'] as String?;
    if (avatarB64 != null) {
      await AvatarImageStore.salvarBase64(p.id, avatarB64);
    } else {
      // Backup explicitamente sem foto: remove a que já existir aqui, para o
      // resultado bater com o que foi exportado.
      await AvatarImageStore.remover(p.id);
    }

    final freeAttempts = decodificado['pinFreeAttempts'];
    final autoWipeEnabled = decodificado['autoWipeEnabled'];
    final autoWipeThreshold = decodificado['autoWipeThreshold'];
    if (freeAttempts is int ||
        autoWipeEnabled is bool ||
        autoWipeThreshold is int) {
      await setPinSecurityPolicy(
        freeAttempts: freeAttempts is int ? freeAttempts : null,
        autoWipeEnabled: autoWipeEnabled is bool ? autoWipeEnabled : null,
        autoWipeThreshold: autoWipeThreshold is int ? autoWipeThreshold : null,
      );
    }

    final autoLockMinutes = decodificado['autoLockMinutes'];
    final lockOnSuspend = decodificado['lockOnSuspend'];
    if (autoLockMinutes is int || lockOnSuspend is bool) {
      await setAutoLockPolicy(
        minutes: autoLockMinutes is int ? autoLockMinutes : null,
        lockOnSuspend: lockOnSuspend is bool ? lockOnSuspend : null,
      );
    }

    notifyListeners();
  }

  /// Leva os dados de cada conta para a pasta derivada da SUA semente.
  ///
  /// Cobre as duas formas antigas: `ldk_c_<id>`/`ldk_m_<id>` (uma pasta por
  /// conta) e `ldk_device` (a tentativa de pasta única). Sem isso, os canais
  /// e o histórico on-chain de cada carteira ficariam órfãos.
  Future<void> _migrarPastasDoNo() async {
    try {
      final docs = await getApplicationDocumentsDirectory();

      Future<void> mover(String origemNome, String seed) async {
        final destino = Directory('${docs.path}/${_nodeDirFor(seed)}');
        if (await destino.exists()) return; // já existe: nada a fazer
        final origem = Directory('${docs.path}/$origemNome');
        if (!await origem.exists()) return;
        await origem.rename(destino.path);
        debugPrint('Nó migrado de $origemNome para ${_nodeDirFor(seed)}.');
      }

      // Contas com seed cifrada (bloqueadas) têm seed vazia até o unlock; suas
      // pastas já existem (instalação antiga) ou serão criadas no unlock. Só há
      // o que migrar para contas legadas com seed ainda em texto puro.
      for (final c in _consumerAccounts) {
        if (c.seed.isEmpty) continue;
        await mover('ldk_c_${c.id}', c.seed);
      }
      for (final m in _merchantAccounts) {
        if (m.seed.isEmpty) continue;
        await mover('ldk_m_${m.id}', m.seed);
      }

      // A pasta única da versão anterior pertence à conta que era a ativa.
      final donoDoDevice = activeConsumer?.seed ?? activeMerchant?.seed;
      if (donoDoDevice != null && donoDoDevice.isNotEmpty) {
        await mover('ldk_device', donoDoDevice);
      }
    } catch (e) {
      debugPrint('Falha ao migrar as pastas do nó: $e');
    }
  }

  /// Define a semente do aparelho na primeira carteira criada/importada.
  /// Persistida CIFRADA (nunca em texto puro).
  Future<void> _definirSeedDoDispositivo(String seed, String pin) async {
    _deviceSeed = seed;
    await _storage.write(
        key: 'device_seed_enc',
        value: await SeedCrypto.encryptInBackground(seed, pin));
    await _storage.delete(
        key: 'device_seed'); // remove qualquer plaintext legado
  }

  /// Restaura a semente do aparelho em memória a partir do PIN, migrando o
  /// formato legado (texto puro) para cifrado no primeiro acesso.
  Future<void> _restoreDeviceSeed(String pin) async {
    final legacy = await _storage.read(key: 'device_seed');
    if (legacy != null && legacy.isNotEmpty) {
      _deviceSeed = legacy;
      await _storage.write(
          key: 'device_seed_enc',
          value: await SeedCrypto.encryptInBackground(legacy, pin));
      await _storage.delete(key: 'device_seed');
      return;
    }
    final enc = await _storage.read(key: 'device_seed_enc');
    if (enc != null) {
      try {
        _deviceSeed = await SeedCrypto.decryptInBackground(enc, pin);
      } on SeedDecryptException {
        // PIN não corresponde ao device seed (perfis com PINs distintos):
        // deixa em memória o que já houver; não é fatal.
      }
    }
  }

  /// Prepara a seed em memória do perfil a partir do PIN. Retorna false se o
  /// PIN não decifrar (= PIN incorreto). Migra perfis legados (texto puro) para
  /// o formato cifrado no primeiro acesso bem-sucedido.
  Future<bool> _unlockSeed(AccountProfile p, String pin) async {
    if (SeedCrypto.isEncrypted(p.encSeed)) {
      try {
        p.seed = await SeedCrypto.decryptInBackground(p.encSeed!, pin);
        return true;
      } on SeedDecryptException {
        return false; // PIN incorreto
      }
    }
    // Perfil legado: seed em texto puro protegida só pelo pinHash.
    if (!verifyPin(pin, p.pinHash)) return false;
    // p.seed já está em memória (do JSON legado); cifra para persistir.
    p.encSeed = await SeedCrypto.encryptInBackground(p.seed, pin);
    return true;
  }

  Future<bool> checkHasWallet() async {
    await initWallet();
    return _consumerAccounts.isNotEmpty || _merchantAccounts.isNotEmpty;
  }

  /// Gera uma semente nova. [words] aceita 12 (128 bits de entropia) ou
  /// 24 (256 bits) — os dois tamanhos padrão do BIP39.
  void resetAndGenerateSeed({int words = 12}) {
    _tempConsumerSeed = generateSeedPhrase(words: words);
    _tempSeedEhRestauracao = false;
    notifyListeners();
  }

  /// Tamanhos de semente aceitos pelo app.
  static const List<int> seedWordCounts = [12, 24];

  /// 12 palavras = 128 bits; 24 palavras = 256 bits.
  static String generateSeedPhrase({int words = 12}) {
    final strength = words == 24 ? 256 : 128;
    return bip39.generateMnemonic(strength: strength);
  }

  /// Valida o tamanho e o checksum. Devolve null se estiver tudo certo, ou a
  /// mensagem de erro pronta para a tela.
  static String? validateSeedPhrase(String seed) {
    final limpa = seed.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (limpa.isEmpty) return 'Digite as palavras da sua semente.';
    final palavras = limpa.split(' ');
    if (!seedWordCounts.contains(palavras.length)) {
      return 'A semente deve ter 12 ou 24 palavras (você digitou ${palavras.length}).';
    }
    if (!bip39.validateMnemonic(limpa)) {
      return 'Semente inválida. Confira a ortografia das palavras.';
    }
    return null;
  }

  void importSeed(String seed) {
    _tempConsumerSeed = seed;
    _tempSeedEhRestauracao = true;
    notifyListeners();
  }

  void cancelWalletCreation() {
    _tempConsumerSeed = null;
    _tempSeedEhRestauracao = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Desbloqueio / criação de contas
  // ---------------------------------------------------------------------

  /// Verificação pura do PIN (confirmação de pagamento etc.) — sem nenhum
  /// efeito colateral de sessão: não navega, não notifica, não mexe no nó.
  bool verifyConsumerPin(String pin) {
    final active = activeConsumer;
    if (active == null || isPinLocked) return false;
    final ok = verifyPin(pin, active.pinHash);
    ok ? _resetPinAttempts() : _registerPinFailure();
    return ok;
  }

  bool verifyMerchantPin(String pin) {
    final active = activeMerchant;
    if (active == null || isPinLocked) return false;
    final ok = verifyPin(pin, active.pinHash);
    ok ? _resetPinAttempts() : _registerPinFailure();
    return ok;
  }

  Future<bool> unlock(String pin) async {
    // Fluxo de criação de nova conta
    if (_tempConsumerSeed != null) {
      // Mesma regra da loja: sem parar o nó anterior, a carteira nova herdaria
      // o nó (e o saldo) da carteira antiga.
      await _consumerNode.stop();

      final newAccount = AccountProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Carteira Pessoal ${_consumerAccounts.length + 1}',
        seed: _tempConsumerSeed!,
        pinHash: hashPin(pin),
      );
      // Cifra a seed ANTES de qualquer persistência: nunca vai a disco em claro.
      newAccount.encSeed =
          await SeedCrypto.encryptInBackground(newAccount.seed, pin);
      _consumerAccounts.add(newAccount);
      _activeConsumerId = newAccount.id;
      _tempConsumerSeed = null;
      final eraRestauracao = _tempSeedEhRestauracao;
      _tempSeedEhRestauracao = false;

      // Uma seed por dispositivo: a primeira carteira criada define a do
      // aparelho; as demais contas são perfis sobre ela.
      if (_deviceSeed == null) {
        await _definirSeedDoDispositivo(newAccount.seed, pin);
      }

      await _saveConsumers();
      _isUnlocked = true;
      // Conta nova começa sem extrato; uma restauração pode já ter histórico
      // gravado de uma sessão anterior neste aparelho.
      _consumerTransactions.clear();
      await _carregarHistorico(false);
      await setLastSessionType('consumer');
      notifyListeners();

      _startNode(_consumerNode, newAccount.seed, _nodeDirFor(newAccount.seed),
              isMerchant: false)
          .then((_) async {
        // Carteira restaurada em outro aparelho começa com o banco do BDK
        // vazio: ele só consulta na rede os endereços que já tem em cache
        // (blocos de 100). Fundos recebidos num índice mais alto ficariam
        // invisíveis para sempre. A varredura revela endereços suficientes
        // para o saldo antigo reaparecer sozinho, sem o usuário ter de achar
        // um botão escondido.
        if (eraRestauracao) {
          _restaurandoCarteira = true;
          notifyListeners();
          try {
            await deepScan();
          } catch (e) {
            debugPrint('Varredura pós-restauração falhou: $e');
          } finally {
            _restaurandoCarteira = false;
            notifyListeners();
          }
        }
      }).catchError((Object e) {
        debugPrint('Erro ao iniciar LDK após criação: $e');
      });
      return true;
    }

    // Verificação de conta existente: o PIN precisa DECIFRAR a seed.
    final active = activeConsumer;
    if (active == null) return false;
    if (isPinLocked) return false; // bloqueado por excesso de tentativas
    if (await _unlockSeed(active, pin)) {
      _resetPinAttempts();
      // Migra hash legado de PIN para PBKDF2 no primeiro desbloqueio.
      if (_isLegacyHash(active.pinHash)) {
        active.pinHash = hashPin(pin);
      }
      await _saveConsumers(); // persiste encSeed (e pinHash migrado)
      await _restoreDeviceSeed(pin);
      _isUnlocked = true;
      // A seed já está em memória: agora dá para derivar a chave e recuperar o
      // extrato cifrado desta conta, e o último saldo verificado dela.
      await _carregarHistorico(false);
      await _preCarregarSaldoConhecido(active.seed);
      await setLastSessionType('consumer');
      notifyListeners();
      _startNode(_consumerNode, active.seed, _nodeDirFor(active.seed),
              isMerchant: false)
          .catchError((e) => debugPrint('Erro ao iniciar LDK: $e'));
      return true;
    }
    _registerPinFailure();
    return false;
  }

  /// Cria o perfil de loja. Se o aparelho já tem carteira, [seed] é ignorada:
  /// a loja é um PERFIL sobre a carteira do dispositivo, com o mesmo saldo.
  /// A loja usa a semente que o lojista escolheu: nova ou importada. Se ele
  /// importar a semente de outra carteira do aparelho, as duas passam a
  /// compartilhar dados e saldo, porque a pasta do nó vem da semente.
  Future<void> setupMerchant(String name, String seed, String pin) async {
    final seedDoPerfil = seed;

    final newAccount = AccountProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      seed: seedDoPerfil,
      pinHash: hashPin(pin),
    );
    // Cifra antes de persistir: a seed nunca vai a disco em texto puro.
    newAccount.encSeed =
        await SeedCrypto.encryptInBackground(seedDoPerfil, pin);

    // Primeira carteira do aparelho define a seed do device (cifrada).
    if (_deviceSeed == null) {
      await _definirSeedDoDispositivo(seedDoPerfil, pin);
    }

    _merchantAccounts.add(newAccount);
    _activeMerchantId = newAccount.id;
    ProductImageStore.definirLoja(newAccount.id);
    await _saveMerchants();

    _isMerchantUnlocked = true;
    // Loja nova nasce sem catálogo e sem histórico próprios.
    _clearMerchantSessionState();
    await setLastSessionType('merchant');
    notifyListeners();

    _startNode(_merchantNode, seedDoPerfil, _nodeDirFor(seedDoPerfil),
            isMerchant: true)
        .catchError((e) => debugPrint('Erro ao iniciar LDK da loja: $e'));
  }

  Future<bool> unlockMerchant(String pin) async {
    final active = activeMerchant;
    if (active == null) return false;

    if (isPinLocked) return false;
    if (await _unlockSeed(active, pin)) {
      _resetPinAttempts();
      if (_isLegacyHash(active.pinHash)) {
        active.pinHash = hashPin(pin);
      }
      await _saveMerchants();
      await _restoreDeviceSeed(pin);
      _isMerchantUnlocked = true;
      // Seed em memória: dá para decifrar o extrato desta loja e recuperar o
      // último saldo verificado dela.
      await _carregarHistorico(true);
      await _preCarregarSaldoConhecido(active.seed);
      await setLastSessionType('merchant');
      notifyListeners();
      _startNode(_merchantNode, active.seed, _nodeDirFor(active.seed),
              isMerchant: true)
          .catchError((e) => debugPrint('Erro ao iniciar LDK da loja: $e'));
      return true;
    }
    _registerPinFailure();
    return false;
  }

  // ---------------------------------------------------------------------
  // Nó LDK: inicialização, eventos e saldos (testnet)
  // ---------------------------------------------------------------------

  /// URL do daemon local por perfil (vazio = nó embarcado via FFI).
  String? _consumerDaemonUrl;
  String? _merchantDaemonUrl;
  String? get consumerDaemonUrl => _consumerDaemonUrl;
  String? get merchantDaemonUrl => _merchantDaemonUrl;
  bool get isConsumerNodeRemote => _consumerNode.isRemote;

  Future<void> setDaemonUrl(String? url, {required bool forMerchant}) async {
    final normalized = (url ?? '').trim().isEmpty ? null : url!.trim();
    if (forMerchant) {
      _merchantDaemonUrl = normalized;
      if (normalized == null) {
        await _storage.delete(key: 'daemon_url_merchant');
      } else {
        await _storage.write(key: 'daemon_url_merchant', value: normalized);
      }
    } else {
      _consumerDaemonUrl = normalized;
      if (normalized == null) {
        await _storage.delete(key: 'daemon_url_consumer');
      } else {
        await _storage.write(key: 'daemon_url_consumer', value: normalized);
      }
    }
    notifyListeners();
  }

  /// Start em andamento. Existe UM nó por aparelho, e tanto o desbloqueio da
  /// carteira quanto o da loja (e a recuperação por sync degradado) chamam
  /// [_startNode] sobre o mesmo handle. Sem serializar, dois ou três starts
  /// concorrentes disputavam a mesma pasta e a mesma porta, e cada um ainda
  /// disparava suas próprias requisições de `fee-estimates` — multiplicando a
  /// carga no exato endpoint que já estava estourando o timeout. Observado no
  /// aparelho: dezenas de "Starting up LDK Node" seguidos, nenhum concluindo.
  Future<void>? _startEmAndamento;

  /// Impressão digital da semente que o app QUER no ar agora. Um start em
  /// curso para outra semente virou trabalho obsoleto (o usuário trocou de
  /// conta) e deve desistir em vez de segurar a fila — era isso que deixava a
  /// tela do QR de recebimento "carregando" sem fim depois de trocar de conta.
  String? _fingerprintDesejada;

  Future<void> _startNode(_NodeHandle handle, String mnemonic, String dirName,
      {required bool isMerchant}) {
    _fingerprintDesejada = _seedFingerprint(mnemonic);
    // Encadeia: cada start só começa quando o anterior terminou. Assim o
    // segundo já enxerga o nó que o primeiro deixou no ar e, se a semente for
    // a mesma, sai pelo atalho sem reiniciar nada.
    final anterior = _startEmAndamento;
    final futuro = () async {
      if (anterior != null) {
        try {
          await anterior;
        } catch (_) {
          // Falha do start anterior não impede esta tentativa.
        }
      }
      await _startNodeInterno(handle, mnemonic, dirName,
          isMerchant: isMerchant);
    }();
    _startEmAndamento = futuro;
    // Limpa a referência só se ninguém encadeou depois, para não engolir a fila.
    futuro.whenComplete(() {
      if (identical(_startEmAndamento, futuro)) _startEmAndamento = null;
    });
    return futuro;
  }

  Future<void> _startNodeInterno(
      _NodeHandle handle, String mnemonic, String dirName,
      {required bool isMerchant}) async {
    final fingerprint = _seedFingerprint(mnemonic);

    // Um nó por vez. Se já roda a MESMA semente, é a mesma carteira e não há
    // nada a fazer — é assim que dois perfis com a mesma semente compartilham
    // saldo sem nunca subir um segundo nó. Se a semente é outra, o nó anterior
    // precisa parar antes: dois nós LDK simultâneos disputam porta e, sobre a
    // mesma chave, podem custar os fundos dos canais.
    if (handle.isRunning) {
      if (handle.runningSeedFingerprint == fingerprint) {
        handle.isMerchant = isMerchant;
        return;
      }
      await handle.stop();
    }

    try {
      _consumerDaemonUrl ??= await _storage.read(key: 'daemon_url_consumer');
      _merchantDaemonUrl ??= await _storage.read(key: 'daemon_url_merchant');
      final daemonUrl = isMerchant ? _merchantDaemonUrl : _consumerDaemonUrl;

      NodeApi api;
      if (daemonUrl != null && daemonUrl.isNotEmpty) {
        // Modo daemon: nó roda como serviço local (iris-noded) em 127.0.0.1
        api = RemoteNodeApi(daemonUrl);
        handle.isRemote = true;
      } else {
        // Modo embarcado: nó LDK via FFI dentro do app (todas as plataformas)
        final directory = await getApplicationDocumentsDirectory();
        final nodePath = '${directory.path}/$dirName';
        final dir = Directory(nodePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        api = EmbeddedNodeApi(
          mnemonic: mnemonic,
          storagePath: nodePath,
          // Portas distintas: os dois perfis rodam no mesmo processo.
          listeningPort: isMerchant ? 9736 : 9735,
        )..abortarSe = () => _fingerprintDesejada != fingerprint;
        handle.isRemote = false;
      }

      await api.start();
      handle.api = api;
      handle.isRunning = true;
      handle.isMock = false;
      handle.lastStartError = null;
      handle.isMerchant = isMerchant;
      handle.runningSeedFingerprint = fingerprint;
      handle.runningSeed = mnemonic;
      handle.consecutiveSyncFailures = 0;

      if (_keepNodeAliveInBackground) {
        // Melhor esforço: não bloqueia o boot do nó nem falha o app se der
        // errado (ex.: permissão de notificação negada).
        unawaited(BackgroundServiceAndroid.start());
      }

      if (isMerchant) await _loadMerchantProducts();

      // Fatura fixa de valor aberto (QR estático). Gerada UMA vez e persistida;
      // em toda abertura seguinte é apenas recarregada do armazenamento (nunca
      // regenerada no boot) — assim o QR já aparece pronto, sem "indisponível".
      handle.fixedInvoice = await _loadFixedInvoice(isMerchant);
      if (handle.fixedInvoice == null || handle.fixedInvoice!.isEmpty) {
        final desc = isMerchant ? 'Loja' : 'Carteira Principal';
        try {
          // Preferimos um OFFER BOLT12: é reutilizável, então o mesmo QR serve
          // para quantos pagamentos vierem. A BOLT11 é de uso único por
          // protocolo (payment_hash não repete) e precisa ser trocada a cada
          // recebimento — foi disso que o QR "fixo" reclamado nascia.
          final offer = await api.createOffer(description: desc);
          if (offer != null && offer.isNotEmpty) {
            handle.fixedInvoice = offer;
            await _saveFixedInvoice(isMerchant, offer);
            debugPrint('QR Lightning fixo: offer BOLT12 (reutilizável).');
          } else {
            final inv = await api.createInvoice(
              amountMsat: null,
              description: desc,
              expirySecs: 31536000, // 1 ano
            );
            handle.fixedInvoice = inv;
            await _saveFixedInvoice(isMerchant, inv);
            debugPrint('QR Lightning fixo: BOLT11 (uso único, sem BOLT12).');
          }
        } catch (e) {
          debugPrint('Falha ao gerar QR Lightning fixo: $e');
        }
      }

      await _refreshBalances(handle);
      // Recupera do registro do próprio nó o que o app não tinha gravado —
      // cobre quem vem de uma versão sem persistência e quem restaurou a
      // carteira em outro aparelho.
      unawaited(reconstruirHistoricoDoNo(forMerchant: isMerchant));
      // Garante que ESTE aparelho enxergue a mesma faixa de endereços que os
      // outros — sem isso, dois aparelhos da mesma carteira mostram saldos
      // diferentes (ver [_garantirJanelaDeEnderecos]).
      unawaited(_garantirJanelaDeEnderecos(handle));
      _runEventLoop(handle, isMerchant: isMerchant);
      _ensureSyncTimer();

      notifyListeners();
      debugPrint(
          'Nó (${isMerchant ? 'loja' : 'pessoal'}) iniciado na testnet4 — backend ${handle.isRemote ? 'daemon local' : 'embarcado'}.');
    } catch (e) {
      debugPrint(
          'Falha ao iniciar nó (${isMerchant ? 'loja' : 'pessoal'}): $e');
      // Fallback de UI: mantém o app utilizável se o motor nativo não carregar.
      // Ainda assim mostra o QR estático persistido (se já existir), para o
      // lojista não ver "indisponível" enquanto o nó religa.
      handle.isRunning = true;
      handle.isMock = true;
      handle.isMerchant = isMerchant;
      handle.runningSeedFingerprint = fingerprint;
      handle.runningSeed = mnemonic;
      handle.fixedInvoice = await _loadFixedInvoice(isMerchant);
      handle.lastStartError = e.toString();
      notifyListeners();
    }
  }

  /// Motivo real da indisponibilidade do nó (perfil pessoal ou loja), para
  /// exibir na UI em vez de uma mensagem genérica. Null quando o nó está ok.
  String? nodeStartError({bool forMerchant = false}) =>
      (forMerchant ? _merchantNode : _consumerNode).lastStartError;

  /// Loop de eventos do nó: credita recebimentos, confirma/derruba envios.
  /// Funciona igual para backend embarcado (FFI) e daemon local (RPC).
  void _runEventLoop(_NodeHandle handle, {required bool isMerchant}) {
    if (handle._eventLoopActive) return;
    handle._eventLoopActive = true;

    () async {
      while (handle._eventLoopActive && handle.api != null) {
        try {
          final event = await handle.api!.nextEvent();
          if (event == null) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          switch (event.type) {
            case 'payment_received':
              final sats = event.amountMsat ~/ 1000;
              final tx = Transaction(
                id: event.paymentHashHex,
                title: isMerchant ? 'Venda recebida' : 'Recebido via Lightning',
                emoji: '⚡',
                amountSats: sats,
                isIncoming: true,
                date: DateTime.now(),
              );
              _registrarTransacao(tx, isMerchant: isMerchant);
              _emitirRecebimento(ReceivedPayment(
                isMerchant: isMerchant,
                paymentHashHex: event.paymentHashHex,
                amountSats: sats,
              ));
              // Offer BOLT12 é REUTILIZÁVEL: não se toca nele, e é isso que
              // faz o QR ser de verdade fixo. Só a BOLT11 (uso único por
              // protocolo) precisa ser trocada depois de receber, senão o QR
              // exibido fica inválido.
              if (!ehOfferBolt12(handle.fixedInvoice)) {
                try {
                  final inv = await handle.api!.createInvoice(
                    amountMsat: null,
                    description: isMerchant ? 'Loja' : 'Carteira Principal',
                    expirySecs: 31536000,
                  );
                  handle.fixedInvoice = inv;
                  await _saveFixedInvoice(isMerchant, inv);
                } catch (e) {
                  debugPrint('Falha ao regenerar fatura fixa: $e');
                }
              }
              break;
            case 'payment_successful':
            case 'payment_failed':
              final novoStatus =
                  event.type == 'payment_successful' ? 'confirmed' : 'failed';
              final txs =
                  isMerchant ? _merchantTransactions : _consumerTransactions;
              var mudou = false;
              for (final tx in txs) {
                if (tx.id == event.paymentHashHex && tx.status == 'pending') {
                  tx.status = novoStatus;
                  mudou = true;
                }
              }
              // O status faz parte do extrato: se não gravar, ao reabrir o app
              // um pagamento que falhou voltaria a aparecer como pendente.
              if (mudou) unawaited(_salvarHistorico(isMerchant));
              break;
          }

          await handle.api!.eventHandled();
          await _refreshBalances(handle);
          notifyListeners();
        } catch (e) {
          debugPrint('Event loop do nó: $e');
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }();
  }

  /// O endereço on-chain é FIXO por escolha do usuário: o mesmo QR deve servir
  /// para quantas transações forem necessárias.
  ///
  /// Antes trocávamos após cada depósito, o que é a recomendação clássica de
  /// privacidade (evita ligar pagamentos ao mesmo endereço na cadeia). Mas
  /// para um lojista que imprime o QR e cola no balcão, trocar sozinho torna o
  /// QR impresso inútil — e o custo é só de privacidade, não de segurança: um
  /// endereço reusado recebe normalmente, quantas vezes for.
  ///
  /// Quem quiser um endereço novo tem [rotateOnchainAddress].
  Future<void> _rotateCachedAddressAposDeposito(_NodeHandle handle) async {
    // Intencionalmente não faz nada. Mantido como ponto único caso a política
    // volte a ser configurável.
  }

  Future<void> _refreshBalances(_NodeHandle handle) async {
    if (handle.api == null) return;
    try {
      final balances = await handle.api!.balances();
      var newTotal = balances.onchainTotalSats;
      var newSpendable = balances.onchainSpendableSats;
      var newLightning = balances.lightningSats;

      // Zero durante a sincronização inicial NÃO significa carteira vazia.
      //
      // O ldk_node lê o saldo com `try_lock` na carteira; enquanto um sync
      // segura esse lock (dezenas de segundos no boot), ele devolve um cache
      // que pode estar zerado. Era isso que fazia o saldo "sumir" ao reabrir
      // o app e voltar depois de sincronizar na mão.
      //
      // Regra: um zero só é aceito depois que um sync confirmou. Até lá,
      // preferimos o último saldo conhecido — ele já foi verificado na rede.
      final tudoZerado = newTotal == 0 && newLightning == 0;
      if (tudoZerado && !handle.saldoConfirmadoPorSync) {
        final ultimo = await _loadLastKnownBalance(handle);
        if (ultimo != null && (ultimo.total > 0 || ultimo.lightning > 0)) {
          newTotal = ultimo.total;
          newSpendable = ultimo.spendable;
          newLightning = ultimo.lightning;
          debugPrint(
              'Saldo lido como zero antes do primeiro sync — mantendo último '
              'valor conhecido ($newTotal sats on-chain).');
        }
      }

      handle.lightningBalanceSats = newLightning;
      final prevTotal = handle.onchainBalanceSats;
      final prevSpendable = handle.onchainSpendableSats;

      // Primeira leitura depois de abrir o app: se já existe valor no mempool,
      // ele precisa aparecer — a comparação entre syncs perdeu essa chegada
      // enquanto o app estava fechado. Só vale sem canais abertos, porque aí a
      // reserva âncora é zero e `total - gastável` é de fato o pendente.
      if (!handle.balancesInitialized && newTotal > newSpendable) {
        final pendente = newTotal - newSpendable;
        final jaRegistrado = pendingTransactions(isMerchant: handle.isMerchant)
                .fold<int>(0, (s, t) => s + t.amountSats) >=
            pendente;
        final semCanais = (await handle.api!.channels()).isEmpty;
        // `jaRegistrado`: com o histórico agora vindo do disco, este mesmo
        // pendente já pode estar na lista de uma sessão anterior — sem esta
        // checagem o extrato ganharia uma linha duplicada a cada abertura.
        if (semCanais && !jaRegistrado) {
          _registrarTransacao(
            Transaction(
              id: 'onchain_pend_${DateTime.now().millisecondsSinceEpoch}',
              title: 'Recebendo on-chain — aguardando confirmação',
              emoji: '₿',
              amountSats: pendente,
              isIncoming: true,
              date: DateTime.now(),
              status: 'pending',
            ),
            isMerchant: handle.isMerchant,
          );
          _emitirRecebimento(ReceivedPayment(
            isMerchant: handle.isMerchant,
            paymentHashHex: '',
            amountSats: pendente,
            isOnchain: true,
            isPending: true,
          ));
          await _rotateCachedAddressAposDeposito(handle);
        }
      }

      // O LDK não emite evento para depósito on-chain, então comparamos os
      // saldos entre syncs. Duas transições distintas interessam:
      //  - total sobe          -> dinheiro novo chegou (pode estar no mempool)
      //  - só o gastável sobe  -> algo que estava pendente CONFIRMOU
      if (handle.balancesInitialized) {
        final txs =
            handle.isMerchant ? _merchantTransactions : _consumerTransactions;

        if (newTotal > prevTotal) {
          final delta = newTotal - prevTotal;
          // Se a parte pendente cresceu junto, a entrada ainda não confirmou.
          final aindaPendente =
              (newTotal - newSpendable) > (prevTotal - prevSpendable);
          _registrarTransacao(
            Transaction(
              id: 'onchain_${DateTime.now().millisecondsSinceEpoch}',
              title: aindaPendente
                  ? 'Recebendo on-chain — aguardando confirmação'
                  : 'Recebido on-chain (Bitcoin)',
              emoji: '₿',
              amountSats: delta,
              isIncoming: true,
              date: DateTime.now(),
              status: aindaPendente ? 'pending' : 'confirmed',
            ),
            isMerchant: handle.isMerchant,
          );
          _emitirRecebimento(ReceivedPayment(
            isMerchant: handle.isMerchant,
            paymentHashHex: '',
            amountSats: delta,
            isOnchain: true,
            isPending: aindaPendente,
          ));
          await _rotateCachedAddressAposDeposito(handle);
        } else if (newSpendable > prevSpendable) {
          // Confirmou o que estava pendente: promove as entradas e avisa.
          final confirmado = newSpendable - prevSpendable;
          var promoveu = false;
          for (final t in txs) {
            if (t.isIncoming && t.status == 'pending') {
              t.status = 'confirmed';
              t.title = 'Recebido on-chain (Bitcoin)';
              promoveu = true;
            }
          }
          if (promoveu) {
            unawaited(_salvarHistorico(handle.isMerchant));
            _emitirRecebimento(ReceivedPayment(
              isMerchant: handle.isMerchant,
              paymentHashHex: '',
              amountSats: confirmado,
              isOnchain: true,
              isConfirmation: true,
            ));
          }
        }
      }
      handle.onchainBalanceSats = newTotal;
      handle.onchainSpendableSats = newSpendable;
      handle.balancesInitialized = true;
      await _saveLastKnownBalance(handle);
    } catch (e) {
      debugPrint('refreshBalances: $e');
    }
  }

  // Último saldo verificado na rede, guardado por semente (não por conta: o nó
  // é do dispositivo). Serve de ponte durante o boot, quando o ldk_node ainda
  // não consegue ler o valor real — ver [_refreshBalances] — e enquanto o nó
  // reinicia, quando a impressão digital some e os getters zerariam.
  String _lastBalanceKey(_NodeHandle handle) =>
      'last_balance_tn4_${handle.runningSeedFingerprint ?? 'desconhecido'}';

  /// Espelho em memória do que está no disco, indexado pela impressão digital
  /// da semente. Os getters de saldo são síncronos, então precisam de uma
  /// consulta sem `await`.
  final Map<String, ({int total, int spendable, int lightning})>
      _saldosConhecidos = {};

  Future<void> _saveLastKnownBalance(_NodeHandle handle) async {
    final fp = handle.runningSeedFingerprint;
    if (fp == null) return;

    // Nunca deixamos um zero apagar um valor não-zero já gravado.
    //
    // Um sync pode "confirmar" zero sem a carteira estar vazia — é o que
    // acontece quando os fundos estão num índice de endereço fora da janela
    // que o BDK consulta (ver a varredura profunda em [deepScan]). Se
    // gravássemos esse zero, perderíamos a única referência boa que temos, e a
    // reserva passaria a exibir zero para sempre. O saldo ao vivo continua
    // mostrando o que o nó lê; isto protege só a cópia de segurança.
    final zerado =
        handle.onchainBalanceSats == 0 && handle.lightningBalanceSats == 0;
    final anterior = _saldosConhecidos[fp];
    if (zerado && anterior != null && (anterior.total > 0 || anterior.lightning > 0)) {
      debugPrint(
          'Leitura zerada ignorada para o histórico de saldo: mantendo '
          '${anterior.total} sats gravados.');
      return;
    }

    _saldosConhecidos[fp] = (
      total: handle.onchainBalanceSats,
      spendable: handle.onchainSpendableSats,
      lightning: handle.lightningBalanceSats,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastBalanceKey(handle),
        '${handle.onchainBalanceSats}:${handle.onchainSpendableSats}:${handle.lightningBalanceSats}',
      );
    } catch (e) {
      debugPrint('Falha ao guardar último saldo: $e');
    }
  }

  /// Traz para a memória o saldo gravado da semente [seed], para os getters
  /// terem o que mostrar antes de o nó ficar pronto.
  Future<void> _preCarregarSaldoConhecido(String? seed) async {
    if (seed == null || seed.isEmpty) return;
    final fp = _seedFingerprint(seed);
    if (_saldosConhecidos.containsKey(fp)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('last_balance_tn4_$fp');
      if (raw == null) return;
      final p = raw.split(':');
      if (p.length != 3) return;
      _saldosConhecidos[fp] = (
        total: int.parse(p[0]),
        spendable: int.parse(p[1]),
        lightning: int.parse(p[2]),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Falha ao pré-carregar saldo: $e');
    }
  }

  /// Último saldo verificado da conta, para usar quando o nó ainda não está
  /// no ar com a semente dela (boot, troca de conta, reinício por sync
  /// degradado). Devolve zeros se nunca houve leitura — nunca inventa valor.
  ({int total, int spendable, int lightning}) _saldoDeReserva(String? seed) {
    if (seed == null || seed.isEmpty) {
      return (total: 0, spendable: 0, lightning: 0);
    }
    return _saldosConhecidos[_seedFingerprint(seed)] ??
        (total: 0, spendable: 0, lightning: 0);
  }

  Future<({int total, int spendable, int lightning})?> _loadLastKnownBalance(
      _NodeHandle handle) async {
    if (handle.runningSeedFingerprint == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastBalanceKey(handle));
      if (raw == null) return null;
      final p = raw.split(':');
      if (p.length != 3) return null;
      return (
        total: int.parse(p[0]),
        spendable: int.parse(p[1]),
        lightning: int.parse(p[2]),
      );
    } catch (e) {
      debugPrint('Falha ao ler último saldo: $e');
      return null;
    }
  }

  /// Falhas seguidas de sync que disparam a recuperação automática (reiniciar
  /// o nó, o que reescolhe o backend Esplora saudável). Ver [_NodeHandle.consecutiveSyncFailures].
  ///
  /// 5, e não 3: reiniciar o nó custa ~20s de boot e joga fora o progresso do
  /// sync. Numa rede móvel lenta, 3 falhas seguidas acontecem sem o nó estar
  /// realmente quebrado, e o reinício só piorava — a recuperação virava a
  /// causa do problema que ela deveria resolver.
  static const int _syncFailureThreshold = 5;

  /// True quando o nó do dispositivo está com a sincronização degradada (o
  /// backend Esplora escolhido no boot parou de responder bem — ex.: passou a
  /// limitar por taxa). A UI pode usar isto para avisar o usuário em vez de o
  /// app parecer travado silenciosamente.
  bool get nodeSyncDegraded =>
      _deviceNode.consecutiveSyncFailures >= _syncFailureThreshold;

  void _ensureSyncTimer() {
    // Perfil pessoal e loja são o MESMO nó (um nó por dispositivo) — sincronizar
    // a lista [_consumerNode, _merchantNode] batia duas vezes no mesmo backend
    // Esplora a cada tick, o que ajuda a causar o próprio rate-limit que
    // depois faz o sync falhar. Um handle, uma chamada.
    Future<void> tick() async {
      final handle = _deviceNode;
      if (handle.api == null) return;
      try {
        await handle.api!.sync();
        // A partir daqui um saldo zero é confiável: veio de leitura pós-sync,
        // não do cache que o ldk_node devolve enquanto o lock está ocupado.
        handle.saldoConfirmadoPorSync = true;
        await _refreshBalances(handle);
        handle.consecutiveSyncFailures = 0;
      } catch (e) {
        handle.consecutiveSyncFailures++;
        debugPrint(
            'Sync falhou (${handle.consecutiveSyncFailures}/$_syncFailureThreshold): $e');
        if (handle.consecutiveSyncFailures >= _syncFailureThreshold) {
          await _recoverDegradedNode(handle);
        }
      }
      notifyListeners();
    }

    _dispararSync = tick;

    // Primeiro sync imediato: sem ele o saldo real só apareceria no primeiro
    // tick, um minuto depois de abrir o app — que era exatamente a espera que
    // obrigava o usuário a sincronizar na mão pelo gerenciador de nós.
    unawaited(tick());
    // O sync completo é caro (o BDK consulta um endpoint por endereço em
    // cache — numa carteira restaurada são ~200 requisições) e é ele que
    // provoca os 429 do Esplora. Fica espaçado e serve de rede de segurança;
    // quem dá a resposta rápida é a vigia de 5s abaixo. 120s também evita que
    // um tick novo caia em cima de um sync anterior que ainda está rodando.
    // 45s com o app em uso, para o saldo acompanhar o que foi feito em outro
    // aparelho sem o usuário precisar pedir; 180s quando ele está em segundo
    // plano, onde ninguém está olhando e o que importa é economizar rede e
    // bateria. A troca acontece em [didChangeAppLifecycleState].
    _reagendarSyncTimer();
    _ensureFastWatch();
  }

  // --- Vigia rápida de recebimentos ---------------------------------------
  //
  // Detectar um pagamento pelo sync completo custava até ~70s (até 60s de
  // espera + ~10s de sync). Aqui fazemos UMA requisição barata ao Esplora
  // perguntando só pelo endereço que está na tela; se o total recebido mudou,
  // disparamos o sync completo na hora. Resultado: o dinheiro aparece em
  // poucos segundos, sem multiplicar a carga que causa rate-limit.

  /// Intervalo do sync completo conforme o app esteja em uso ou não.
  bool _appEmPrimeiroPlano = true;

  void _reagendarSyncTimer() {
    _syncTimer?.cancel();
    final intervalo =
        _appEmPrimeiroPlano ? const Duration(seconds: 45) : const Duration(seconds: 180);
    _syncTimer = Timer.periodic(intervalo, (_) => _dispararSync?.call());
  }

  Timer? _fastWatchTimer;
  Future<void> Function()? _dispararSync;
  int? _ultimoTotalVisto;
  String? _enderecoVigiado;

  /// Ticks a pular depois de um 429. A testnet4 tem provedor Esplora único; se
  /// a vigia insistir enquanto está sendo limitada, ela ajuda a derrubar o sync
  /// completo, que é o que realmente mantém o saldo correto.
  int _vigiaEmEspera = 0;

  void _ensureFastWatch() {
    _fastWatchTimer ??=
        Timer.periodic(const Duration(seconds: 5), (_) => _vigiarEndereco());
  }

  Future<void> _vigiarEndereco() async {
    if (_vigiaEmEspera > 0) {
      _vigiaEmEspera--;
      return;
    }
    final handle = _deviceNode;
    if (handle.api == null || !handle.isRunning || handle.isMock) return;

    final base = EmbeddedNodeApi.esploraEmUso;
    if (base == null) return;

    try {
      // Usa o endereço já em cache; não deriva um novo (ver
      // [getOnchainAddress]), senão a vigia queimaria índices sem parar.
      final addr = handle.cachedOnchainAddress ??
          await _loadOnchainAddress(handle.isMerchant);
      if (addr == null || addr.isEmpty) return;

      final r = await http
          .get(Uri.parse('$base/address/$addr'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 429) {
        // Um minuto de silêncio (12 ticks de 5s) para o Esplora respirar.
        _vigiaEmEspera = 12;
        debugPrint('Vigia rápida: 429 do Esplora — pausando por ~1 min.');
        return;
      }
      if (r.statusCode != 200) return;

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final chain = (j['chain_stats'] as Map<String, dynamic>?) ?? const {};
      final mem = (j['mempool_stats'] as Map<String, dynamic>?) ?? const {};
      final total = ((chain['funded_txo_sum'] as num?)?.toInt() ?? 0) +
          ((mem['funded_txo_sum'] as num?)?.toInt() ?? 0);

      // Trocou de endereço (depósito anterior já rotacionou): rebaseia sem
      // disparar sync, senão a troca seria lida como "chegou dinheiro".
      if (_enderecoVigiado != addr) {
        _enderecoVigiado = addr;
        _ultimoTotalVisto = total;
        return;
      }

      if (_ultimoTotalVisto != null && total > _ultimoTotalVisto!) {
        debugPrint(
            'Vigia rápida: recebimento detectado em $addr — sincronizando já.');
        _ultimoTotalVisto = total;
        await _dispararSync?.call();
      } else {
        _ultimoTotalVisto = total;
      }
    } catch (e) {
      // Qualquer falha (timeout, DNS, conexão) significa provedor ou rede sob
      // pressão. Insistir a cada 5s só somaria carga ao mesmo servidor de que
      // o sync completo depende — recuar é o que ajuda os dois.
      _vigiaEmEspera = 6; // ~30s de silêncio
      debugPrint('Vigia rápida pausada após falha: $e');
    }
  }

  /// Reinicia o nó do dispositivo depois de várias falhas de sync seguidas.
  /// Reiniciar refaz a escolha do backend Esplora (`escolherEsplora`), que é o
  /// único jeito de trocar de servidor sem reconstruir o nó nativo do zero à
  /// mão — o LDK/BDK não expõe troca do Esplora em um nó já em execução.
  Future<void> _recoverDegradedNode(_NodeHandle handle) async {
    final seed = handle.runningSeed;
    if (seed == null) return; // nada a reiniciar (ex.: modo mock sem seed)
    debugPrint(
        'Sync degradado por $_syncFailureThreshold tentativas seguidas — reiniciando o nó para trocar de backend Esplora.');
    final wasMerchant = handle.isMerchant;
    try {
      // _startNode pula o reinício se a fingerprint da seed não mudou (guarda
      // pensada para evitar reinícios redundantes) — aqui é exatamente o caso
      // (mesma seed, só queremos um Esplora novo), então precisa parar antes
      // para não cair naquele atalho.
      await handle.stop();
      await _startNode(handle, seed, _nodeDirFor(seed),
          isMerchant: wasMerchant);
    } catch (e) {
      debugPrint('Recuperação automática do nó falhou: $e');
    }
  }

  void lock() {
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    notifyListeners();
  }

  Future<void> wipeWallet() async {
    await _consumerNode.stop();
    await _merchantNode.stop();
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    for (final a in _merchantAccounts) {
      await prefs.remove('merchant_products_${a.id}');
      await prefs.remove('tx_hist_v2_${a.id}');
      await ProductImageStore.apagarLoja(a.id);
      await AvatarImageStore.apagarConta(a.id);
    }
    for (final a in _consumerAccounts) {
      await prefs.remove('tx_hist_v2_${a.id}');
      await AvatarImageStore.apagarConta(a.id);
    }
    // Chaves derivadas vivem só em memória, mas não devem sobreviver ao wipe.
    _chavesDeHistorico.clear();
    await prefs.remove('merchant_products');
    ProductImageStore.definirLoja(null);
    _merchantProducts = [];
    _consumerAccounts.clear();
    _merchantAccounts.clear();
    _activeConsumerId = null;
    _activeMerchantId = null;
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    _consumerTransactions.clear();
    _merchantTransactions.clear();
    notifyListeners();
  }

  Future<void> deleteActiveConsumer() async {
    await _consumerNode.stop();
    if (_activeConsumerId != null) {
      await AvatarImageStore.apagarConta(_activeConsumerId!);
      // O extrato morre com a conta: apagar a carteira e deixar o histórico
      // cifrado no disco seria guardar dado que o usuário mandou remover.
      await _apagarHistoricoDaConta(_activeConsumerId!);
    }
    _consumerAccounts.removeWhere((a) => a.id == _activeConsumerId);
    if (_consumerAccounts.isNotEmpty) {
      _activeConsumerId = _consumerAccounts.first.id;
    } else {
      _activeConsumerId = null;
      _isUnlocked = false;
      if (_merchantAccounts.isNotEmpty) {
        await setLastSessionType('merchant');
      }
    }
    await _saveConsumers();
    notifyListeners();
  }

  Future<void> deleteActiveMerchant() async {
    await _merchantNode.stop();
    final removedId = _activeMerchantId;
    if (removedId != null) {
      await _deleteMerchantProducts(removedId);
      // A loja deixou de existir: as fotos e o extrato dela vão junto.
      await ProductImageStore.apagarLoja(removedId);
      await AvatarImageStore.apagarConta(removedId);
      await _apagarHistoricoDaConta(removedId);
    }
    _clearMerchantSessionState();
    _merchantAccounts.removeWhere((a) => a.id == _activeMerchantId);
    if (_merchantAccounts.isNotEmpty) {
      _activeMerchantId = _merchantAccounts.first.id;
    } else {
      _activeMerchantId = null;
      _isMerchantUnlocked = false;
      if (_consumerAccounts.isNotEmpty) {
        await setLastSessionType('consumer');
      }
    }
    await _saveMerchants();
    // Assume o catálogo da loja que passou a ser a ativa.
    await _loadMerchantProducts();
    notifyListeners();
  }

  Future<void> switchConsumerAccount(String id) async {
    // NÃO paramos o nó aqui de propósito. Quase todos os perfis compartilham a
    // semente do aparelho, e parar+subir de novo custa ~20s (cache de taxas do
    // LDK) para acabar exatamente no mesmo nó. Quem decide é o [_startNode]:
    // ele já mantém o nó no ar se a semente for a mesma e só reinicia se for
    // outra. Enquanto isso, [_noEDoPerfil] impede exibir saldo alheio.
    _clearConsumerSessionState();
    _activeConsumerId = id;
    setConsumerTab(0); // troca de conta começa no Início
    await _saveConsumers();
    _isUnlocked = false; // Requer PIN para a nova conta
    notifyListeners();
  }

  Future<void> switchMerchantAccount(String id) async {
    // Mesma razão de [switchConsumerAccount]: o nó só reinicia se a semente
    // mudar, e essa decisão é do [_startNode].
    _clearMerchantSessionState();
    _activeMerchantId = id;
    // As fotos seguem a loja: sem isto, a limpeza de órfãs da loja nova
    // apagaria as fotos da anterior.
    ProductImageStore.definirLoja(id);
    setMerchantTab(0); // troca de loja começa no Início
    await _saveMerchants();
    // Carrega o catálogo da loja escolhida na hora (não depende do nó subir).
    await _loadMerchantProducts();
    _isMerchantUnlocked = false; // Requer PIN para a nova loja
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Produtos do lojista
  // ---------------------------------------------------------------------

  /// Apaga da memória tudo que pertence à loja que estava ativa. Contas são
  /// separadas: catálogo, histórico, carrinho e cobrança pendente não podem
  /// atravessar de uma para outra. Sem isso o catálogo antigo ainda seria
  /// gravado na chave da loja nova no primeiro cadastro de produto.
  void _clearMerchantSessionState() {
    _merchantProducts = [];
    _merchantTransactions.clear();
    _cartTotal = 0;
    _pendingChargeAmount = 0;
    onAccountChanged?.call();
  }

  /// Equivalente para a carteira pessoal.
  void _clearConsumerSessionState() {
    _consumerTransactions.clear();
    onAccountChanged?.call();
  }

  /// Cada loja tem seu próprio catálogo. Uma loja nova nasce sem produtos.
  String? get _productsKey =>
      _activeMerchantId == null ? null : 'merchant_products_$_activeMerchantId';

  Future<void> _loadMerchantProducts() async {
    final key = _productsKey;
    if (key == null) {
      _merchantProducts = [];
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    // Catálogo global legado (compartilhado entre lojas): descartado.
    await prefs.remove('merchant_products');
    final jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) {
      _merchantProducts = [];
      return;
    }
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      _merchantProducts = jsonList.map((j) => Product.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Failed to decode merchant products: $e');
      _merchantProducts = [];
    }
  }

  Future<void> _saveMerchantProducts() async {
    final key = _productsKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(_merchantProducts.map((p) => p.toJson()).toList());
    await prefs.setString(key, jsonStr);
  }

  Future<void> _deleteMerchantProducts(String merchantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('merchant_products_$merchantId');
  }

  // --- Endereços da própria carteira ---------------------------------------
  //
  // Guardamos todo endereço que o app já revelou para esta semente. Serve para
  // avisar quando o destino de um envio é a PRÓPRIA carteira — caso real: os
  // perfis compartilham a semente do aparelho, então "mandar da carteira A
  // para a B" é mandar para si mesmo, e o usuário só perde a taxa de mineração
  // sem mover nada. O conjunto é por semente, exatamente como o nó.

  /// endereço (minúsculo) -> nome do perfil que o revelou. Guardar o NOME, e
  /// não só a existência, é o que permite dizer na tela "este endereço é da
  /// sua Loja X" em vez de um genérico "é seu" — que é o feedback visual que
  /// deixa o usuário conferir para onde está mandando.
  final Map<String, String> _enderecosProprios = {};
  String? _fpDosEnderecosProprios;

  String _chaveEnderecosProprios(String fp) => 'meus_enderecos_tn4_$fp';

  Future<void> _carregarEnderecosProprios(String fingerprint) async {
    if (_fpDosEnderecosProprios == fingerprint) return;
    _enderecosProprios.clear();
    _fpDosEnderecosProprios = fingerprint;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString(_chaveEnderecosProprios(fingerprint));
      if (bruto != null && bruto.isNotEmpty) {
        final m = jsonDecode(bruto) as Map<String, dynamic>;
        m.forEach((k, v) => _enderecosProprios[k] = v as String);
      }
    } catch (e) {
      debugPrint('Falha ao carregar endereços próprios: $e');
    }
  }

  Future<void> _registrarEnderecoProprio(String endereco,
      {String? nomeDoPerfil}) async {
    final fp = _deviceNode.runningSeedFingerprint;
    if (fp == null || endereco.isEmpty) return;
    await _carregarEnderecosProprios(fp);
    final chave = endereco.trim().toLowerCase();
    final nome = nomeDoPerfil ??
        (_deviceNode.isMerchant
            ? (activeMerchant?.name ?? 'Loja')
            : (activeConsumer?.name ?? 'Carteira pessoal'));
    if (_enderecosProprios[chave] == nome) return; // nada mudou
    _enderecosProprios[chave] = nome;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _chaveEnderecosProprios(fp), jsonEncode(_enderecosProprios));
    } catch (e) {
      debugPrint('Falha ao gravar endereço próprio: $e');
    }
  }

  /// Nome do perfil dono de [endereco], ou null se o endereço não for desta
  /// carteira. Enviar para um endereço com nome = enviar para si mesmo.
  ///
  /// Reconhece o que o app revelou (tela de receber, gerenciador de nós,
  /// varredura profunda). Não enxerga endereços de troco, que o BDK deriva
  /// internamente — mas o destino que o usuário cola vem sempre da tela de
  /// receber, que é justamente o que cobrimos.
  String? nomeDaCarteiraDoEndereco(String endereco) {
    final fp = _deviceNode.runningSeedFingerprint;
    if (fp == null) return null;
    if (_fpDosEnderecosProprios != fp) {
      // Ainda não carregado para esta semente: dispara e responde na próxima.
      unawaited(_carregarEnderecosProprios(fp).then((_) => notifyListeners()));
      return null;
    }
    return _enderecosProprios[endereco.trim().toLowerCase()];
  }

  bool enderecoEhDaMinhaCarteira(String endereco) =>
      nomeDaCarteiraDoEndereco(endereco) != null;

  // Fatura fixa (QR estático) persistida por perfil: gerada uma vez na criação
  // da carteira e reutilizada sempre; só troca após um recebimento (uso único).
  // A chave carrega a rede: a fatura fixa guardada na testnet3 pertence a um
  // estado de nó que não existe mais, então não deve ser reaproveitada — com a
  // chave nova ela nasce vazia e é regerada no primeiro start em testnet4.
  Future<String?> _loadFixedInvoice(bool isMerchant) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fixed_invoice_tn4n_$id');
  }

  Future<void> _saveFixedInvoice(bool isMerchant, String invoice) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fixed_invoice_tn4n_$id', invoice);
  }

  // Endereço on-chain persistido por perfil: mesma lógica da fatura fixa
  // acima — gerado uma vez, reaproveitado sempre, só troca após um
  // recebimento. Chave carrega a rede pelo mesmo motivo (endereço de uma
  // testnet3 inerte não deve ressurgir na testnet4).
  Future<String?> _loadOnchainAddress(bool isMerchant) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('onchain_addr_tn4_$id');
  }

  Future<void> _saveOnchainAddress(bool isMerchant, String address) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onchain_addr_tn4_$id', address);
  }


  /// QR estático (fatura Lightning fixa). Retorna a persistida se existir; se o
  /// nó já está rodando mas a fatura ainda não foi criada (ex.: tela abriu antes
  /// de o boot terminar), gera sob demanda e persiste. Só falha se o nó estiver
  /// realmente offline. Evita o erro "indisponível" nas áreas pessoal e loja.
  /// Reinicia o nó do perfil. Usado pelo "Tentar novamente" e pela geração sob
  /// demanda quando o nó caiu em mock (ex.: timeout de fee no boot). Recompõe
  /// os mesmos parâmetros de storage usados na inicialização.
  Future<void> restartNode({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    await handle.stop();
    final seed = forMerchant ? activeMerchant?.seed : activeConsumer?.seed;
    if (seed == null) return;
    await _startNode(handle, seed, _nodeDirFor(seed), isMerchant: forMerchant);
  }

  Future<String> getFixedInvoice({bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;
    if (handle.fixedInvoice != null && handle.fixedInvoice!.isNotEmpty) {
      return handle.fixedInvoice!;
    }
    final persisted = await _loadFixedInvoice(forMerchant);
    if (persisted != null && persisted.isNotEmpty) {
      handle.fixedInvoice = persisted;
      return persisted;
    }
    // Nó em mock (ex.: timeout no boot): tenta reiniciar antes de desistir.
    if (handle.api == null) {
      await restartNode(forMerchant: forMerchant);
      handle = forMerchant ? _merchantNode : _consumerNode;
    }
    if (handle.isRunning && handle.api != null) {
      final inv = await handle.api!.createInvoice(
        amountMsat: null,
        description: forMerchant ? 'Loja' : 'Carteira Principal',
        expirySecs: 31536000,
      );
      handle.fixedInvoice = inv;
      await _saveFixedInvoice(forMerchant, inv);
      return inv;
    }
    throw Exception(
        'Fatura Lightning ainda indisponível — o nó pode estar iniciando ou offline. Tente novamente em instantes.');
  }

  void addMerchantProduct(Product p) {
    _merchantProducts.add(p);
    _saveMerchantProducts();
    notifyListeners();
  }

  void updateMerchantProduct(Product p) {
    final idx = _merchantProducts.indexWhere((e) => e.id == p.id);
    if (idx != -1) {
      _merchantProducts[idx] = p;
      _saveMerchantProducts();
      // Se a foto foi trocada ou removida, a antiga vira lixo.
      _limparFotosOrfas();
      notifyListeners();
    }
  }

  void removeMerchantProduct(String id) {
    _merchantProducts.removeWhere((e) => e.id == id);
    _saveMerchantProducts();
    // A foto do produto apagado não serve mais a ninguém.
    _limparFotosOrfas();
    notifyListeners();
  }

  /// Apaga arquivos de foto que nenhum produto referencia mais: produto
  /// excluído, foto trocada, ou cadastro abandonado depois de escolher imagem.
  Future<void> _limparFotosOrfas() async {
    final emUso =
        _merchantProducts.map((p) => p.image).whereType<String>().toSet();
    await ProductImageStore.limparOrfaos(emUso);
  }

  // ---------------------------------------------------------------------
  // Exportar / importar catálogo (replicar a loja em vários dispositivos)
  // ---------------------------------------------------------------------

  /// Versão do formato do arquivo. Só o catálogo trafega — nunca seed, PIN ou
  /// qualquer chave: um arquivo exportado não dá acesso à carteira.
  static const int catalogFormatVersion = 1;

  /// Serializa o catálogo da loja ativa. O JSON sai indentado para ser legível
  /// e conferível por quem recebe.
  Future<String> exportMerchantCatalog() async {
    if (_activeMerchantId == null) {
      throw StateError('Nenhuma loja ativa para exportar.');
    }

    // A foto vive em arquivo local; para atravessar para outro aparelho ela
    // precisa ir embutida no JSON.
    final produtos = <Map<String, dynamic>>[];
    for (final p in _merchantProducts) {
      final json = p.toJson();
      final bytes = await ProductImageStore.lerBytes(p.image);
      if (bytes != null) {
        json['image'] = base64Encode(bytes);
        json['image_ext'] = _extensaoDe(p.image);
      } else {
        json.remove('image');
      }
      produtos.add(json);
    }

    return const JsonEncoder.withIndent('  ').convert({
      'iris_catalog': catalogFormatVersion,
      'loja': merchantName ?? '',
      'exportado_em': DateTime.now().toIso8601String(),
      'produtos': produtos,
    });
  }

  static String _extensaoDe(String? nomeArquivo) {
    if (nomeArquivo == null || !nomeArquivo.contains('.')) return 'jpg';
    return nomeArquivo.split('.').last;
  }

  /// Lê o conteúdo exportado e valida item a item. Nada é gravado se o arquivo
  /// for inválido — ou entra tudo que é válido, ou a operação falha inteira.
  ///
  /// [substituir] troca o catálogo atual; caso contrário mescla, atualizando os
  /// produtos de mesmo id e acrescentando os novos.
  Future<CatalogImportResult> importMerchantCatalog(String raw,
      {bool substituir = false}) async {
    if (_activeMerchantId == null) {
      throw StateError('Nenhuma loja ativa para receber o catálogo.');
    }

    final texto = raw.trim();
    if (texto.isEmpty) {
      throw const FormatException('Conteúdo vazio.');
    }

    dynamic decodificado;
    try {
      decodificado = jsonDecode(texto);
    } catch (_) {
      throw const FormatException(
          'Isso não é um catálogo do Iris. Verifique se o texto foi copiado por inteiro.');
    }

    // Aceita o envelope completo ou uma lista de produtos pura, para o caso de
    // alguém colar só o trecho dos produtos.
    List<dynamic> crus;
    if (decodificado is List) {
      crus = decodificado;
    } else if (decodificado is Map<String, dynamic>) {
      final versao = decodificado['iris_catalog'];
      if (versao is int && versao > catalogFormatVersion) {
        throw FormatException(
            'Catálogo criado numa versão mais nova do app (formato $versao). Atualize o Iris neste aparelho.');
      }
      final lista = decodificado['produtos'];
      if (lista is! List) {
        throw const FormatException(
            'O arquivo não contém uma lista de produtos.');
      }
      crus = lista;
    } else {
      throw const FormatException('Formato de catálogo não reconhecido.');
    }

    final importados = <Product>[];
    var ignorados = 0;
    for (final item in crus) {
      final lido = _produtoDeJsonTolerante(item);
      if (lido == null) {
        ignorados++;
        continue;
      }
      // Grava a foto embutida como arquivo local deste aparelho.
      if (lido.fotoBase64 != null) {
        lido.produto.image = await ProductImageStore.salvarBase64(
          lido.fotoBase64!,
          extensao: lido.extensao,
        );
      }
      importados.add(lido.produto);
    }

    if (importados.isEmpty) {
      throw const FormatException(
          'Nenhum produto válido foi encontrado no arquivo.');
    }

    var adicionados = 0;
    var atualizados = 0;
    if (substituir) {
      _merchantProducts = importados;
      adicionados = importados.length;
    } else {
      for (final novo in importados) {
        final idx = _merchantProducts.indexWhere((e) => e.id == novo.id);
        if (idx == -1) {
          _merchantProducts.add(novo);
          adicionados++;
        } else {
          _merchantProducts[idx] = novo;
          atualizados++;
        }
      }
    }

    await _saveMerchantProducts();
    // Substituir descarta os produtos antigos: as fotos deles ficariam órfãs.
    await _limparFotosOrfas();

    // O catálogo veio de outro aparelho, mas o dinheiro é deste. Descarta
    // cobranças em cache para que todo QR seja regerado com a carteira local
    // (endereço Liquid, fatura Lightning e endereço on-chain daqui).
    onCatalogImported?.call();

    notifyListeners();
    return CatalogImportResult(
      adicionados: adicionados,
      atualizados: atualizados,
      ignorados: ignorados,
    );
  }

  /// Converte um item do arquivo, ou devolve null se for inválido.
  /// Deliberadamente tolerante com campos ausentes (descrição, foto, isActive)
  /// e rigoroso com os que definem o produto (nome e preço).
  static _ProdutoImportado? _produtoDeJsonTolerante(dynamic item) {
    if (item is! Map) return null;

    final nome = item['name'];
    if (nome is! String || nome.trim().isEmpty) return null;

    final precoCru = item['price'];
    final double preco;
    if (precoCru is num) {
      preco = precoCru.toDouble();
    } else if (precoCru is String) {
      final v = double.tryParse(precoCru.replaceAll(',', '.'));
      if (v == null) return null;
      preco = v;
    } else {
      return null;
    }
    // NaN/infinito quebrariam a formatação e os cálculos de cobrança.
    if (!preco.isFinite || preco < 0) return null;

    final id = item['id'];
    final descricao = item['description'];

    final produto = Product(
      id: (id is String && id.trim().isNotEmpty)
          ? id
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: nome.trim(),
      price: preco,
      isActive: item['isActive'] is bool ? item['isActive'] as bool : true,
      description: descricao is String ? descricao.trim() : '',
    );

    // A foto vem embutida em base64. Só é aceita se decodificar; foto inválida
    // não invalida o produto — ele entra sem foto, em vez de sumir.
    String? fotoBase64;
    final imagemCrua = item['image'];
    if (imagemCrua is String && imagemCrua.isNotEmpty) {
      try {
        base64Decode(imagemCrua);
        fotoBase64 = imagemCrua;
      } catch (_) {
        fotoBase64 = null;
      }
    }
    final ext = item['image_ext'];

    return _ProdutoImportado(
      produto: produto,
      fotoBase64: fotoBase64,
      extensao: (ext is String && ext.trim().isNotEmpty) ? ext.trim() : 'jpg',
    );
  }

  Future<void> toggleNfc(bool value) async {
    _isNfcEnabled = value;
    await _storage.write(key: 'nfc_enabled', value: value.toString());
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Gestão do nó (on-chain, canais) — perfil pessoal
  // ---------------------------------------------------------------------

  /// Endereço Bitcoin on-chain (testnet) do nó — recebimento puro pela
  /// rede Bitcoin, além da Lightning.
  Future<String> getOnchainAddress({bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;
    // Nó em mock (ex.: timeout no boot): tenta reiniciar antes de falhar.
    if (handle.api == null) {
      // Com prazo: o start pode estar na fila atrás de outro que ainda tenta
      // subir. Sem este limite a tela do QR ficava "carregando" para sempre,
      // sem erro e sem endereço — pior do que dizer que não deu.
      try {
        await restartNode(forMerchant: forMerchant)
            .timeout(const Duration(seconds: 50));
      } on TimeoutException {
        throw Exception(
            'O nó está demorando para conectar à rede. Toque para tentar de novo.');
      }
      handle = forMerchant ? _merchantNode : _consumerNode;
    }
    if (!handle.isRunning || handle.api == null) {
      // Nunca exibir endereço falso: sem nó, sem endereço.
      final reason = handle.lastStartError;
      throw Exception(reason != null
          ? 'Nó indisponível — não é possível gerar endereço real. Detalhe: $reason'
          : 'Nó indisponível — não é possível gerar endereço real.');
    }

    // Reaproveita o mesmo endereço até ele receber algo — sem isto, o
    // ldk_node deriva um índice novo (`AddressIndex::New`) a cada chamada, e
    // reabrir a tela de receber trocava o endereço mostrado sem motivo.
    if (handle.cachedOnchainAddress != null) {
      return handle.cachedOnchainAddress!;
    }
    final persisted = await _loadOnchainAddress(forMerchant);
    if (persisted != null && persisted.isNotEmpty) {
      handle.cachedOnchainAddress = persisted;
      await _registrarEnderecoProprio(persisted);
      return persisted;
    }

    final novo = await handle.api!.newOnchainAddress();
    handle.cachedOnchainAddress = novo;
    await _saveOnchainAddress(forMerchant, novo);
    await _registrarEnderecoProprio(novo);
    return novo;
  }

  /// Força um endereço novo mesmo sem ter recebido nada no atual — para quem
  /// quer trocar por privacidade sem esperar um depósito.
  Future<String> rotateOnchainAddress({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      throw Exception('Nó indisponível — não é possível gerar endereço real.');
    }
    final novo = await handle.api!.newOnchainAddress();
    handle.cachedOnchainAddress = novo;
    await _saveOnchainAddress(forMerchant, novo);
    await _registrarEnderecoProprio(novo);
    notifyListeners();
    return novo;
  }

  /// Identidade pública do nó deste dispositivo — o que outro dispositivo
  /// precisa saber (junto com um endereço alcançável) para se conectar a ele
  /// e abrir um canal. Sem isto, "meu nó" não existe do ponto de vista de
  /// fora: é a chave que faz um dispositivo achar o outro na rede.
  Future<String> getMyNodeId({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      throw Exception('Nó indisponível.');
    }
    return await handle.api!.myNodeId();
  }

  /// IPs locais deste dispositivo (Wi-Fi/LAN), como sugestão de para onde
  /// outro dispositivo na MESMA rede pode discar para abrir um canal direto.
  /// Só funciona se ambos estiverem na mesma rede — não atravessa a
  /// internet nem NAT/CGNAT (por isso não é um endereço "público").
  Future<List<String>> getLocalNetworkAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((a) => !a.startsWith('169.254.')) // link-local, sem uso aqui
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> getOnchainBalance() async {
    if (_consumerNode.api == null) return _consumerNode.onchainBalanceSats;
    await _refreshBalances(_consumerNode);
    return _consumerNode.onchainBalanceSats;
  }

  /// Força uma sincronização com a rede agora, para o usuário não depender do
  /// tick periódico quando sabe que algo mudou em outro aparelho.
  Future<void> atualizarAgora() async {
    final f = _dispararSync;
    if (f == null) return;
    await f();
  }

  Future<void> syncNode() async {
    if (_consumerNode.api == null) return;
    await _consumerNode.api!.sync();
    _consumerNode.saldoConfirmadoPorSync = true;
    await _refreshBalances(_consumerNode);
    notifyListeners();
  }

  /// Varredura profunda: força a carteira a enxergar endereços de índice alto.
  ///
  /// Por que isso é necessário: o BDK só consulta na rede os endereços que já
  /// tem em cache, e o cache anda em blocos de 100 (`CACHE_ADDR_BATCH_SIZE`)
  /// a partir do último índice revelado. Uma carteira recém-criada revelou
  /// pouca coisa, então dinheiro parado num índice alto — situação típica de
  /// quem trocou de rede e recomeçou com um banco vazio — fica invisível: o
  /// endereço nunca entra na consulta.
  ///
  /// Revelar endereços empurra o cache para frente e traz esses fundos de
  /// volta ao campo de visão. O custo é queimar índices de derivação, o que
  /// não perde dinheiro nenhum — só avança o contador.
  Future<int> deepScan({int ateIndice = 150, bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (handle.api == null) return 0;

    var revelados = 0;
    for (var i = 0; i < ateIndice; i++) {
      try {
        final addr = await handle.api!.newOnchainAddress();
        // Cada endereço revelado aqui também é "meu": alimenta o aviso de
        // autoenvio em [enderecoEhDaMinhaCarteira].
        await _registrarEnderecoProprio(addr);
        revelados++;
      } catch (e) {
        debugPrint('Varredura profunda parou no índice $i: $e');
        break;
      }
    }

    try {
      await handle.api!.sync();
      handle.saldoConfirmadoPorSync = true;
    } catch (e) {
      debugPrint('Sync após varredura profunda falhou: $e');
    }
    await _refreshBalances(handle);
    notifyListeners();
    return revelados;
  }

  Future<List<ChannelSummary>> getChannels() async {
    if (!_consumerNode.isRunning || _consumerNode.api == null) {
      if (_consumerNode.isMock) return [];
      throw Exception('Nó Lightning não está rodando.');
    }
    return await _consumerNode.api!.channels();
  }

  Future<void> openChannel({
    required String pubKeyHex,
    required String host,
    required int port,
    required int amountSats,
  }) async {
    if (!_consumerNode.isRunning || _consumerNode.api == null) {
      throw Exception('Nó offline');
    }
    await _consumerNode.api!.openChannel(
      nodeId: pubKeyHex,
      host: host,
      port: port,
      amountSats: amountSats,
    );
    notifyListeners();
  }

  /// Define a taxa de roteamento que ESTE usuário cobra quando o próprio nó
  /// dele encaminha (roteia) um pagamento de outra pessoa por [userChannelId].
  /// É nativo do protocolo Lightning: quem ganha é sempre o dono do nó — o
  /// Iris nunca fica com nada disso, nem precisa de nenhum sistema de
  /// pagamento próprio para viabilizar.
  Future<void> updateForwardingFee({
    required String counterpartyNodeId,
    required String userChannelId,
    required int proportionalPpm,
    required int baseMsat,
  }) async {
    if (!_consumerNode.isRunning || _consumerNode.api == null) {
      throw Exception('Nó offline');
    }
    await _consumerNode.api!.updateForwardingFee(
      counterpartyNodeId: counterpartyNodeId,
      userChannelId: userChannelId,
      proportionalPpm: proportionalPpm,
      baseMsat: baseMsat,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Lightning: faturas e pagamentos reais (testnet)
  // ---------------------------------------------------------------------

  /// Gera fatura BOLT11 real no nó do perfil correspondente.
  Future<String> createInvoice(int amountSats, String desc,
      {bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;
    // Nó em mock (ex.: timeout no boot): tenta reiniciar antes de falhar.
    if (handle.api == null) {
      // Com prazo: o start pode estar na fila atrás de outro que ainda tenta
      // subir. Sem este limite a tela do QR ficava "carregando" para sempre,
      // sem erro e sem endereço — pior do que dizer que não deu.
      try {
        await restartNode(forMerchant: forMerchant)
            .timeout(const Duration(seconds: 50));
      } on TimeoutException {
        throw Exception(
            'O nó está demorando para conectar à rede. Toque para tentar de novo.');
      }
      handle = forMerchant ? _merchantNode : _consumerNode;
    }
    if (!handle.isRunning || handle.api == null) {
      if (handle.isMock) {
        final reason = handle.lastStartError;
        throw Exception(reason != null
            ? 'Motor do nó indisponível nesta plataforma. Detalhe: $reason'
            : 'Motor do nó indisponível nesta plataforma. Verifique a instalação ou configure um daemon local.');
      }
      throw Exception('Nó offline');
    }
    return await handle.api!.createInvoice(
      amountMsat: amountSats * 1000,
      description: desc,
      expirySecs: 3600,
    );
  }

  /// Paga uma fatura BOLT11 real via LDK. Para faturas de valor aberto,
  /// [amountSatsOverride] define quanto enviar.
  Future<Map<String, dynamic>> payLightningInvoice(String invoiceStr,
      {int? amountSatsOverride}) async {
    final handle = _consumerNode;
    if (!handle.isRunning) {
      throw Exception('Nó Lightning não está rodando.');
    }

    final parsed = Bolt11.decode(invoiceStr);
    if (parsed.isExpired) {
      throw Exception('Fatura expirada.');
    }
    final sats = parsed.amountSats ?? amountSatsOverride;
    if (sats == null || sats <= 0) {
      throw Exception('Fatura sem valor definido — informe o valor a enviar.');
    }

    if (handle.api == null) {
      throw Exception(
          'Motor do nó indisponível nesta plataforma. Verifique a instalação ou configure um daemon local.');
    }

    await handle.api!.payInvoice(
      invoiceStr.trim(),
      amountMsat: parsed.amountSats == null ? sats * 1000 : null,
    );

    final tx = Transaction(
      id: parsed.paymentHashHex,
      title: parsed.description.isNotEmpty
          ? parsed.description
          : 'Pagamento Lightning',
      emoji: '⚡',
      amountSats: sats,
      isIncoming: false,
      date: DateTime.now(),
      status: 'pending', // confirmado pelo evento PaymentSuccessful
    );
    _registrarTransacao(tx, isMerchant: false);
    await _refreshBalances(handle);
    notifyListeners();

    return {
      'status': 'sent',
      'paymentHash': parsed.paymentHashHex,
      'nerdData':
          '[ LIGHTNING LDK ]\nPayment Hash: ${parsed.paymentHashHex}\nValor: $sats sats\nRede: Testnet4',
    };
  }

  /// Envio pela rede Bitcoin (on-chain) — trilho de grandes valores.
  Future<String> sendOnchain(
      {required String address, required int sats}) async {
    final handle = _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      throw Exception('Nó não está rodando.');
    }
    final txid = await handle.api!.sendOnchain(address: address, sats: sats);

    final tx = Transaction(
      id: txid,
      title: 'Envio on-chain (Bitcoin)',
      emoji: '₿',
      amountSats: sats,
      isIncoming: false,
      date: DateTime.now(),
    );
    _registrarTransacao(tx, isMerchant: false);
    await _refreshBalances(handle);
    notifyListeners();
    return txid;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _fastWatchTimer?.cancel();
    _paymentsCtrl.close();
    _consumerNode.stop();
    _merchantNode.stop();
    super.dispose();
  }
}

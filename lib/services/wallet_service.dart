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

import '../core/bolt11.dart';
import 'node_backend.dart';
import 'product_image_store.dart';

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
    description: json['description'] is String ? json['description'] as String : '',
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
  final String title;
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
}

class AccountProfile {
  final String id;
  final String name;
  final String seed;
  final String pinHash;

  AccountProfile({required this.id, required this.name, required this.seed, required this.pinHash});

  AccountProfile copyWith({String? pinHash}) => AccountProfile(
    id: id,
    name: name,
    seed: seed,
    pinHash: pinHash ?? this.pinHash,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'seed': seed,
    'pinHash': pinHash,
  };

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    id: json['id'],
    name: json['name'],
    seed: json['seed'],
    pinHash: json['pinHash'],
  );
}

/// Notificação de pagamento recebido (Lightning ou on-chain).
class ReceivedPayment {
  final bool isMerchant;
  final String paymentHashHex; // vazio para recebimentos on-chain
  final int amountSats;
  final bool isOnchain;
  ReceivedPayment({
    required this.isMerchant,
    required this.paymentHashHex,
    required this.amountSats,
    this.isOnchain = false,
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
  int onchainBalanceSats = 0;
  bool balancesInitialized = false;
  String? fixedInvoice;
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
    lightningBalanceSats = 0;
    onchainBalanceSats = 0;
    // A fatura fixa pertence à conta que estava ativa. Se ficasse aqui, a
    // próxima conta exibiria o QR estático da anterior e o pagamento cairia
    // na carteira errada.
    fixedInvoice = null;
    lastStartError = null;
  }
}

class WalletService extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<AccountProfile> _consumerAccounts = [];
  List<AccountProfile> _merchantAccounts = [];

  String? _activeConsumerId;
  String? _activeMerchantId;

  String? _tempConsumerSeed; // Usada durante a criação

  bool _isUnlocked = false;
  bool _isMerchantUnlocked = false;
  bool _isNfcEnabled = false;
  String _lastSessionType = 'consumer';

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

  /// Seed única do aparelho. A primeira carteira criada a define; importar uma
  /// semente substitui a carteira do dispositivo inteiro.
  String? _deviceSeed;
  String? get deviceSeed => _deviceSeed;

  /// Pasta de dados do nó. Fixa, porque o nó é do dispositivo.
  static const String _deviceNodeDir = 'ldk_device';

  Timer? _syncTimer;

  final StreamController<ReceivedPayment> _paymentsCtrl =
      StreamController<ReceivedPayment>.broadcast();

  /// Stream de pagamentos recebidos (eventos reais do LDK).
  Stream<ReceivedPayment> get paymentsReceived => _paymentsCtrl.stream;

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

  bool get hasConsumerPin => activeConsumer != null || _tempConsumerSeed != null;
  bool get isUnlocked => _isUnlocked;
  /// A semente é do dispositivo. Durante a criação, mostra a temporária.
  String? get consumerSeed => _tempConsumerSeed ?? _deviceSeed ?? activeConsumer?.seed;

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

  /// Mesma semente da carteira pessoal: a loja é um perfil sobre a carteira
  /// do dispositivo, não uma carteira separada.
  String? get merchantSeed => _deviceSeed ?? activeMerchant?.seed;
  String? get merchantName => activeMerchant?.name;

  List<Product> _merchantProducts = [];
  List<Product> get merchantProducts => _merchantProducts;

  final List<Transaction> _consumerTransactions = [];
  final List<Transaction> _merchantTransactions = [];

  /// Saldo unificado em sats (moeda principal do app): Lightning + on-chain.
  /// O saldo L-BTC da Liquid é somado na camada de UI via LiquidWalletService.
  int get consumerBalance => _consumerNode.totalSats;
  int get merchantBalance => _merchantNode.totalSats;
  int get consumerLightningSats => _consumerNode.lightningBalanceSats;
  int get consumerOnchainSats => _consumerNode.onchainBalanceSats;
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

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
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
    final encoded = jsonEncode(_consumerAccounts.map((e) => e.toJson()).toList());
    await _storage.write(key: 'consumer_accounts', value: encoded);
    if (_activeConsumerId != null) {
      await _storage.write(key: 'active_consumer_id', value: _activeConsumerId!);
    } else {
      await _storage.delete(key: 'active_consumer_id');
    }
  }

  Future<void> _saveMerchants() async {
    final encoded = jsonEncode(_merchantAccounts.map((e) => e.toJson()).toList());
    await _storage.write(key: 'merchant_accounts', value: encoded);
    if (_activeMerchantId != null) {
      await _storage.write(key: 'active_merchant_id', value: _activeMerchantId!);
    } else {
      await _storage.delete(key: 'active_merchant_id');
    }
  }

  Future<void> _saveLastSession() async {
    await _storage.write(key: 'last_session_type', value: _lastSessionType);
  }

  Future<void> initWallet() async {
    final consumersStr = await _storage.read(key: 'consumer_accounts');
    if (consumersStr != null) {
      final List decoded = jsonDecode(consumersStr);
      _consumerAccounts = decoded.map((e) => AccountProfile.fromJson(e)).toList();
      _activeConsumerId = await _storage.read(key: 'active_consumer_id');

      final nfcSaved = await _storage.read(key: 'nfc_enabled');
      if (nfcSaved != null) {
        _isNfcEnabled = nfcSaved == 'true';
      }
    } else {
      final legacySeed = await _storage.read(key: 'consumer_seed');
      final legacyPin = await _storage.read(key: 'consumer_pin_hash');
      if (legacySeed != null && legacyPin != null) {
        final profile = AccountProfile(id: 'legacy_consumer', name: 'Carteira Pessoal 1', seed: legacySeed, pinHash: legacyPin);
        _consumerAccounts.add(profile);
        _activeConsumerId = profile.id;
        await _saveConsumers();
      }
    }

    final merchantsStr = await _storage.read(key: 'merchant_accounts');
    if (merchantsStr != null) {
      final List decoded = jsonDecode(merchantsStr);
      _merchantAccounts = decoded.map((e) => AccountProfile.fromJson(e)).toList();
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
      final legacyName = await _storage.read(key: 'merchant_name') ?? 'Minha Loja 1';
      if (legacySeed != null && legacyPin != null) {
        final profile = AccountProfile(id: 'legacy_merchant', name: legacyName, seed: legacySeed, pinHash: legacyPin);
        _merchantAccounts.add(profile);
        _activeMerchantId = profile.id;
        await _saveMerchants();
      }
    }

    // Catálogo da loja: carregado AQUI, junto do perfil, e não mais dentro do
    // _startNode. Antes, se o nó falhasse ou demorasse a subir, os produtos
    // nunca eram carregados e pareciam apagados a cada abertura do app.
    await _carregarSeedDoDispositivo();

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

  /// Lê a semente do dispositivo. Em aparelhos que vêm da versão com uma seed
  /// por conta, adota a da carteira pessoal ativa (ou a da loja, se só houver
  /// loja) e migra a pasta do nó, para não perder os canais existentes.
  Future<void> _carregarSeedDoDispositivo() async {
    _deviceSeed = await _storage.read(key: 'device_seed');
    if (_deviceSeed != null) return;

    final herdada = activeConsumer?.seed ?? activeMerchant?.seed;
    if (herdada == null) return; // aparelho ainda sem carteira

    _deviceSeed = herdada;
    await _storage.write(key: 'device_seed', value: herdada);
    await _migrarPastaDoNo();
  }

  /// Move os dados do nó da conta para a pasta única do dispositivo.
  Future<void> _migrarPastaDoNo() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final destino = Directory('${docs.path}/$_deviceNodeDir');
      if (await destino.exists()) return; // já migrado

      final origemNome = activeConsumer != null
          ? 'ldk_c_${activeConsumer!.id}'
          : (activeMerchant != null ? 'ldk_m_${activeMerchant!.id}' : null);
      if (origemNome == null) return;

      final origem = Directory('${docs.path}/$origemNome');
      if (!await origem.exists()) return;

      await origem.rename(destino.path);
      debugPrint('Nó migrado de $origemNome para $_deviceNodeDir.');
    } catch (e) {
      debugPrint('Falha ao migrar a pasta do nó: $e');
    }
  }

  /// Define a semente do aparelho na primeira carteira criada/importada.
  Future<void> _definirSeedDoDispositivo(String seed) async {
    _deviceSeed = seed;
    await _storage.write(key: 'device_seed', value: seed);
  }

  Future<bool> checkHasWallet() async {
    await initWallet();
    return _consumerAccounts.isNotEmpty || _merchantAccounts.isNotEmpty;
  }

  /// Gera uma semente nova. [words] aceita 12 (128 bits de entropia) ou
  /// 24 (256 bits) — os dois tamanhos padrão do BIP39.
  void resetAndGenerateSeed({int words = 12}) {
    _tempConsumerSeed = generateSeedPhrase(words: words);
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
    notifyListeners();
  }

  void cancelWalletCreation() {
    _tempConsumerSeed = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Desbloqueio / criação de contas
  // ---------------------------------------------------------------------

  /// Verificação pura do PIN (confirmação de pagamento etc.) — sem nenhum
  /// efeito colateral de sessão: não navega, não notifica, não mexe no nó.
  bool verifyConsumerPin(String pin) {
    final active = activeConsumer;
    return active != null && verifyPin(pin, active.pinHash);
  }

  bool verifyMerchantPin(String pin) {
    final active = activeMerchant;
    return active != null && verifyPin(pin, active.pinHash);
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
      _consumerAccounts.add(newAccount);
      _activeConsumerId = newAccount.id;
      _tempConsumerSeed = null;

      // Uma seed por dispositivo: a primeira carteira criada define a do
      // aparelho; as demais contas são perfis sobre ela.
      if (_deviceSeed == null) {
        await _definirSeedDoDispositivo(newAccount.seed);
      }

      await _saveConsumers();
      _isUnlocked = true;
      _consumerTransactions.clear();
      await setLastSessionType('consumer');
      notifyListeners();

      _startNode(_consumerNode, _deviceSeed!, _deviceNodeDir, isMerchant: false)
          .catchError((e) => debugPrint('Erro ao iniciar LDK após criação: $e'));
      return true;
    }

    // Verificação de conta existente
    final active = activeConsumer;
    if (active != null && verifyPin(pin, active.pinHash)) {
      // Migra hash legado para PBKDF2 no primeiro desbloqueio bem-sucedido
      if (_isLegacyHash(active.pinHash)) {
        final idx = _consumerAccounts.indexWhere((a) => a.id == active.id);
        _consumerAccounts[idx] = active.copyWith(pinHash: hashPin(pin));
        await _saveConsumers();
      }
      _isUnlocked = true;
      await setLastSessionType('consumer');
      notifyListeners();
      _startNode(_consumerNode, _deviceSeed ?? active.seed, _deviceNodeDir, isMerchant: false)
          .catchError((e) => debugPrint('Erro ao iniciar LDK: $e'));
      return true;
    }
    return false;
  }

  /// Cria o perfil de loja. Se o aparelho já tem carteira, [seed] é ignorada:
  /// a loja é um PERFIL sobre a carteira do dispositivo, com o mesmo saldo.
  /// A semente informada só vale quando ainda não existe carteira aqui.
  Future<void> setupMerchant(String name, String seed, String pin) async {
    final jaTinhaCarteira = _deviceSeed != null;
    if (!jaTinhaCarteira) {
      await _definirSeedDoDispositivo(seed);
    }
    final seedDoPerfil = _deviceSeed!;

    final newAccount = AccountProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      seed: seedDoPerfil,
      pinHash: hashPin(pin),
    );

    _merchantAccounts.add(newAccount);
    _activeMerchantId = newAccount.id;
    ProductImageStore.definirLoja(newAccount.id);
    await _saveMerchants();

    _isMerchantUnlocked = true;
    // Loja nova nasce sem catálogo próprio; o SALDO é o do dispositivo.
    _clearMerchantSessionState();
    await setLastSessionType('merchant');
    notifyListeners();

    _startNode(_merchantNode, _deviceSeed!, _deviceNodeDir, isMerchant: true)
        .catchError((e) => debugPrint('Erro ao iniciar LDK da loja: $e'));
  }

  Future<bool> unlockMerchant(String pin) async {
    final active = activeMerchant;
    if (active == null) return false;

    if (verifyPin(pin, active.pinHash)) {
      if (_isLegacyHash(active.pinHash)) {
        final idx = _merchantAccounts.indexWhere((a) => a.id == active.id);
        _merchantAccounts[idx] = active.copyWith(pinHash: hashPin(pin));
        await _saveMerchants();
      }
      _isMerchantUnlocked = true;
      await setLastSessionType('merchant');
      notifyListeners();
      _startNode(_merchantNode, _deviceSeed ?? active.seed, _deviceNodeDir, isMerchant: true)
          .catchError((e) => debugPrint('Erro ao iniciar LDK da loja: $e'));
      return true;
    }
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

  Future<void> _startNode(_NodeHandle handle, String mnemonic, String dirName,
      {required bool isMerchant}) async {
    if (handle.isRunning) return;
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
        );
        handle.isRemote = false;
      }

      await api.start();
      handle.api = api;
      handle.isRunning = true;
      handle.isMock = false;
      handle.lastStartError = null;
      handle.isMerchant = isMerchant;

      if (isMerchant) await _loadMerchantProducts();

      // Fatura fixa de valor aberto (QR estático). Gerada UMA vez e persistida;
      // em toda abertura seguinte é apenas recarregada do armazenamento (nunca
      // regenerada no boot) — assim o QR já aparece pronto, sem "indisponível".
      handle.fixedInvoice = await _loadFixedInvoice(isMerchant);
      if (handle.fixedInvoice == null || handle.fixedInvoice!.isEmpty) {
        try {
          final inv = await api.createInvoice(
            amountMsat: null,
            description: isMerchant ? 'Loja' : 'Carteira Principal',
            expirySecs: 31536000, // 1 ano
          );
          handle.fixedInvoice = inv;
          await _saveFixedInvoice(isMerchant, inv);
        } catch (e) {
          debugPrint('Falha ao gerar fatura fixa: $e');
        }
      }

      await _refreshBalances(handle);
      _runEventLoop(handle, isMerchant: isMerchant);
      _ensureSyncTimer();

      notifyListeners();
      debugPrint(
          'Nó (${isMerchant ? 'loja' : 'pessoal'}) iniciado na testnet — backend ${handle.isRemote ? 'daemon local' : 'embarcado'}.');
    } catch (e) {
      debugPrint('Falha ao iniciar nó (${isMerchant ? 'loja' : 'pessoal'}): $e');
      // Fallback de UI: mantém o app utilizável se o motor nativo não carregar.
      // Ainda assim mostra o QR estático persistido (se já existir), para o
      // lojista não ver "indisponível" enquanto o nó religa.
      handle.isRunning = true;
      handle.isMock = true;
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
              (isMerchant ? _merchantTransactions : _consumerTransactions).insert(0, tx);
              _paymentsCtrl.add(ReceivedPayment(
                isMerchant: isMerchant,
                paymentHashHex: event.paymentHashHex,
                amountSats: sats,
              ));
              // Fatura BOLT11 é de uso único: regenera o QR fixo (e persiste)
              // SÓ após um recebimento — exigência da Lightning para que o QR
              // continue válido. Fora isso, ele nunca é recarregado.
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
              break;
            case 'payment_successful':
              final txs = isMerchant ? _merchantTransactions : _consumerTransactions;
              for (final tx in txs) {
                if (tx.id == event.paymentHashHex && tx.status == 'pending') {
                  tx.status = 'confirmed';
                }
              }
              break;
            case 'payment_failed':
              final txs = isMerchant ? _merchantTransactions : _consumerTransactions;
              for (final tx in txs) {
                if (tx.id == event.paymentHashHex && tx.status == 'pending') {
                  tx.status = 'failed';
                }
              }
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

  Future<void> _refreshBalances(_NodeHandle handle) async {
    if (handle.api == null) return;
    try {
      final balances = await handle.api!.balances();
      handle.lightningBalanceSats = balances.lightningSats;
      final newOnchain = balances.onchainTotalSats;

      // Detecção de depósito puro na rede Bitcoin (on-chain): o LDK não
      // emite evento para isso, então comparamos o saldo entre syncs.
      final previous = handle.onchainBalanceSats;
      if (handle.balancesInitialized && newOnchain > previous) {
        final delta = newOnchain - previous;
        final tx = Transaction(
          id: 'onchain_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Recebido on-chain (Bitcoin)',
          emoji: '₿',
          amountSats: delta,
          isIncoming: true,
          date: DateTime.now(),
        );
        (handle.isMerchant ? _merchantTransactions : _consumerTransactions).insert(0, tx);
        _paymentsCtrl.add(ReceivedPayment(
          isMerchant: handle.isMerchant,
          paymentHashHex: '',
          amountSats: delta,
          isOnchain: true,
        ));
      }
      handle.onchainBalanceSats = newOnchain;
      handle.balancesInitialized = true;
    } catch (e) {
      debugPrint('refreshBalances: $e');
    }
  }

  void _ensureSyncTimer() {
    _syncTimer ??= Timer.periodic(const Duration(seconds: 60), (_) async {
      for (final handle in [_consumerNode, _merchantNode]) {
        if (handle.api != null) {
          try {
            await handle.api!.sync();
            await _refreshBalances(handle);
          } catch (e) {
            debugPrint('Sync periódico: $e');
          }
        }
      }
      notifyListeners();
    });
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
      await ProductImageStore.apagarLoja(a.id);
    }
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
      // A loja deixou de existir: as fotos dela vão junto.
      await ProductImageStore.apagarLoja(removedId);
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
    await _consumerNode.stop();
    _clearConsumerSessionState();
    _activeConsumerId = id;
    await _saveConsumers();
    _isUnlocked = false; // Requer PIN para a nova conta
    notifyListeners();
  }

  Future<void> switchMerchantAccount(String id) async {
    await _merchantNode.stop();
    _clearMerchantSessionState();
    _activeMerchantId = id;
    // As fotos seguem a loja: sem isto, a limpeza de órfãs da loja nova
    // apagaria as fotos da anterior.
    ProductImageStore.definirLoja(id);
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
    final jsonStr = jsonEncode(_merchantProducts.map((p) => p.toJson()).toList());
    await prefs.setString(key, jsonStr);
  }

  Future<void> _deleteMerchantProducts(String merchantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('merchant_products_$merchantId');
  }

  // Fatura fixa (QR estático) persistida por perfil: gerada uma vez na criação
  // da carteira e reutilizada sempre; só troca após um recebimento (uso único).
  Future<String?> _loadFixedInvoice(bool isMerchant) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fixed_invoice_$id');
  }

  Future<void> _saveFixedInvoice(bool isMerchant, String invoice) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fixed_invoice_$id', invoice);
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
    // O nó é do dispositivo: mesma seed e mesma pasta, venha de onde vier.
    final seed = _deviceSeed ??
        (forMerchant ? activeMerchant?.seed : activeConsumer?.seed);
    if (seed == null) return;
    await _startNode(handle, seed, _deviceNodeDir, isMerchant: forMerchant);
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
    final emUso = _merchantProducts
        .map((p) => p.image)
        .whereType<String>()
        .toSet();
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
        throw const FormatException('O arquivo não contém uma lista de produtos.');
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
      throw const FormatException('Nenhum produto válido foi encontrado no arquivo.');
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
      await restartNode(forMerchant: forMerchant);
      handle = forMerchant ? _merchantNode : _consumerNode;
    }
    if (!handle.isRunning || handle.api == null) {
      // Nunca exibir endereço falso: sem nó, sem endereço.
      final reason = handle.lastStartError;
      throw Exception(reason != null
          ? 'Nó indisponível — não é possível gerar endereço real. Detalhe: $reason'
          : 'Nó indisponível — não é possível gerar endereço real.');
    }
    return await handle.api!.newOnchainAddress();
  }

  Future<int> getOnchainBalance() async {
    if (_consumerNode.api == null) return _consumerNode.onchainBalanceSats;
    await _refreshBalances(_consumerNode);
    return _consumerNode.onchainBalanceSats;
  }

  Future<void> syncNode() async {
    if (_consumerNode.api == null) return;
    await _consumerNode.api!.sync();
    await _refreshBalances(_consumerNode);
    notifyListeners();
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

  // ---------------------------------------------------------------------
  // Lightning: faturas e pagamentos reais (testnet)
  // ---------------------------------------------------------------------

  /// Gera fatura BOLT11 real no nó do perfil correspondente.
  Future<String> createInvoice(int amountSats, String desc, {bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;
    // Nó em mock (ex.: timeout no boot): tenta reiniciar antes de falhar.
    if (handle.api == null) {
      await restartNode(forMerchant: forMerchant);
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
      title: parsed.description.isNotEmpty ? parsed.description : 'Pagamento Lightning',
      emoji: '⚡',
      amountSats: sats,
      isIncoming: false,
      date: DateTime.now(),
      status: 'pending', // confirmado pelo evento PaymentSuccessful
    );
    _consumerTransactions.insert(0, tx);
    await _refreshBalances(handle);
    notifyListeners();

    return {
      'status': 'sent',
      'paymentHash': parsed.paymentHashHex,
      'nerdData':
          '[ LIGHTNING LDK ]\nPayment Hash: ${parsed.paymentHashHex}\nValor: $sats sats\nRede: Testnet',
    };
  }

  /// Envio pela rede Bitcoin (on-chain) — trilho de grandes valores.
  Future<String> sendOnchain({required String address, required int sats}) async {
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
    _consumerTransactions.insert(0, tx);
    await _refreshBalances(handle);
    notifyListeners();
    return txid;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _paymentsCtrl.close();
    _consumerNode.stop();
    _merchantNode.stop();
    super.dispose();
  }
}

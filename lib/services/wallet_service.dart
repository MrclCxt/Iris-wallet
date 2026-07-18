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

class Product {
  final String id;
  String emoji;
  String name;
  double price;
  bool isActive;

  Product({
    required this.id,
    required this.emoji,
    required this.name,
    required this.price,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'emoji': emoji,
    'name': name,
    'price': price,
    'isActive': isActive,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'],
    emoji: json['emoji'],
    name: json['name'],
    price: json['price'],
    isActive: json['isActive'],
  );
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

  final _NodeHandle _consumerNode = _NodeHandle();
  final _NodeHandle _merchantNode = _NodeHandle();

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
  String? get consumerSeed => activeConsumer?.seed ?? _tempConsumerSeed;

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

  String? get merchantSeed => activeMerchant?.seed;
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

  Future<bool> checkHasWallet() async {
    await initWallet();
    return _consumerAccounts.isNotEmpty || _merchantAccounts.isNotEmpty;
  }

  void resetAndGenerateSeed() {
    _tempConsumerSeed = bip39.generateMnemonic();
    notifyListeners();
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

  Future<bool> unlock(String pin) async {
    // Fluxo de criação de nova conta
    if (_tempConsumerSeed != null) {
      final newAccount = AccountProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Carteira Pessoal ${_consumerAccounts.length + 1}',
        seed: _tempConsumerSeed!,
        pinHash: hashPin(pin),
      );
      _consumerAccounts.add(newAccount);
      _activeConsumerId = newAccount.id;
      _tempConsumerSeed = null;

      await _saveConsumers();
      _isUnlocked = true;
      _consumerTransactions.clear();
      await setLastSessionType('consumer');
      notifyListeners();

      _startNode(_consumerNode, newAccount.seed, 'ldk_c_${newAccount.id}', isMerchant: false)
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
      _startNode(_consumerNode, active.seed, 'ldk_c_${active.id}', isMerchant: false)
          .catchError((e) => debugPrint('Erro ao iniciar LDK: $e'));
      return true;
    }
    return false;
  }

  Future<void> setupMerchant(String name, String seed, String pin) async {
    final newAccount = AccountProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      seed: seed,
      pinHash: hashPin(pin),
    );

    _merchantAccounts.add(newAccount);
    _activeMerchantId = newAccount.id;
    await _saveMerchants();

    _isMerchantUnlocked = true;
    _merchantTransactions.clear();
    await setLastSessionType('merchant');
    notifyListeners();

    _startNode(_merchantNode, seed, 'ldk_m_${newAccount.id}', isMerchant: true)
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
      _startNode(_merchantNode, active.seed, 'ldk_m_${active.id}', isMerchant: true)
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
        api = EmbeddedNodeApi(mnemonic: mnemonic, storagePath: nodePath);
        handle.isRemote = false;
      }

      await api.start();
      handle.api = api;
      handle.isRunning = true;
      handle.isMock = false;
      handle.isMerchant = isMerchant;

      if (!isMerchant) {
        await _loadMerchantProducts();
        if (_merchantProducts.isEmpty) {
          addMerchantProduct(Product(id: 'prod_coffee', emoji: '☕', name: 'Café Expresso', price: 15.0));
        }
      }

      // Fatura fixa de valor aberto (QR estático da carteira)
      try {
        handle.fixedInvoice = await api.createInvoice(
          amountMsat: null,
          description: isMerchant ? 'Loja' : 'Carteira Principal',
          expirySecs: 31536000, // 1 ano
        );
      } catch (e) {
        debugPrint('Falha ao gerar fatura fixa: $e');
      }

      await _refreshBalances(handle);
      _runEventLoop(handle, isMerchant: isMerchant);
      _ensureSyncTimer();

      notifyListeners();
      debugPrint(
          'Nó (${isMerchant ? 'loja' : 'pessoal'}) iniciado na testnet — backend ${handle.isRemote ? 'daemon local' : 'embarcado'}.');
    } catch (e) {
      debugPrint('Falha ao iniciar nó: $e');
      // Fallback de UI: mantém o app utilizável se o motor nativo não carregar
      handle.isRunning = true;
      handle.isMock = true;
      handle.fixedInvoice = null;
      notifyListeners();
    }
  }

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
    notifyListeners();
  }

  Future<void> switchConsumerAccount(String id) async {
    await _consumerNode.stop();
    _activeConsumerId = id;
    await _saveConsumers();
    _isUnlocked = false; // Requer PIN para a nova conta
    notifyListeners();
  }

  Future<void> switchMerchantAccount(String id) async {
    await _merchantNode.stop();
    _activeMerchantId = id;
    await _saveMerchants();
    _isMerchantUnlocked = false; // Requer PIN para a nova loja
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Produtos do lojista
  // ---------------------------------------------------------------------

  Future<void> _loadMerchantProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('merchant_products');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _merchantProducts = jsonList.map((j) => Product.fromJson(j)).toList();
      } catch (e) {
        debugPrint('Failed to decode merchant products: $e');
      }
    }
  }

  Future<void> _saveMerchantProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_merchantProducts.map((p) => p.toJson()).toList());
    await prefs.setString('merchant_products', jsonStr);
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
      notifyListeners();
    }
  }

  void removeMerchantProduct(String id) {
    _merchantProducts.removeWhere((e) => e.id == id);
    _saveMerchantProducts();
    notifyListeners();
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
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      if (handle.isMock) return 'tb1q_modo_demonstracao';
      throw Exception('Nó Lightning não está rodando.');
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
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      if (handle.isMock) {
        throw Exception(
            'Motor do nó indisponível nesta plataforma. Verifique a instalação ou configure um daemon local.');
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

  @override
  void dispose() {
    _syncTimer?.cancel();
    _paymentsCtrl.close();
    _consumerNode.stop();
    _merchantNode.stop();
    super.dispose();
  }
}

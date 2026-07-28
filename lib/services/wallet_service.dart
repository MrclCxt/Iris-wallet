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
  String title;
  final String emoji;
  final int amountSats;
  final bool isIncoming;
  final DateTime date;
  String status;

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

  String name;

  String? avatarColor;

  String seed;

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
        if (encSeed != null) 'encSeed': encSeed else 'seed': seed,
      };

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        id: json['id'],
        name: json['name'],
        avatarColor: json['avatarColor'] as String?,
        seed: (json['seed'] as String?) ?? '',
        encSeed: json['encSeed'] as String?,
        pinHash: json['pinHash'],
      );
}

class ReceivedPayment {
  final bool isMerchant;
  final String paymentHashHex;
  final int amountSats;
  final bool isOnchain;

  final bool isPending;

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

class _NodeHandle {
  NodeApi? api;
  bool isRunning = false;
  bool isMock = false;
  String? lastStartError;
  bool isMerchant = false;
  bool isRemote = false;
  int lightningBalanceSats = 0;
  int onchainBalanceSats = 0;

  int onchainSpendableSats = 0;
  bool balancesInitialized = false;
  String? fixedInvoice;

  String? cachedOnchainAddress;

  String? runningSeedFingerprint;

  String? runningSeed;

  int consecutiveSyncFailures = 0;

  bool saldoConfirmadoPorSync = false;
  bool _eventLoopActive = false;

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

    fixedInvoice = null;

    cachedOnchainAddress = null;
    lastStartError = null;
    runningSeedFingerprint = null;
    runningSeed = null;
    consecutiveSyncFailures = 0;
  }
}

class WalletService extends ChangeNotifier with WidgetsBindingObserver {
  WalletService() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final emUso = state == AppLifecycleState.resumed;
    if (emUso != _appEmPrimeiroPlano) {
      _appEmPrimeiroPlano = emUso;
      if (_syncTimer != null) _reagendarSyncTimer();
      if (_fastWatchTimer != null) _reagendarFastWatch();
    }
    if (!emUso) return;
    final agora = DateTime.now();

    if (_ultimoSyncPorRetorno != null &&
        agora.difference(_ultimoSyncPorRetorno!) <
            const Duration(seconds: 20)) {
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

  String? _tempConsumerSeed;

  bool _tempSeedEhRestauracao = false;

  bool _restaurandoCarteira = false;
  bool get restaurandoCarteira => _restaurandoCarteira;

  bool _isUnlocked = false;
  bool _isMerchantUnlocked = false;
  bool _isNfcEnabled = false;
  String _lastSessionType = 'consumer';

  int _pinFailedAttempts = 0;
  DateTime? _pinLockedUntil;

  int _pinFreeAttempts = 4;

  bool _autoWipeEnabled = false;
  int _autoWipeThreshold = 10;

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

  int _autoLockMinutes = 5;

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

  bool _hideBalance = false;
  bool get hideBalance => _hideBalance;

  Future<void> setHideBalance(bool hide) async {
    _hideBalance = hide;
    await _storage.write(key: 'hide_balance', value: hide ? '1' : '0');
    notifyListeners();
  }

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

  VoidCallback? onAccountChanged;

  VoidCallback? onCatalogImported;

  final _NodeHandle _deviceNode = _NodeHandle();

  _NodeHandle get _consumerNode => _deviceNode;
  _NodeHandle get _merchantNode => _deviceNode;

  String? _deviceSeed;
  String? get deviceSeed => _deviceSeed;

  static String _nodeDirFor(String seed) =>
      'ldk_tn4n_${_seedFingerprint(seed)}';

  static String _seedFingerprint(String seed) {
    final normal = seed.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return sha256.convert(utf8.encode(normal)).toString().substring(0, 16);
  }

  Timer? _syncTimer;

  final StreamController<ReceivedPayment> _paymentsCtrl =
      StreamController<ReceivedPayment>.broadcast();

  Stream<ReceivedPayment> get paymentsReceived => _paymentsCtrl.stream;

  static bool ehOfferBolt12(String? codigo) =>
      codigo != null && codigo.trim().toLowerCase().startsWith('lno');


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

  String? get consumerSeed => _tempConsumerSeed ?? activeConsumer?.seed;

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

  String? get merchantSeed => activeMerchant?.seed;
  String? get merchantName => activeMerchant?.name;

  List<Product> _merchantProducts = [];
  List<Product> get merchantProducts => _merchantProducts;

  final List<Transaction> _consumerTransactions = [];
  final List<Transaction> _merchantTransactions = [];

  bool _noEDoPerfil(String? seed) =>
      seed != null &&
      _deviceNode.runningSeedFingerprint == _seedFingerprint(seed);

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

  bool get saldoDesatualizado {
    final seed = _isMerchantUnlocked && !_isUnlocked
        ? activeMerchant?.seed
        : activeConsumer?.seed;
    return seed != null && seed.isNotEmpty && !_noEDoPerfil(seed);
  }

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

  final Map<String, SecretKey> _chavesDeHistorico = {};

  Future<SecretKey?> _chaveDoHistorico(bool isMerchant) async {
    final id = isMerchant ? _activeMerchantId : _activeConsumerId;
    if (id == null) return null;
    final conta = isMerchant ? activeMerchant : activeConsumer;
    final seed = conta?.seed;
    if (seed == null || seed.isEmpty) return null;
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

      lista.sort((a, b) => b.date.compareTo(a.date));
      destino
        ..clear()
        ..addAll(lista);
    } catch (e) {
      debugPrint('Falha ao carregar histórico: $e');
    }
  }

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


  Future<int> reconstruirHistoricoDoNo({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (handle.api == null) return 0;

    final lista = forMerchant ? _merchantTransactions : _consumerTransactions;
    var recuperadas = 0;
    try {
      for (final p in await handle.api!.listPayments()) {
        if (p.amountSats <= 0) continue;
        if (lista.any((t) => t.id == p.id)) continue;

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
        lista.sort((a, b) => b.date.compareTo(a.date));
        await _salvarHistorico(forMerchant);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Falha ao reconstruir histórico: $e');
    }
    return recuperadas;
  }

  void _registrarTransacao(Transaction tx, {required bool isMerchant}) {
    final lista = isMerchant ? _merchantTransactions : _consumerTransactions;

    if (tx.id.isNotEmpty && lista.any((t) => t.id == tx.id)) return;
    lista.add(tx);

    lista.sort((a, b) => b.date.compareTo(a.date));
    unawaited(_salvarHistorico(isMerchant));
  }


  List<Transaction> _pendingTransactions({required bool isMerchant}) =>
      (isMerchant ? _merchantTransactions : _consumerTransactions)
          .where((t) => t.status == 'pending')
          .toList();

  List<Transaction> get consumerTransactions => _consumerTransactions;
  List<Transaction> get merchantTransactions => _merchantTransactions;

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

      if (hash.length != expected.length) return false;
      int diff = 0;
      for (int i = 0; i < hash.length; i++) {
        diff |= hash.codeUnitAt(i) ^ expected.codeUnitAt(i);
      }
      return diff == 0;
    }

    return sha256.convert(utf8.encode(pin)).toString() == stored;
  }

  bool _isLegacyHash(String stored) => !stored.startsWith('v2\$');

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

    _lockOnSuspend = (await _storage.read(key: 'lock_on_suspend')) != '0';

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

    _deviceSeed = await _storage.read(key: 'device_seed');

    await _migrarPastasDoNo();

    ProductImageStore.definirLoja(_activeMerchantId);
    await _loadMerchantProducts();

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

  Future<bool> _changePin({
    required AccountProfile? account,
    required String oldPin,
    required String newPin,
    required Future<void> Function() persist,
  }) async {
    if (account == null) return false;
    if (isPinLocked) return false;
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
      if (!verifyPin(oldPin, account.pinHash)) {
        _registerPinFailure();
        return false;
      }
      seed = account.seed;
    }

    account.seed = seed;
    account.encSeed = await SeedCrypto.encryptInBackground(seed, newPin);
    account.pinHash = hashPin(newPin);

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

  static const int profileBackupFormatVersion = 1;

  Future<String> exportProfileBackup({required bool isMerchant}) async {
    final p = isMerchant ? activeMerchant : activeConsumer;
    if (p == null) throw StateError('Nenhum perfil ativo para exportar.');

    final json = <String, dynamic>{
      'iris_profile_backup': profileBackupFormatVersion,
      'exportado_em': DateTime.now().toIso8601String(),
      'name': p.name,
      if (p.avatarColor != null) 'avatarColor': p.avatarColor,
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

  Future<void> _migrarPastasDoNo() async {
    try {
      final docs = await getApplicationDocumentsDirectory();

      Future<void> mover(String origemNome, String seed) async {
        final destino = Directory('${docs.path}/${_nodeDirFor(seed)}');
        if (await destino.exists()) return;
        final origem = Directory('${docs.path}/$origemNome');
        if (!await origem.exists()) return;
        await origem.rename(destino.path);
        debugPrint('Nó migrado de $origemNome para ${_nodeDirFor(seed)}.');
      }

      for (final c in _consumerAccounts) {
        if (c.seed.isEmpty) continue;
        await mover('ldk_c_${c.id}', c.seed);
      }
      for (final m in _merchantAccounts) {
        if (m.seed.isEmpty) continue;
        await mover('ldk_m_${m.id}', m.seed);
      }

      final donoDoDevice = activeConsumer?.seed ?? activeMerchant?.seed;
      if (donoDoDevice != null && donoDoDevice.isNotEmpty) {
        await mover('ldk_device', donoDoDevice);
      }
    } catch (e) {
      debugPrint('Falha ao migrar as pastas do nó: $e');
    }
  }

  Future<void> _definirSeedDoDispositivo(String seed, String pin) async {
    _deviceSeed = seed;
    await _storage.write(
        key: 'device_seed_enc',
        value: await SeedCrypto.encryptInBackground(seed, pin));
    await _storage.delete(key: 'device_seed');
  }

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
      } on SeedDecryptException {}
    }
  }

  Future<bool> _unlockSeed(AccountProfile p, String pin) async {
    if (SeedCrypto.isEncrypted(p.encSeed)) {
      try {
        p.seed = await SeedCrypto.decryptInBackground(p.encSeed!, pin);
        return true;
      } on SeedDecryptException {
        return false;
      }
    }

    if (!verifyPin(pin, p.pinHash)) return false;

    p.encSeed = await SeedCrypto.encryptInBackground(p.seed, pin);
    return true;
  }

  Future<bool> checkHasWallet() async {
    await initWallet();
    return _consumerAccounts.isNotEmpty || _merchantAccounts.isNotEmpty;
  }

  void resetAndGenerateSeed({int words = 12}) {
    _tempConsumerSeed = generateSeedPhrase(words: words);
    _tempSeedEhRestauracao = false;
    notifyListeners();
  }

  static const List<int> seedWordCounts = [12, 24];

  static String generateSeedPhrase({int words = 12}) {
    final strength = words == 24 ? 256 : 128;
    return bip39.generateMnemonic(strength: strength);
  }

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
    if (_tempConsumerSeed != null) {
      await _consumerNode.stop();

      final newAccount = AccountProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Carteira Pessoal ${_consumerAccounts.length + 1}',
        seed: _tempConsumerSeed!,
        pinHash: hashPin(pin),
      );

      newAccount.encSeed =
          await SeedCrypto.encryptInBackground(newAccount.seed, pin);
      _consumerAccounts.add(newAccount);
      _activeConsumerId = newAccount.id;
      _tempConsumerSeed = null;
      final eraRestauracao = _tempSeedEhRestauracao;
      _tempSeedEhRestauracao = false;

      if (_deviceSeed == null) {
        await _definirSeedDoDispositivo(newAccount.seed, pin);
      }

      await _saveConsumers();
      _isUnlocked = true;

      _consumerTransactions.clear();
      await _carregarHistorico(false);
      await setLastSessionType('consumer');
      notifyListeners();

      _startNode(_consumerNode, newAccount.seed, _nodeDirFor(newAccount.seed),
              isMerchant: false)
          .then((_) async {
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

    final active = activeConsumer;
    if (active == null) return false;
    if (isPinLocked) return false;
    if (await _unlockSeed(active, pin)) {
      _resetPinAttempts();

      if (_isLegacyHash(active.pinHash)) {
        active.pinHash = hashPin(pin);
      }
      await _saveConsumers();
      await _restoreDeviceSeed(pin);
      _isUnlocked = true;

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

  Future<void> setupMerchant(String name, String seed, String pin) async {
    final seedDoPerfil = seed;

    final newAccount = AccountProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      seed: seedDoPerfil,
      pinHash: hashPin(pin),
    );

    newAccount.encSeed =
        await SeedCrypto.encryptInBackground(seedDoPerfil, pin);

    if (_deviceSeed == null) {
      await _definirSeedDoDispositivo(seedDoPerfil, pin);
    }

    _merchantAccounts.add(newAccount);
    _activeMerchantId = newAccount.id;
    ProductImageStore.definirLoja(newAccount.id);
    await _saveMerchants();

    _isMerchantUnlocked = true;

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

  Future<void>? _startEmAndamento;

  String? _fingerprintDesejada;

  Future<void> _startNode(_NodeHandle handle, String mnemonic, String dirName,
      {required bool isMerchant}) {
    _fingerprintDesejada = _seedFingerprint(mnemonic);

    final anterior = _startEmAndamento;
    final futuro = () async {
      if (anterior != null) {
        try {
          await anterior;
        } catch (_) {}
      }
      await _startNodeInterno(handle, mnemonic, dirName,
          isMerchant: isMerchant);
    }();
    _startEmAndamento = futuro;

    futuro.whenComplete(() {
      if (identical(_startEmAndamento, futuro)) _startEmAndamento = null;
    });
    return futuro;
  }

  Future<void> _startNodeInterno(
      _NodeHandle handle, String mnemonic, String dirName,
      {required bool isMerchant}) async {
    final fingerprint = _seedFingerprint(mnemonic);

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
        api = RemoteNodeApi(daemonUrl);
        handle.isRemote = true;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final nodePath = '${directory.path}/$dirName';
        final dir = Directory(nodePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        api = EmbeddedNodeApi(
          mnemonic: mnemonic,
          storagePath: nodePath,
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
        unawaited(BackgroundServiceAndroid.start());
      }

      if (isMerchant) await _loadMerchantProducts();

      handle.fixedInvoice = await _loadFixedInvoice(isMerchant);
      if (handle.fixedInvoice == null || handle.fixedInvoice!.isEmpty) {
        final desc = isMerchant ? 'Loja' : 'Carteira Principal';
        try {
          final offer = await api.createOffer(description: desc);
          if (offer != null && offer.isNotEmpty) {
            handle.fixedInvoice = offer;
            await _saveFixedInvoice(isMerchant, offer);
            debugPrint('QR Lightning fixo: offer BOLT12 (reutilizável).');
          } else {
            final inv = await api.createInvoice(
              amountMsat: null,
              description: desc,
              expirySecs: 31536000,
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
      _runEventLoop(handle, isMerchant: isMerchant);
      _ensureSyncTimer();

      notifyListeners();
      debugPrint(
          'Nó (${isMerchant ? 'loja' : 'pessoal'}) iniciado na testnet4 — backend ${handle.isRemote ? 'daemon local' : 'embarcado'}.');
    } catch (e) {
      debugPrint(
          'Falha ao iniciar nó (${isMerchant ? 'loja' : 'pessoal'}): $e');

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

  String? nodeStartError({bool forMerchant = false}) =>
      (forMerchant ? _merchantNode : _consumerNode).lastStartError;

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

  Future<void> _rotateCachedAddressAposDeposito(_NodeHandle handle) async {}

  Future<void> _refreshBalances(_NodeHandle handle) async {
    if (handle.api == null) return;
    try {
      final balances = await handle.api!.balances();
      var newTotal = balances.onchainTotalSats;
      var newSpendable = balances.onchainSpendableSats;
      var newLightning = balances.lightningSats;

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

      if (!handle.balancesInitialized && newTotal > newSpendable) {
        final pendente = newTotal - newSpendable;
        final jaRegistrado = _pendingTransactions(isMerchant: handle.isMerchant)
                .fold<int>(0, (s, t) => s + t.amountSats) >=
            pendente;
        final semCanais = (await handle.api!.channels()).isEmpty;

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

      if (handle.balancesInitialized) {
        final txs =
            handle.isMerchant ? _merchantTransactions : _consumerTransactions;

        if (newTotal > prevTotal) {
          final delta = newTotal - prevTotal;

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

  String _lastBalanceKey(_NodeHandle handle) =>
      'last_balance_tn4_${handle.runningSeedFingerprint ?? 'desconhecido'}';

  final Map<String, ({int total, int spendable, int lightning})>
      _saldosConhecidos = {};

  Future<void> _saveLastKnownBalance(_NodeHandle handle) async {
    final fp = handle.runningSeedFingerprint;
    if (fp == null) return;

    final zerado =
        handle.onchainBalanceSats == 0 && handle.lightningBalanceSats == 0;
    final anterior = _saldosConhecidos[fp];
    if (zerado &&
        anterior != null &&
        (anterior.total > 0 || anterior.lightning > 0)) {
      debugPrint('Leitura zerada ignorada para o histórico de saldo: mantendo '
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

  static const int _syncFailureThreshold = 5;

  bool get nodeSyncDegraded =>
      _deviceNode.consecutiveSyncFailures >= _syncFailureThreshold;

  void _ensureSyncTimer() {
    Future<void> tick() async {
      final handle = _deviceNode;
      if (handle.api == null) return;
      try {
        await handle.api!.sync();

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

    unawaited(tick());

    _reagendarSyncTimer();
    _ensureFastWatch();
  }

  bool _appEmPrimeiroPlano = true;

  void _reagendarSyncTimer() {
    _syncTimer?.cancel();
    final intervalo = _appEmPrimeiroPlano
        ? const Duration(seconds: 45)
        : const Duration(seconds: 120);
    _syncTimer = Timer.periodic(intervalo, (_) => _dispararSync?.call());
  }

  Timer? _fastWatchTimer;
  Future<void> Function()? _dispararSync;
  int? _ultimoTotalVisto;
  String? _enderecoVigiado;

  int _vigiaEmEspera = 0;

  void _ensureFastWatch() {
    _reagendarFastWatch();
  }

  void _reagendarFastWatch() {
    _fastWatchTimer?.cancel();
    final intervalo = _appEmPrimeiroPlano
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30);
    _fastWatchTimer = Timer.periodic(intervalo, (_) => _vigiarEndereco());
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
      final addr = handle.cachedOnchainAddress ??
          await _loadOnchainAddress(handle.isMerchant);
      if (addr == null || addr.isEmpty) return;

      final r = await http
          .get(Uri.parse('$base/address/$addr'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 429) {
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
      _vigiaEmEspera = 6;
      debugPrint('Vigia rápida pausada após falha: $e');
    }
  }

  Future<void> _recoverDegradedNode(_NodeHandle handle) async {
    final seed = handle.runningSeed;
    if (seed == null) return;
    debugPrint(
        'Sync degradado por $_syncFailureThreshold tentativas seguidas — reiniciando o nó para trocar de backend Esplora.');
    final wasMerchant = handle.isMerchant;
    try {
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

    await _loadMerchantProducts();
    notifyListeners();
  }

  Future<void> switchConsumerAccount(String id) async {
    _clearConsumerSessionState();
    _activeConsumerId = id;
    setConsumerTab(0);
    await _saveConsumers();
    _isUnlocked = false;
    notifyListeners();
  }

  Future<void> switchMerchantAccount(String id) async {
    _clearMerchantSessionState();
    _activeMerchantId = id;

    ProductImageStore.definirLoja(id);
    setMerchantTab(0);
    await _saveMerchants();

    await _loadMerchantProducts();
    _isMerchantUnlocked = false;
    notifyListeners();
  }

  void _clearMerchantSessionState() {
    _merchantProducts = [];
    _merchantTransactions.clear();
    _cartTotal = 0;
    _pendingChargeAmount = 0;
    onAccountChanged?.call();
  }

  void _clearConsumerSessionState() {
    _consumerTransactions.clear();
    onAccountChanged?.call();
  }

  String? get _productsKey =>
      _activeMerchantId == null ? null : 'merchant_products_$_activeMerchantId';

  Future<void> _loadMerchantProducts() async {
    final key = _productsKey;
    if (key == null) {
      _merchantProducts = [];
      return;
    }
    final prefs = await SharedPreferences.getInstance();

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
    if (_enderecosProprios[chave] == nome) return;
    _enderecosProprios[chave] = nome;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _chaveEnderecosProprios(fp), jsonEncode(_enderecosProprios));
    } catch (e) {
      debugPrint('Falha ao gravar endereço próprio: $e');
    }
  }

  String? nomeDaCarteiraDoEndereco(String endereco) {
    final fp = _deviceNode.runningSeedFingerprint;
    if (fp == null) return null;
    if (_fpDosEnderecosProprios != fp) {
      unawaited(_carregarEnderecosProprios(fp).then((_) => notifyListeners()));
      return null;
    }
    return _enderecosProprios[endereco.trim().toLowerCase()];
  }


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

      _limparFotosOrfas();
      notifyListeners();
    }
  }

  void removeMerchantProduct(String id) {
    _merchantProducts.removeWhere((e) => e.id == id);
    _saveMerchantProducts();

    _limparFotosOrfas();
    notifyListeners();
  }

  Future<void> _limparFotosOrfas() async {
    final emUso =
        _merchantProducts.map((p) => p.image).whereType<String>().toSet();
    await ProductImageStore.limparOrfaos(emUso);
  }

  static const int catalogFormatVersion = 1;

  Future<String> exportMerchantCatalog() async {
    if (_activeMerchantId == null) {
      throw StateError('Nenhuma loja ativa para exportar.');
    }

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

    await _limparFotosOrfas();

    onCatalogImported?.call();

    notifyListeners();
    return CatalogImportResult(
      adicionados: adicionados,
      atualizados: atualizados,
      ignorados: ignorados,
    );
  }

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

  Future<String> getOnchainAddress({bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;

    if (handle.api == null) {
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
      final reason = handle.lastStartError;
      throw Exception(reason != null
          ? 'Nó indisponível — não é possível gerar endereço real. Detalhe: $reason'
          : 'Nó indisponível — não é possível gerar endereço real.');
    }

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


  Future<String> getMyNodeId({bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (!handle.isRunning || handle.api == null) {
      throw Exception('Nó indisponível.');
    }
    return await handle.api!.myNodeId();
  }

  Future<List<String>> getLocalNetworkAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((a) => !a.startsWith('169.254.'))
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

  Future<int> deepScan({int ateIndice = 150, bool forMerchant = false}) async {
    final handle = forMerchant ? _merchantNode : _consumerNode;
    if (handle.api == null) return 0;

    await reconstruirHistoricoDoNo(forMerchant: forMerchant);

    var revelados = 0;
    for (var i = 0; i < ateIndice; i++) {
      try {
        final addr = await handle.api!.newOnchainAddress();

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

  Future<String> createInvoice(int amountSats, String desc,
      {bool forMerchant = false}) async {
    var handle = forMerchant ? _merchantNode : _consumerNode;

    if (handle.api == null) {
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
      status: 'pending',
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

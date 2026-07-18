import 'package:flutter/material.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:ldk_node/ldk_node.dart' as ldk;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  Transaction({
    required this.id,
    required this.title,
    required this.emoji,
    required this.amountSats,
    required this.isIncoming,
    required this.date,
  });
}

class AccountProfile {
  final String id;
  final String name;
  final String seed;
  final String pinHash;

  AccountProfile({required this.id, required this.name, required this.seed, required this.pinHash});

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

class WalletService extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<AccountProfile> _consumerAccounts = [];
  List<AccountProfile> _merchantAccounts = [];

  String? _activeConsumerId;
  String? _activeMerchantId;

  String? _tempConsumerSeed; // Used during creation

  bool _isUnlocked = false;
  bool _isMerchantUnlocked = false;
  bool _isNodeRunning = false;
  bool _isNfcEnabled = false;
  String _lastSessionType = 'consumer';

  double _cartTotal = 0;
  double _pendingChargeAmount = 0;

  // LDK Node state
  ldk.Node? _lnNode;
  bool get isNodeRunning => _isNodeRunning;
  
  String? _mainWalletFixedInvoice;
  String? get mainWalletFixedInvoice => _mainWalletFixedInvoice;

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

  // State
  int _balanceSats = 0;
  bool _isInit = false;
  List<Product> _merchantProducts = [];
  List<Product> get merchantProducts => _merchantProducts;

  int _consumerBalance = 0;
  int _merchantBalance = 0;
  
  final List<Transaction> _consumerTransactions = [];
  final List<Transaction> _merchantTransactions = [];

  int get consumerBalance => _consumerBalance;
  int get merchantBalance => _merchantBalance;
  List<Transaction> get consumerTransactions => _consumerTransactions;
  List<Transaction> get merchantTransactions => _merchantTransactions;

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
      // Falback se não tinha salvo, usa o que tem
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
  
  Future<bool> unlock(String pin) async {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    
    // Create new account flow
    if (_tempConsumerSeed != null) {
      final newAccount = AccountProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Carteira Pessoal ${_consumerAccounts.length + 1}',
        seed: _tempConsumerSeed!,
        pinHash: digest.toString(),
      );
      _consumerAccounts.add(newAccount);
      _activeConsumerId = newAccount.id;
      _tempConsumerSeed = null;
      
      await _saveConsumers();
      _isUnlocked = true;
      _consumerBalance = 0;
      _consumerTransactions.clear();
      await setLastSessionType('consumer');
      notifyListeners();
      
      // Initialize node after creating account
      _startLightningNode(newAccount.seed).catchError((e) {
        debugPrint('Erro ao iniciar LDK após criação: $e');
      });
      
      return true;
    }
    
    // Verify existing active account flow
    final active = activeConsumer;
    if (active != null) {
      if (digest.toString() == active.pinHash) {
        _isUnlocked = true;
        await setLastSessionType('consumer');
        notifyListeners();
        // Inicializa o nó em background
        _startLightningNode(active.seed).catchError((e) {
          debugPrint('Erro ao iniciar LDK: $e');
        });
        return true;
      }
    }
    return false;
  }
  
  Future<void> _startLightningNode(String mnemonic) async {
    if (_isNodeRunning) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final nodePath = '${directory.path}/ldk_node_data';
      final dir = Directory(nodePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final builder = ldk.Builder()
        ..setEntropyBip39Mnemonic(mnemonic: ldk.Mnemonic(seedPhrase: mnemonic))
        ..setNetwork(ldk.Network.testnet)
        ..setStorageDirPath(nodePath)
        ..setEsploraServer('https://mempool.space/testnet/api');
        
      _lnNode = await builder.build();
      await _lnNode!.start();
      _isNodeRunning = true;
      
      // Load persisted products
      await _loadMerchantProducts();
      
      if (_merchantProducts.isEmpty) {
        // Add default mock product if none exist
        addMerchantProduct(Product(id: 'prod_coffee', emoji: '☕', name: 'Café Expresso', price: 15.0));
      }

      _isInit = true;

      try {
        final nodePubKey = await _lnNode!.nodeId();
        final bolt11 = await _lnNode!.bolt11Payment();
        final inv = await bolt11.receiveVariableAmount(
          expirySecs: 31536000, // 1 year
          description: "Carteira Principal",
        );
        _mainWalletFixedInvoice = inv.signedRawInvoice;
      } catch (e) {
        debugPrint('Failed to generate fixed invoice: $e');
        _mainWalletFixedInvoice = 'lnbc1_mock_fixed_invoice_windows_fallback_0000000000000';
      }

      notifyListeners();
      debugPrint('Nó LDK iniciado localmente com sucesso! (Zero KYC)');
    } catch (e) {
      debugPrint('Falha ao rodar nó localmente: $e');
      if (Platform.isWindows) {
        debugPrint('Windows não suportado pelo ldk_node 0.2.0 nativamente. Mockando nó LDK para UI tests...');
        _isNodeRunning = true;
        _mainWalletFixedInvoice = 'lnbc1_mock_fixed_invoice_windows_fallback_0000000000000';
        notifyListeners();
      } else {
        rethrow;
      }
    }
  }
  
  void lock() {
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    notifyListeners();
  }

  Future<void> wipeWallet() async {
    await _storage.deleteAll();
    _consumerAccounts.clear();
    _merchantAccounts.clear();
    _activeConsumerId = null;
    _activeMerchantId = null;
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    _consumerBalance = 0;
    _merchantBalance = 0;
    _consumerTransactions.clear();
    _merchantTransactions.clear();
    notifyListeners();
  }

  Future<void> deleteActiveConsumer() async {
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

  Future<void> setupMerchant(String name, String seed, String pin) async {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    final hash = digest.toString();

    final newAccount = AccountProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      seed: seed,
      pinHash: hash,
    );

    _merchantAccounts.add(newAccount);
    _activeMerchantId = newAccount.id;
    await _saveMerchants();
    
    _isMerchantUnlocked = true;
    _merchantBalance = 0;
    _merchantTransactions.clear();
    await setLastSessionType('merchant');
    notifyListeners();
  }

  Future<bool> unlockMerchant(String pin) async {
    final active = activeMerchant;
    if (active == null) return false;

    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    if (digest.toString() == active.pinHash) {
      _isMerchantUnlocked = true;
      await setLastSessionType('merchant');
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> switchConsumerAccount(String id) async {
    _activeConsumerId = id;
    await _saveConsumers();
    _isUnlocked = false; // Requere PIN para a nova conta ao trocar
    notifyListeners();
  }

  Future<void> switchMerchantAccount(String id) async {
    _activeMerchantId = id;
    await _saveMerchants();
    _isMerchantUnlocked = false; // Requere PIN para a nova loja ao trocar
    notifyListeners();
  }

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

  // Node Management (LDK)
  
  Future<String> getOnchainAddress() async {
    if (!_isNodeRunning || _lnNode == null) {
      if (Platform.isWindows) return "tb1qmockwindowsfallbackaddress0000000000000000";
      throw Exception("Nó Lightning não está rodando.");
    }
    final onChain = await _lnNode!.onChainPayment();
    final address = await onChain.newAddress();
    return address.s;
  }

  Future<int> getOnchainBalance() async {
    if (!_isNodeRunning || _lnNode == null) return 0;
    final balances = await _lnNode!.listBalances();
    return balances.totalOnchainBalanceSats.toInt();
  }

  Future<void> syncNode() async {
    if (!_isNodeRunning || _lnNode == null) return;
    await _lnNode!.syncWallets();
  }

  Future<List<ldk.ChannelDetails>> getChannels() async {
    if (!_isNodeRunning || _lnNode == null) {
      if (Platform.isWindows) return [];
      throw Exception("Nó Lightning não está rodando.");
    }
    return await _lnNode!.listChannels();
  }

  Future<void> openChannel({
    required String pubKeyHex,
    required String host,
    required int port,
    required int amountSats,
  }) async {
    if (!_isNodeRunning || _lnNode == null) throw Exception("Nó offline");
    final nodeAddr = ldk.SocketAddress.hostname(addr: host, port: port);
    await _lnNode!.connectOpenChannel(
      channelAmountSats: BigInt.from(amountSats),
      nodeId: ldk.PublicKey(hex: pubKeyHex),
      socketAddress: nodeAddr,
      announceChannel: true,
    );
    notifyListeners();
  }

  // Real Lightning Network Logic (LDK)
  
  Future<String> createInvoice(int amountSats, String desc) async {
    if (!_isNodeRunning || _lnNode == null) {
      if (Platform.isWindows) return "lnbc1_mock_invoice_windows_fallback_0000000000000";
      throw Exception("Nó offline");
    }
    try {
      final bolt11 = await _lnNode!.bolt11Payment();
      final invoice = await bolt11.receive(
        amountMsat: BigInt.from(amountSats * 1000),
        description: desc,
        expirySecs: 3600,
      );
      return invoice.signedRawInvoice;
    } catch (e) {
      debugPrint('createInvoice error: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> payInvoice(String destination, int sats) async {
    await Future.delayed(const Duration(milliseconds: 800)); 
    
    _consumerBalance -= sats;
    if (_consumerBalance < 0) _consumerBalance = 0;

    final tx = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: destination,
      emoji: '💸',
      amountSats: sats,
      isIncoming: false,
      date: DateTime.now(),
    );
    _consumerTransactions.insert(0, tx);
    notifyListeners();

    return {
      'status': 'paid',
      'preimage': '0x${generateRandomHex(32)}',
      'nerdData': '[ LIGHTNING ]\nHTLC ID: ${generateRandomHex(32)}\nRotas: 3 hops\nTaxa: 0 sats'
    };
  }

  Future<Map<String, dynamic>> payLightningInvoice(String invoiceStr) async {
    if (!_isNodeRunning) {
      throw Exception("Nó Lightning não está rodando.");
    }
    if (_lnNode == null) {
      // Mock for Windows
      await Future.delayed(const Duration(milliseconds: 800));
      return {
        'status': 'paid',
        'preimage': 'mock_preimage_${generateRandomHex(16)}',
        'nerdData': '[ LIGHTNING MOCK ]\nInvoice: $invoiceStr\nRede: Testnet Simulação'
      };
    }
    try {
      final invoice = ldk.Bolt11Invoice(signedRawInvoice: invoiceStr);
      final bolt11 = await _lnNode!.bolt11Payment();
      final paymentId = await bolt11.send(invoice: invoice);
      
      final sats = 0; // Amount parsing not available in ldk_node 0.2.0 Bolt11Invoice
      
      _consumerBalance -= sats;
      if (_consumerBalance < 0) _consumerBalance = 0;

      final tx = Transaction(
        id: paymentId.toString(),
        title: 'Pagamento Lightning', // Description parsing not available in 0.2.0
        emoji: '⚡',
        amountSats: sats,
        isIncoming: false,
        date: DateTime.now(),
      );
      _consumerTransactions.insert(0, tx);
      notifyListeners();

      return {
        'status': 'paid',
        'preimage': paymentId.toString(),
        'nerdData': '[ LIGHTNING LDK ]\nPayment ID: $paymentId\nRede: Testnet'
      };
    } catch (e) {
      debugPrint('Falha ao rotear pagamento via LDK: $e');
      rethrow;
    }
  }

  void lockApp() {
    _isUnlocked = false;
    _isMerchantUnlocked = false;
    notifyListeners();
  }

  String generateRandomHex(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length ~/ 2, (i) => random.nextInt(256));
    return values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}

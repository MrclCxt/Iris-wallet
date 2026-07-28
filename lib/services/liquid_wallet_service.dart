import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lwk/lwk.dart' as lwk;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class LiquidWalletService extends ChangeNotifier {
  static const String _electrumUrl = 'blockstream.info:465';

  static const String lbtcTestnetAssetId =
      '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';

  lwk.Wallet? _wallet;
  String? _mnemonic;
  String? _accountId;
  bool _isRunning = false;
  bool _isMock = false;
  Timer? _syncTimer;

  bool get isRunning => _isRunning;
  bool get isMock => _isMock;

  int _balanceSats = 0;
  int get balanceSats => _balanceSats;

  final StreamController<int> _receivedCtrl = StreamController<int>.broadcast();
  Stream<int> get lbtcReceived => _receivedCtrl.stream;

  String? _receiveAddress;
  String? get receiveAddress => _receiveAddress;

  void resetForAccountSwitch() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _wallet = null;
    _mnemonic = null;
    _accountId = null;
    _receiveAddress = null;
    _balanceSats = 0;
    _isRunning = false;
    _isMock = false;
    notifyListeners();
  }

  Future<void> initLiquidWallet(String mnemonic,
      {String accountId = 'default'}) async {
    if (_isRunning && _accountId == accountId) return;
    if (_isRunning) resetForAccountSwitch();
    try {
      await lwk.LibLwk.init();

      final directory = await getApplicationDocumentsDirectory();
      final dbPath = '${directory.path}/lwk_data_$accountId';
      final dir = Directory(dbPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      const network = lwk.Network.testnet;

      final descriptor = await lwk.Descriptor.newConfidential(
        network: network,
        mnemonic: mnemonic,
      );

      _wallet = await lwk.Wallet.init(
        network: network,
        dbpath: dbPath,
        descriptor: descriptor,
      );
      _mnemonic = mnemonic;
      _accountId = accountId;

      await _wallet!.sync(
        electrumUrl: _electrumUrl,
        validateDomain: true,
      );

      final addr = await _wallet!.addressLastUnused();
      _receiveAddress = addr.confidential;

      await _refreshBalance();

      _isRunning = true;
      _isMock = false;

      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
        final before = _balanceSats;
        await syncWallet();
        if (_balanceSats > before) {
          _receivedCtrl.add(_balanceSats - before);
        }
      });

      notifyListeners();
      debugPrint(
          'Liquid Wallet iniciada (testnet). Saldo: $_balanceSats sats L-BTC');
    } catch (e) {
      debugPrint('Erro ao iniciar Liquid Wallet: $e');
      if (Platform.isWindows) {
        _isRunning = true;
        _isMock = true;
        _receiveAddress = null;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshBalance() async {
    if (_wallet == null) return;
    try {
      final balances = await _wallet!.balances();
      for (final b in balances) {
        if (b.assetId == lbtcTestnetAssetId) {
          _balanceSats = b.value;
        }
      }
    } catch (e) {
      debugPrint('Erro ao ler saldo Liquid: $e');
    }
  }

  Future<void> syncWallet() async {
    if (!_isRunning || _wallet == null) return;
    try {
      await _wallet!.sync(
        electrumUrl: _electrumUrl,
        validateDomain: true,
      );
      await _refreshBalance();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync Liquid error: $e');
    }
  }

  Future<String> getReceiveAddress() async {
    if (!_isRunning || _wallet == null) {
      throw Exception(
          'Carteira Liquid indisponível nesta plataforma (modo demonstração).');
    }
    final addr = await _wallet!.addressLastUnused();
    return addr.confidential;
  }

  Future<String> sendLbtc(
      {required String toAddress, required int sats}) async {
    if (!_isRunning || _wallet == null || _mnemonic == null) {
      throw Exception('Carteira Liquid não está pronta.');
    }
    if (sats <= 0) throw Exception('Valor inválido.');
    if (sats > _balanceSats) throw Exception('Saldo L-BTC insuficiente.');

    final pset = await _wallet!.buildLbtcTx(
      sats: BigInt.from(sats),
      outAddress: toAddress,
      feeRate: 0.1,
      drain: false,
    );

    final signedBytes = await _wallet!.signTx(
      network: lwk.Network.testnet,
      pset: pset,
      mnemonic: _mnemonic!,
    );

    final txid = await lwk.Wallet.broadcastTx(
      electrumUrl: _electrumUrl,
      txBytes: signedBytes,
    );

    await syncWallet();
    debugPrint('L-BTC enviado. txid: $txid');
    return txid;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _receivedCtrl.close();
    super.dispose();
  }
}

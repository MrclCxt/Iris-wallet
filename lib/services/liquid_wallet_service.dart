import 'package:flutter/material.dart';
import 'package:lwk/lwk.dart' as lwk;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

class LiquidWalletService extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  lwk.Wallet? _wallet;
  bool _isRunning = false;
  
  bool get isRunning => _isRunning;
  int _balanceSats = 0;
  int get balanceSats => _balanceSats;
  
  String? _receiveAddress;
  String? get receiveAddress => _receiveAddress;

  Future<void> initLiquidWallet(String mnemonic) async {
    if (_isRunning) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = '${directory.path}/lwk_data';
      final dir = Directory(dbPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final network = lwk.Network.testnet;
      
      final descriptor = await lwk.Descriptor.newConfidential(
        network: network, 
        mnemonic: mnemonic
      );

      _wallet = await lwk.Wallet.init(
        network: network,
        dbpath: dbPath,
        descriptor: descriptor,
      );

      await _wallet!.sync(
        electrumUrl: 'blockstream.info:465',
        validateDomain: false,
      );
      
      final addr = await _wallet!.address(index: 0); 
      _receiveAddress = addr.confidential;

      _isRunning = true;
      notifyListeners();
      debugPrint('Liquid Wallet iniciada com sucesso.');
    } catch (e) {
      debugPrint('Erro ao iniciar Liquid Wallet: $e');
      if (Platform.isWindows) {
        _isRunning = true;
        _receiveAddress = 'tlq1_mock_windows_fallback_address_depix';
        notifyListeners();
      }
    }
  }

  Future<void> syncWallet() async {
    if (!_isRunning || _wallet == null) return;
    try {
      await _wallet!.sync(
        electrumUrl: 'blockstream.info:465',
        validateDomain: false,
      );
      // Pega os balanços, que retorna um Map<AssetId, Balance>
      final balances = await _wallet!.balances();
      // O asset do L-BTC testnet
      final lbtcAseetId = "144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49"; 
      
      // Procurando balance
      // TODO: Adapt to specific LWK API depending on exact typings
    } catch (e) {
      debugPrint('Sync Liquid error: $e');
    }
  }

  Future<String> getReceiveAddress() async {
    if (!_isRunning || _wallet == null) return "tlq1_mock_address";
    try {
      final addr = await _wallet!.address(index: 0); 
      return addr.confidential;
    } catch (e) {
      return "tlq1_mock_fallback";
    }
  }
}

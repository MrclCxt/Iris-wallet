import 'package:flutter/material.dart';
import 'package:lwk/lwk.dart' as lwk;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Integração com a sidechain Liquid (testnet) via LWK.
/// Cumpre o requisito de Sidechain do projeto: recebimento, saldo real
/// e envio de L-BTC com transação construída, assinada e transmitida
/// localmente (não-custodial).
class LiquidWalletService extends ChangeNotifier {
  static const String _electrumUrl = 'blockstream.info:465';

  /// Asset ID do L-BTC na Liquid testnet.
  static const String lbtcTestnetAssetId =
      '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';

  lwk.Wallet? _wallet;
  String? _mnemonic; // mantida em memória apenas para assinar (não-custodial)
  bool _isRunning = false;
  bool _isMock = false;

  bool get isRunning => _isRunning;
  bool get isMock => _isMock;

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
        mnemonic: mnemonic,
      );

      _wallet = await lwk.Wallet.init(
        network: network,
        dbpath: dbPath,
        descriptor: descriptor,
      );
      _mnemonic = mnemonic;

      await _wallet!.sync(
        electrumUrl: _electrumUrl,
        validateDomain: false,
      );

      final addr = await _wallet!.addressLastUnused();
      _receiveAddress = addr.confidential;

      await _refreshBalance();

      _isRunning = true;
      _isMock = false;
      notifyListeners();
      debugPrint('Liquid Wallet iniciada (testnet). Saldo: $_balanceSats sats L-BTC');
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
        validateDomain: false,
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

  /// Envia L-BTC (testnet): constrói o PSET, assina localmente com a
  /// mnemônica e transmite via Electrum. Retorna o txid.
  Future<String> sendLbtc({required String toAddress, required int sats}) async {
    if (!_isRunning || _wallet == null || _mnemonic == null) {
      throw Exception('Carteira Liquid não está pronta.');
    }
    if (sats <= 0) throw Exception('Valor inválido.');
    if (sats > _balanceSats) throw Exception('Saldo L-BTC insuficiente.');

    final pset = await _wallet!.buildLbtcTx(
      sats: BigInt.from(sats),
      outAddress: toAddress,
      feeRate: 0.1, // sats/vbyte típico da Liquid
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
}

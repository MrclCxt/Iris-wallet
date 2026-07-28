import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DaemonInstallService {
  static const String taskName = 'IrisNoded';

  static bool get isSupported => Platform.isWindows;

  static Future<String?> pickBinary() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Selecione o iris-noded.exe',
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );
    return res?.files.single.path;
  }

  static Future<Directory> _dataDir() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory('${docs.path}/daemon');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> _writeSeedFile(String accountId, String seed) async {
    final dir = await _dataDir();
    final file = File('${dir.path}/seed_$accountId.txt');
    await file.writeAsString(seed.trim());
    return file.path;
  }

  static Future<String> install({
    required String exePath,
    required String accountId,
    required String seed,
    int port = 8380,
    String esplora = 'https://mempool.space/testnet4/api',
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Instalação automática só existe no Windows.');
    }
    if (!await File(exePath).exists()) {
      throw Exception('Arquivo não encontrado: $exePath');
    }

    final seedPath = await _writeSeedFile(accountId, seed);
    final dataDir =
        Directory('${(await _dataDir()).path}/node_data_$accountId');
    if (!await dataDir.exists()) await dataDir.create(recursive: true);

    await uninstall();

    final args = '--mnemonic-file "$seedPath" --data-dir "${dataDir.path}" '
        '--port $port --esplora "$esplora"';

    final createResult = await Process.run('schtasks', [
      '/create',
      '/tn',
      taskName,
      '/tr',
      '"$exePath" $args',
      '/sc',
      'onlogon',
      '/rl',
      'limited',
      '/f',
    ]);
    if (createResult.exitCode != 0) {
      throw Exception('Falha ao criar a tarefa: ${createResult.stderr}');
    }

    final runResult = await Process.run('schtasks', ['/run', '/tn', taskName]);
    if (runResult.exitCode != 0) {
      throw Exception(
          'Tarefa criada, mas falhou ao iniciar: ${runResult.stderr}');
    }

    final url = 'http://127.0.0.1:$port';
    await _waitHealthy(url);
    return url;
  }

  static Future<void> _waitHealthy(String url) async {
    const tentativas = 10;
    for (var i = 0; i < tentativas; i++) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final r = await http
            .get(Uri.parse('$url/health'))
            .timeout(const Duration(seconds: 2));
        if (r.statusCode == 200) return;
      } catch (_) {}
    }
    throw Exception(
        'O daemon não respondeu em $url/health a tempo. Confira se a porta '
        'está livre e se o binário é válido.');
  }

  static Future<bool> isInstalled() async {
    if (!isSupported) return false;
    final r = await Process.run('schtasks', ['/query', '/tn', taskName]);
    return r.exitCode == 0;
  }

  static Future<void> uninstall() async {
    if (!isSupported) return;

    await Process.run('schtasks', ['/end', '/tn', taskName]);
    await Process.run('schtasks', ['/delete', '/tn', taskName, '/f']);
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Instala/gerencia o daemon local (`iris-noded`) como tarefa que inicia
/// sozinha no login do Windows — a única forma de o nó sobreviver a fechar o
/// app de verdade em desktop (o nó embarcado morre junto com o processo do
/// app; o daemon roda à parte).
///
/// Não é um "Serviço do Windows" no sentido formal do Service Control
/// Manager (isso exigiria reescrever o binário do daemon para responder ao
/// protocolo de controle do SCM) — é uma Tarefa Agendada do Windows
/// (`schtasks`) disparada no logon do usuário atual, sem precisar de
/// privilégio de administrador. Na prática, cumpre o mesmo objetivo: o nó
/// fica de pé sem precisar abrir o app.
///
/// Linux/macOS ainda não têm instalador automático aqui — o caminho manual
/// (systemd/launchd) continua documentado em `daemon/README.md`.
class DaemonInstallService {
  static const String taskName = 'IrisNoded';

  static bool get isSupported => Platform.isWindows;

  /// Deixa o usuário escolher o binário `iris-noded.exe` (não há instalador
  /// que o traga embutido ainda — precisa ser compilado com `cargo build
  /// --release` na pasta `daemon/`, ou apontar para uma cópia já compilada).
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

  /// Grava a seed num arquivo privado do usuário para o daemon ler. É a
  /// mesma limitação já documentada em `daemon/README.md`: o daemon roda como
  /// processo separado do app e não tem acesso à seed cifrada do Dart, então
  /// precisa da semente em texto puro em disco, protegida só pelas
  /// permissões do sistema de arquivos — por isso isto é opt-in e avisado na
  /// UI antes de instalar.
  static Future<String> _writeSeedFile(String accountId, String seed) async {
    final dir = await _dataDir();
    final file = File('${dir.path}/seed_$accountId.txt');
    await file.writeAsString(seed.trim());
    return file.path;
  }

  /// Instala e já inicia a tarefa. Devolve a URL do daemon
  /// (`http://127.0.0.1:<port>`) quando ele responde `/health` com sucesso.
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

    // Remove uma instalação anterior antes de recriar — schtasks /create
    // falha se a tarefa já existir, e trocar de conta/porta precisa refazer.
    await uninstall();

    final args = '--mnemonic-file "$seedPath" --data-dir "${dataDir.path}" '
        '--port $port --esplora "$esplora"';
    // /sc onlogon: dispara ao logar o usuário atual, sem precisar de admin.
    // /rl limited: nível de privilégio normal do usuário (não eleva).
    // /it (não usado): rodaria interativo — de propósito NÃO usamos, pois o
    // daemon deve rodar em segundo plano sem janela visível.
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

    // Roda agora — sem isto o usuário só veria efeito no próximo login.
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
      } catch (_) {
        // ainda subindo — tenta de novo
      }
    }
    throw Exception(
        'O daemon não respondeu em $url/health a tempo. Confira se a porta '
        'está livre e se o binário é válido.');
  }

  /// True se a tarefa existe (instalada), independentemente de estar rodando
  /// agora.
  static Future<bool> isInstalled() async {
    if (!isSupported) return false;
    final r = await Process.run('schtasks', ['/query', '/tn', taskName]);
    return r.exitCode == 0;
  }

  static Future<void> uninstall() async {
    if (!isSupported) return;
    // Ignora erro se a tarefa não existir — não há o que remover.
    await Process.run('schtasks', ['/end', '/tn', taskName]);
    await Process.run('schtasks', ['/delete', '/tn', taskName, '/f']);
  }
}

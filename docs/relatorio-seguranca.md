# Relatório de segurança — out/2026

Testes feitos dentro do projeto antes de qualquer auditoria externa. Não
substitui auditoria: antes da rede principal, uma empresa independente deve
repetir isto com acesso a iOS, Frida e interceptação de rede.

Rede de todos os testes: testnet4 e regtest. Aparelho: Galaxy S24 Ultra
(Android 16, arm64). Código: branch `dev`.

---

## 1. Entropia da semente

**Achado (corrigido):** o pacote `bip39` 1.0.6 gera a semente com
`Random.secure().nextInt(255)` — o byte `0xFF` nunca aparece. Cada byte da
semente tem 255 valores em vez de 256: a semente de 12 palavras perde ~0,09
bit e, pior, o gerador é previsível por construção. É o mesmo tipo de defeito
das carteiras quebradas na vida real (Milk Sad/Libbitcoin `bx` com semente
de 32 bits; Trust Wallet com MT19937; Randstorm com `Math.random`).

**Correção:** [lib/core/entropia.dart](../lib/core/entropia.dart).
- Bytes do sistema por `Random.secure().nextInt(256)` (CSPRNG do sistema
  operacional, sem viés).
- Opcional: o usuário mistura lançamentos de dado (1–6) ou moeda (C/K). Tudo
  passa por SHA-256 com rótulo de domínio. Dados fracos do usuário **nunca
  enfraquecem** a semente: sem eles, vale só o sistema; com eles, um atacante
  precisa adivinhar os dois.
- A tela mostra quantos bits os dados acrescentaram (dado ≈ 2,585 bits,
  moeda = 1 bit).

**Prova** ([test/entropia_test.dart](../test/entropia_test.dart)):
- 3.000 sementes do `bip39` antigo: nenhuma tem o byte `0xFF` (o defeito
  existe e é reproduzível).
- 10.000 sementes novas: nenhuma repetida, os 256 valores de byte aparecem,
  qui-quadrado abaixo do limite de 99,9% (330,5 para 255 graus de liberdade).
- 24 palavras, vetores oficiais da Trezor, mistura de dados/moeda
  determinística e sensível a qualquer mudança.

## 2. Análise estática do código (SAST)

Buscas no código Dart, Rust e Kotlin:

| Verificação | Resultado |
|---|---|
| Semente/PIN/WIF em `print`/`debugPrint`/log | Nada. Logs só mostram a impressão digital (16 hex do SHA-256 da semente) usada no nome da pasta do nó |
| Endpoint `http://` sem TLS | Só `127.0.0.1`/`localhost` (daemon local) |
| Chaves, tokens, API keys no código | Nenhuma |
| `Random()` não seguro em código de chave | Nenhum (só `Random.secure()`) |
| WebView | Não existe no app |
| Deep links / intent filters além do launcher | Não existem |

## 3. Dependências (SCA)

Consulta ao banco OSV (api.osv.dev) com os 772 pacotes únicos de
`pubspec.lock` e dos três `Cargo.lock` (daemon, ldk_node, lwk).

- **Antes:** 70 avisos (incluindo HIGH em `rustls-webpki`, `ring`, `idna`,
  `quinn-proto`).
- **Depois de atualizar os lockfiles:** 15 avisos, nenhum HIGH. Dart: 0.

Restantes:

| Pacote | Aviso | Por que ficou |
|---|---|---|
| `webpki-roots 0.25.4` | RUSTSEC-2026-0381 (raízes emSign desconfiadas) | Dependência transitiva antiga do cliente Esplora/Electrum; a 1.0.11 também está no grafo. Acompanhar o ldk-node/lwk |
| `tokio 1.46.1` (lwk) | RUSTSEC-2026-0386 (`AsyncFd::new`) | Preso pela versão exigida pelo lwk; o app não usa `AsyncFd` diretamente. Liquid não entra no saldo |
| `atty 0.2.14` (lwk) | leitura desalinhada, só no Windows | Ferramenta de build, não roda no app |
| `adler`, `derivative`, `fxhash`, `paste`, `serde_cbor`, `yaml-rust`, `rustls-pemfile`, ... | "sem manutenção" | Informativo, sem falha conhecida |

## 4. Daemon `iris-noded`

**Achados (corrigidos):**
1. API REST sem autenticação em `127.0.0.1:8380`. Qualquer página aberta no
   navegador do PC poderia mandar o nó pagar (CSRF) ou chegar à porta por
   DNS rebinding.
2. Semente lida de arquivo em texto puro.

**Correção** ([daemon/src/main.rs](../daemon/src/main.rs)):
- Token aleatório de 32 bytes no cabeçalho `X-Iris-Token`, guardado em
  arquivo do usuário (permissão 0600 no Linux), comparado em tempo constante.
- Pedido com `Origin` (vem de navegador) → 403; `Host` diferente de
  `127.0.0.1:porta`/`localhost:porta` → 403 (DNS rebinding); POST sem
  `application/json` → 415 (formulário HTML não passa).
- Semente cifrada no mesmo formato do app (AES-256-GCM, PBKDF2-SHA256 200
  mil iterações). Semente em claro é recusada, salvo com
  `--aceitar-semente-em-claro`.

**Prova:** `cargo test` (abre um arquivo cifrado pelo app, recusa senha
errada) e a regtest ([scripts/regtest_canal.py](../scripts/regtest_canal.py))
ataca a API a cada execução: sem token → 401, token errado → 401, `Origin`
→ 403, formulário → 415, `Host` forjado → 403, JSON inválido → 400.

## 5. PIN e força bruta

**Achado (corrigido):** o hash do PIN usava PBKDF2 com 20 mil iterações,
guardado junto da semente cifrada com 200 mil. Quebrar o PIN pelo hash era
10x mais barato e o PIN abre a semente.

Medido neste PC (um núcleo):

| Iterações | Por PIN | 1 milhão de PINs (6 dígitos) |
|---|---|---|
| 20.000 | 2,7 ms | ~45 min/núcleo · ~3 min em 16 núcleos |
| 200.000 | 25,9 ms | ~7,2 h/núcleo · ~27 min em 16 núcleos |

**Correção:** 200 mil iterações, cálculo fora da thread da tela, hash antigo
refeito no próximo PIN certo, PIN de 6 dígitos sem sequências óbvias, e o
bloqueio por tentativas que já existia.

**Conclusão honesta:** nenhum KDF protege um PIN de 6 dígitos se o arquivo
vazar. A defesa real é o dado não sair do aparelho — por isso o item 6.

## 6. Android (OWASP MASVS)

| MASVS | Antes | Agora |
|---|---|---|
| STORAGE — backup | `allowBackup` padrão (ligado): `adb backup`/nuvem copiavam o cofre | `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` exclui tudo da nuvem e da troca de aparelho. Conferido no aparelho: o pacote não tem mais a flag `ALLOW_BACKUP` |
| STORAGE — tela | Semente aparecia em print e na miniatura de apps recentes | `FLAG_SECURE` nas telas da semente (gerar, confirmar, mostrar) |
| NETWORK | Cleartext permitido | `usesCleartextTraffic=false`; `network_security_config` só libera `127.0.0.1`/`localhost` |
| PLATFORM — componentes | — | Só a activity do launcher é exportada; nenhum intent filter extra, nenhum provider exportado |
| PLATFORM — permissões | O leitor de QR trazia `RECORD_AUDIO` | Removida do manifesto final (conferido com `aapt`) |
| PRIVACY | O ML Kit trazia o `datatransport` do Google (envio de métricas) | Serviços e receivers removidos do manifesto final (conferido com `aapt`) |
| RESILIENCE — root | — | Aviso ao gerar a semente em aparelho com sinais de root (`su`, Magisk, `test-keys`). Aviso, não bloqueio: o dono do aparelho decide |
| CODE — release | — | `minifyEnabled` e `shrinkResources` no release; release não é `debuggable` |

### Binário (engenharia reversa estática)

APK descompactado; busca em `classes.dex`, `kernel_blob.bin` (Dart),
`libldk_node.so`, `liblwk.so` e `libflutter.so` por chave PEM, `xprv/tprv`,
WIF, chaves AWS/Google e `api_key`. **Nada encontrado** — os poucos "WIF"
eram trechos de texto sem checksum válido. As URLs `http://` no binário são
comentários de bibliotecas (RFCs, Wikipedia) e o daemon local.

### Armazenamento local no aparelho

Pendente: o aparelho perdeu a autorização de depuração USB no meio do teste.
O roteiro, para repetir: `run-as app.iriswallet` → copiar `shared_prefs` e
`app_flutter` → procurar 12+ palavras seguidas da lista BIP39, WIF e hex de
64 caracteres. Pelo código, a semente vai cifrada (`enc1$`) para o
FlutterSecureStorage (Keystore) e o histórico é cifrado por conta.

## 7. O que não deu para testar aqui

| Teste pedido | Situação |
|---|---|
| iOS (MASVS, binário, Keychain) | Sem Mac neste ambiente. Precisa de auditoria externa |
| Instrumentação dinâmica (Frida) | Não instalado/autorizado neste ambiente |
| Interceptação de tráfego (mitmproxy) | Não feito. Com cleartext desligado e sem pinning, um proxy só intercepta com CA instalada pelo dono do aparelho; o conteúdo trafegado é público (blockchain, cotação) |
| DAST, IAST, pentest web | Não se aplica: a Iris não tem servidor web nem backend próprio. A única API é o daemon local, testado no item 4 |
| WebView, intents implícitos | Não se aplica: não há WebView nem intent filter além do launcher |
| Força bruta do PIN | Medida (item 5) |

## 8. Riscos aceitos

- **Impressão digital da semente no nome da pasta do nó**: 64 bits do
  SHA-256 da semente, sem sal. Com semente de 128 bits do CSPRNG isso não
  ajuda um atacante; só seria problema com um gerador fraco (o item 1 fecha
  essa porta).
- **Quem tem o aparelho desbloqueado e com root** lê a memória do app. Fora
  do alcance de uma carteira em software.
- **Relays Nostr** veem quem conversa com quem nas trocas P2P (não o
  conteúdo, cifrado com NIP-44).

## 9. IAST/DAST do daemon (fuzzing da API)

Fuzzer próprio (`scratchpad/dast_daemon.py`) contra o `iris-noded` compilado
em **debug** (com checagem de estouro), atacando a API por fora e vigiando o
processo a cada caso: ~700 casos — sem token, métodos e rotas inexistentes,
tentativas de burlar token/Host/Origin, corpos gigantes/UTF-8 inválido/JSON
aninhado, valores extremos em todos os campos, e slowloris. A autenticação
recusou tudo (401/403/415/400) e o serviço continuou de pé e atendendo. (Os
"pânicos" vistos no fuzzer foram do daemon **debug** com overflow-checks em
inteiros fora de faixa num campo que o app nunca manda; o release não aborta,
e o pedido já cairia no 500. Vale endurecer a validação desses campos.)

## 10. Incidente de recuperação de PIN e a correção

**O que foi feito** (a pedido do dono, para reaver 6 carteiras cujo PIN ele
esqueceu e sem ter a semente): como o aparelho tinha o build **debug
(depurável)**, deu para instalar por cima uma tela que, rodando dentro do
app (com acesso ao Keystore), exportou os blobs `encSeed`/`pinHash` já fora
da camada do Keystore. Com o blob em mãos, um PC de 16 núcleos testou os
1.000.000 de PINs de 6 dígitos contra cada carteira — a primeira caiu em ~41
min, as demais em minutos. **Recuperou os 6 PINs e as 6 sementes.**

**Causa raiz, honesta:**
1. O build instalado era **depurável** (`run-as`, VM service, reinstalável por
   cima). Num **release** (`debuggable=false`) nada disso é possível.
2. A cifra da semente dependia **só do PIN** (`enc1`): com o blob vazado, 6
   dígitos caem rápido fora do aparelho.

**Correção (implementada):**
- **Cifra vinculada ao hardware** (`enc2`/`v3`): a chave da semente passa a
  depender do PIN **mais um HMAC calculado por uma chave não-exportável do
  Android Keystore/StrongBox** ([Dispositivo.pepper], [SeedCrypto],
  `MainActivity.kt`). Sem o aparelho não dá para derivar a chave — a força
  bruta offline dos 6 dígitos fica **impossível**, mesmo que o blob vaze.
  Migração `enc1→enc2` e `v2→v3` no primeiro desbloqueio. No desktop (sem
  Keystore) mantém-se o modo só-PIN. Provado em `test/seed_crypto_pepper_test.dart`.
- **Nunca distribuir build depurável.** O release tem `debuggable=false`; as
  chaves do Keystore são atreladas à assinatura do app, então **repackaging
  quebra o acesso aos segredos**.
- **Engenharia reversa:** release com `--obfuscate --split-debug-info` (Dart)
  e R8/minify (Java/Kotlin) — os símbolos e strings legíveis no `kernel_blob`
  do debug somem no release.
- **Recuperação de PIN legítima:** a tela "Esqueci meu PIN" agora pede as
  12/24 palavras da semente e define um PIN novo (único caminho possível, já
  que o PIN nunca é guardado de forma reversível). A tela de despejo usada no
  incidente foi removida.

**Lição de produto:** as carteiras criadas nos testes tiveram as sementes
expostas neste processo e devem ser descartadas; e o app precisa deixar
gritante, na criação, que sem as 12 palavras ninguém recupera o acesso.

## Próximos passos

1. Repetir o item 6 (armazenamento) no aparelho quando a depuração USB for
   autorizada.
2. Endurecer a validação de faixa dos campos numéricos do daemon (item 9).
3. Auditoria externa (incluindo iOS e Frida) antes da rede principal.
4. Rodar o SCA a cada atualização de dependência
   (`python sca_osv.py`, consulta ao OSV).

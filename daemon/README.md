# iris-noded — daemon local do nó Lightning

Modo **daemon** da arquitetura híbrida do Iris Wallet (opção B). O nó LDK roda
como processo/serviço no próprio dispositivo e o app conecta via REST em
`127.0.0.1` — nada é exposto à rede e as chaves nunca saem da máquina.

Quando usar em vez do modo embarcado (padrão):

- PDV/desktop que fica ligado o dia todo (o nó sobrevive a fechamentos da UI);
- rodar o nó como serviço do sistema (systemd/Serviço do Windows/launchd);
- múltiplas interfaces controlando o mesmo nó local.

## Compilar

Requer [Rust](https://rustup.rs) instalado (Windows, Linux ou macOS):

```sh
cd daemon
cargo build --release
# binário em target/release/iris-noded(.exe)
```

## Rodar (testnet)

A semente nunca fica em texto puro. Cifre uma vez (mesmo formato e mesma
criptografia do app: PBKDF2-SHA256 + AES-256-GCM) e apague o arquivo claro:

```sh
./iris-noded --cifrar seed.txt --saida semente.enc   # pede a senha duas vezes
rm seed.txt                                          # no Windows: apague e esvazie a lixeira
./iris-noded --mnemonic-file semente.enc --port 8380 # pede a senha (ou IRIS_SENHA)
```

Um arquivo de semente em texto puro é recusado (só com
`--aceitar-semente-em-claro`, para testes).

Usa o mesmo ldk-node 0.7 e os mesmos remendos do app (cópias em
`packages/ldk_node/rust/vendor`), com testnet4 nativa. Os dados ficam em
`./iris_node_data_tn4n` — uma pasta de daemon antigo (0.3, testnet3) não é
reaproveitada.

### Rede

Testnet4 por padrão. `--rede bitcoin` roda na rede principal, com pasta de
dados própria (`./iris_node_data_main`) e Esploras da rede principal. O app só
aceita um daemon da mesma rede para a qual foi compilado.

### Nó Bitcoin próprio (privacidade)

Com `--bitcoind-rpc usuario:senha@host:porta` o daemon lê a blockchain do seu
próprio bitcoind e não consulta servidor de terceiro nenhum — os endereços da
carteira não saem da sua máquina. Vale em qualquer rede.

### Regtest e testes automáticos

`--rede regtest` roda numa blockchain local de teste (exige `--bitcoind-rpc`).
O teste de ponta a ponta sobe um bitcoind e dois daemons, abre canal, paga,
fecha e confere os saldos, sem celular e sem internet:

```sh
cargo build --release
python ../scripts/regtest_canal.py --bitcoin-bin <pasta do bitcoind>
```

O mesmo teste roda no GitHub Actions a cada push na `dev`
(`.github/workflows/testes.yml`).

### Servidores Esplora

Por padrão o daemon testa, em ordem, mempool.space, Blockstream e o espelho
va1 da mempool, e começa pelo primeiro que responder **e estiver na testnet4**
(o bloco gênese é conferido). Para usar o seu servidor, repita `--esplora`:

```sh
./iris-noded --mnemonic-file semente.enc --esplora https://meu-servidor/api
```

### Rotas

`GET /health` (informa a rede), `/node_id`, `/balances`, `/payments`,
`/channels`, `/onchain_address`, `/event` · `POST /invoice`, `/offer`, `/pay`,
`/send_onchain` (recusa endereço de outra rede), `/open_channel`,
`/set_forwarding_fee`, `/close_channel`, `/sync`, `/full_scan`, `/event_handled`.

## Conectar o app

No Iris Wallet: **Gerenciar Nó → ícone de servidor → URL do daemon** e informe
`http://127.0.0.1:8380`. Deixe vazio para voltar ao nó embarcado. O app usa o
daemon na próxima vez que o perfil for desbloqueado.

## Segurança

- **API autenticada.** A cada partida o daemon gera um token aleatório e o
  grava só para o usuário (`%APPDATA%/iris-noded/api_token` no Windows,
  `~/.config/iris-noded/api_token` no Linux/macOS, ou `--token-file`). O app
  lê esse arquivo e manda `X-Iris-Token` em cada pedido. Sem o token: 401.
- **Contra site malicioso no navegador:** pedido com `Origin` (vindo de
  página web) é recusado (403); `Host` diferente de `127.0.0.1:porta` também
  (403, fecha DNS rebinding); POST que não seja `application/json` é
  recusado (415), fechando o CSRF por "POST simples"; JSON inválido dá 400.

- O bind é **exclusivamente** em `127.0.0.1` — o daemon nunca escuta em
  interfaces de rede.
- A semente fica cifrada; a senha não é gravada em lugar nenhum.
- Testnet4. O app recusa um daemon que não informe a mesma rede no `/health`.

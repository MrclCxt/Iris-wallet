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

```sh
echo "suas doze palavras da seed aqui" > seed.txt
./iris-noded --mnemonic-file seed.txt --port 8380
```

Usa o mesmo ldk-node 0.7 e os mesmos remendos do app (cópias em
`packages/ldk_node/rust/vendor`), com testnet4 nativa. Os dados ficam em
`./iris_node_data_tn4n` — uma pasta de daemon antigo (0.3, testnet3) não é
reaproveitada.

### Rede

Testnet4 por padrão. `--rede bitcoin` roda na rede principal, com pasta de
dados própria (`./iris_node_data_main`) e Esploras da rede principal. O app só
aceita um daemon da mesma rede para a qual foi compilado.

### Servidores Esplora

Por padrão o daemon testa, em ordem, mempool.space, Blockstream e o espelho
va1 da mempool, e começa pelo primeiro que responder **e estiver na testnet4**
(o bloco gênese é conferido). Para usar o seu servidor, repita `--esplora`:

```sh
./iris-noded --mnemonic-file seed.txt --esplora https://meu-servidor/api
```

### Rotas

`GET /health` (informa a rede), `/node_id`, `/balances`, `/payments`,
`/channels`, `/onchain_address`, `/event` · `POST /invoice`, `/offer`, `/pay`,
`/send_onchain` (recusa endereço de outra rede), `/open_channel`,
`/set_forwarding_fee`, `/sync`, `/full_scan`, `/event_handled`.

## Conectar o app

No Iris Wallet: **Gerenciar Nó → ícone de servidor → URL do daemon** e informe
`http://127.0.0.1:8380`. Deixe vazio para voltar ao nó embarcado. O app usa o
daemon na próxima vez que o perfil for desbloqueado.

## Segurança

- O bind é **exclusivamente** em `127.0.0.1` — o daemon nunca escuta em
  interfaces de rede.
- A seed fica no arquivo indicado por `--mnemonic-file`; proteja-o com as
  permissões do sistema (ex.: `chmod 600 seed.txt`).
- Testnet4. O app recusa um daemon que não informe a mesma rede no `/health`.

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
./iris-noded --mnemonic-file seed.txt --data-dir ./iris_node_data --port 8380
```

## Conectar o app

No Iris Wallet: **Gerenciar Nó → ícone de servidor → URL do daemon** e informe
`http://127.0.0.1:8380`. Deixe vazio para voltar ao nó embarcado. O app usa o
daemon na próxima vez que o perfil for desbloqueado.

## Segurança

- O bind é **exclusivamente** em `127.0.0.1` — o daemon nunca escuta em
  interfaces de rede.
- A seed fica no arquivo indicado por `--mnemonic-file`; proteja-o com as
  permissões do sistema (ex.: `chmod 600 seed.txt`).
- Testnet por padrão; ajuste `--esplora` se quiser outro provedor de dados.

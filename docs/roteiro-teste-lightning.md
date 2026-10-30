# Roteiro de teste — canal e pagamento Lightning na testnet4 (Fase 0.4)

Objetivo: provar que o Iris **abre canal, recebe, paga e fecha** depois do
porte para o ldk-node 0.7. Nada novo entra no app antes disto passar.

O teste principal não depende de ninguém: o celular abre canal com o nó do
PC, na sua rede local. Um nó público fica como teste extra.

---

## 0. Preparação

1. Gerar os dois builds a partir do mesmo commit:
   - Windows: `flutter build windows --release` — se o log tiver `SEVERE`,
     o Rust não compilou e o build não vale.
   - Android: `flutter build apk --release` e procurar `SEVERE` no log.
2. Instalar nos dois aparelhos. Usar a mesma rede Wi-Fi.
3. No Windows, liberar a porta **9735** no firewall quando o aviso aparecer
   (é a porta Lightning do nó pessoal; a da loja é 9736).
4. Moedas de teste: [faucet testnet4 da mempool](https://mempool.space/testnet4/faucet).
   Mandar ~100.000 sats para o endereço on-chain do **Android**
   (Gerenciar Nó → endereço Testnet4). Esperar 1 confirmação.

## 1. Canal celular → PC (sem terceiros)

1. No PC: Gerenciar Nó → copiar o **ID do nó**. Descobrir o IP local do PC
   (`ipconfig`, ex.: `192.168.0.10`).
2. No Android: Gerenciar Nó → abrir canal:
   - Node PubKey: o ID do PC
   - Host: o IP do PC · Porta: `9735`
   - Capacidade: `50000`
3. Esperar 3 confirmações (~30 min). O canal deve aparecer como utilizável
   nos **dois** aparelhos.

✅ Passou se: o canal aparece nos dois lados com capacidade 50.000.

## 2. Pagar do celular para o PC

1. No PC: Receber → gerar cobrança Lightning de **1.000 sats**.
2. No Android: Enviar → ler o QR → pagar.

✅ Passou se: o Android mostra pagamento concluído, o PC mostra o recebimento
**uma vez só** (sem linha duplicada) e os saldos batem nos dois.

## 3. Pagar do PC para o celular

O canal só tem saldo do lado do celular; depois do passo 2, o PC tem 1.000 sats.

1. No Android: gerar cobrança de **500 sats**.
2. No PC: pagar.

✅ Passou se: concluído nos dois sentidos.

## 4. Fechar o canal

1. Fechar de forma cooperativa (não forçada).
2. Esperar a confirmação.

✅ Passou se: o saldo do canal volta para o on-chain dos dois, menos a taxa.

## 5. Daemon (PDV sempre ligado)

1. Fechar o app no PC. Rodar:
   `iris-noded --mnemonic-file semente.enc` (mesma semente da conta do PC,
   cifrada antes com `iris-noded --cifrar seed.txt --saida semente.enc`).
   O terminal mostra `aceitando canais em <id>@<ip>:9735`.
2. No app do PC: Backend do nó → URL do daemon `http://127.0.0.1:8380` →
   bloquear e desbloquear.
3. Repetir os passos 1 e 2 tendo o daemon como o lado PC.

✅ Passou se: o mesmo resultado, e o histórico aparece pelo daemon.

## 6. Extra — nó público

Procurar um nó em [mempool.space/testnet4/lightning](https://mempool.space/testnet4/lightning),
abrir canal de 20.000–50.000 sats e pagar uma fatura gerada por **outra
carteira** testnet4. Isso testa rota pelo grafo público.

---

## Se falhar

| Sintoma | Suspeito |
|---|---|
| Canal não abre, erro de rede/chain | ChainHash anunciado: confirmar no log `on network: testnet4` |
| Pagamento falha logo de cara | Conversão `Currency::BitcoinTestnet → Network` no `lightning-invoice` vendorizado |
| Pagamento fica pendente para sempre | Rota: no passo 6, canal sem liquidez do lado certo |
| Comportamento antigo depois de mexer no Rust | `.so`/`.dll` antiga empacotada — procurar `SEVERE` no log do build |

Mandar para análise: o log do nó (`ldk_node.log` dentro da pasta `ldk_tn4n_*`)
dos dois aparelhos e o print da tela do erro.

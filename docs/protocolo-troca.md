# Protocolo de troca da Iris (P2P e Pagar conta)

A Iris é a plataforma onde usuários trocam bitcoin por Real entre si — comprar,
vender e pagar contas. **A Iris nunca segura o dinheiro de ninguém**: os sats
saem da carteira de uma pessoa e entram direto na da outra, travados por uma
garantia que nenhum dos lados (nem a Iris) consegue desviar.

Inspiração técnica: Mostro (ordens e disputa sobre Nostr) e Bro (pagar contas
P2P). Nenhum código, ordem ou servidor deles é usado.

## Um primitivo para tudo: a troca com garantia

Toda troca tem dois papéis:

| Papel | Tem | Quer |
|---|---|---|
| **Vendedor de sats** (V) | sats na carteira Iris | Real (Pix, boleto pago, TED) |
| **Comprador de sats** (C) | Real | sats |

- *Vender bitcoin*: o usuário é V; outro usuário Iris é C.
- *Comprar bitcoin*: o usuário é C.
- *Pagar conta*: o usuário é V; C é um usuário Iris que paga o boleto/Pix dele
  e recebe os sats.

## A garantia (hold invoice)

1. **V** gera um segredo `s` (32 bytes aleatórios) e calcula `h = sha256(s)`.
2. V manda `h` para C. Se a troca tiver árbitro, V também manda `s` cifrado
   para a chave do árbitro (NIP-44).
3. **C** cria uma fatura Lightning *para o hash `h`* (`receive_for_hash`). O nó
   de C não consegue receber sem `s`.
4. V paga a fatura. Os sats ficam **travados no caminho**: C ainda não recebeu,
   V não consegue pegar de volta antes do prazo.
5. C paga o Real (Pix/boleto) e manda o comprovante.
6. V confere no banco e **revela `s`** para C. O nó de C resgata
   (`claim_for_hash`) e os sats entram na carteira de C.

Desfechos:

| Situação | O que acontece |
|---|---|
| Tudo certo | V revela `s`; C recebe os sats |
| C desiste ou não paga o Real | C recusa (`fail_for_hash`) ou o prazo vence: **os sats voltam para V** |
| C pagou e V some ou se recusa a revelar | Disputa: o árbitro, com as provas, revela `s` para C |

Propriedades:

- **Sem custódia**: em nenhum momento os sats estão com a Iris ou com o árbitro.
- **O árbitro não consegue roubar**: `s` só serve para C resgatar a própria
  fatura — os sats só podem ir para C. O máximo que um árbitro desonesto faz é
  favorecer C numa disputa, o mesmo risco de qualquer escrow com árbitro.
- **Prazo limitado pelo Lightning**: a trava dura até o `claim_deadline` do
  HTLC (horas, não semanas). A troca tem de fechar dentro dele; a interface
  mostra o tempo restante.

Provado de ponta a ponta em `scripts/regtest_canal.py` (travado até o segredo,
segredo errado recusado, resgate com o certo, troca desfeita devolvendo a V).

## Mensagens (Nostr)

Identidade: a chave Nostr derivada da semente (NIP-06, `lib/nostr/chaves.dart`).
Mensagens entre as partes são cifradas com NIP-44 e trocadas por vários relays.

| Kind | Quem publica | Conteúdo |
|---|---|---|
| `38383` (NIP-69, `y=iris`) | quem anuncia | oferta pública: tipo, moeda, faixa em Real, métodos, prêmio |
| `14` cifrado (NIP-44) | as partes | passos da troca abaixo |

Passos (conteúdo JSON cifrado, campo `acao`):

1. `aceitar` — C → V: aceita a oferta, informa o valor.
2. `hash` — V → C: `h` e o valor em sats.
3. `fatura` — C → V: a fatura para `h`.
4. `travado` — V → C: confirma que pagou (C vê o `PaymentClaimable`).
5. `pago` — C → V: comprovante do Real (texto/imagem).
6. `segredo` — V → C: `s`. Fim.
7. `cancelar` / `disputa` — qualquer lado.

## O que a Iris nunca faz

- Guardar chave ou sats de usuário.
- Comprar ou vender bitcoin com caixa próprio.
- Mandar o usuário para outra plataforma.
- Exigir cadastro ou documento.

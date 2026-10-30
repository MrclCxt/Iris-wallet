# Levantamento regulatório da Iris (para levar a um advogado)

> **Isto não é parecer jurídico.** É um mapa das normas que tocam a Iris, de
> como a arquitetura dela se encaixa nelas e das perguntas que um advogado
> especializado em ativos virtuais precisa responder antes de abrir trocas em
> Real e vouchers na rede principal. Levantado em 30/out/2026 a partir de
> fontes públicas listadas no fim; confira o texto oficial das normas.

## 1. O que a Iris é, em fatos técnicos

| Fato | Onde está no código |
|---|---|
| Carteira não-custodial: a chave fica só no aparelho do usuário, cifrada com o PIN | `lib/core/seed_crypto.dart` |
| Sem conta, cadastro, servidor ou banco de dados da Iris | arquitetura inteira |
| Trocas P2P entre usuários Iris: a Iris não compra, não vende e não cobra taxa | `lib/troca/`, `docs/protocolo-troca.md` |
| Garantia por hold invoice: os sats vão direto de uma carteira à outra; ninguém no meio consegue desviá-los | `docs/protocolo-troca.md` |
| Árbitro opcional, escolhido por quem anuncia: só consegue liberar os sats para o comprador | `lib/troca/troca_service.dart` |
| Vouchers: o lojista emite uma chave financiada pela carteira dele e vende no balcão | `lib/services/voucher_service.dart` |
| Ofertas e mensagens trafegam por relays Nostr públicos, cifradas | `lib/nostr/` |

## 2. Normas que tocam a Iris

**Lei 14.478/2022 (marco legal dos criptoativos).** Prestadora de serviços de
ativos virtuais (PSAV) é a pessoa jurídica que executa, *em nome de terceiros*,
troca entre ativo virtual e moeda nacional, troca entre ativos virtuais,
transferência, custódia/administração ou participação em serviços financeiros
ligados à oferta de ativos. Precisa de autorização prévia do regulador (o BCB,
pelo Decreto 11.563/2023).

**Resoluções BCB 519, 520 e 521, de 10/11/2025.** Autorização (519),
funcionamento e supervisão (520) das sociedades prestadoras (SPSAV), e
integração com o mercado de câmbio (521). Vigência apontada para 02/02/2026;
prazo de adequação de 270 dias (fontes divergem sobre datas — **30/10/2026**
aparece como prazo de protocolo para quem já atuava). Capital mínimo variando
conforme a atividade.

- **Autocustódia:** a proibição de autocustódia de stablecoins, que estava na
  consulta pública, caiu. Mas as PSAVs passam a ter de identificar o titular da
  carteira autocustodiada para onde enviam recursos.
- **P2P:** há leitura (AMDJUS) de que o art. 76-A da Resolução 521 trata a
  transferência para carteira autocustodiada como operação de câmbio, o que
  criaria risco para P2P feito sem autorização. Leitura de uma fonte só —
  conferir no texto oficial.

**Lei 9.613/1998 (lavagem de dinheiro) e COAF.** PSAVs são equiparadas a
instituições financeiras para fins penais e de prevenção à lavagem.

**Receita Federal — IN 1888/2019 (e sucessoras).** Pessoa física que opera
fora de exchange brasileira (P2P incluído) declara à Receita acima de um
limite mensal (historicamente R$ 30 mil). Ganho de capital tributado acima de
R$ 35 mil vendidos no mês. Isso pesa sobre o **usuário**, não sobre a Iris —
mas vale orientar.

## 3. Como a arquitetura se encaixa

**A favor da tese "a Iris é só software":**
- A definição de PSAV gira em torno de agir *em nome de terceiros*. A Iris
  nunca tem a chave nem os sats de ninguém, não executa a troca e não recebe
  nada por ela.
- Na troca P2P, quem troca são os dois usuários; a Iris fornece o protocolo
  (como um app de mensagens com uma calculadora de garantia).
- Sem taxa sobre o fluxo nem spread (decisão do dono, ver memória do projeto).
- Sem servidor: não há ponto central que o regulador possa considerar
  "plataforma de negociação" operada pela Iris.

**Pontos de risco que o advogado precisa avaliar:**
1. **Livro de ofertas.** Mesmo descentralizado (Nostr), o app *aproxima*
   compradores e vendedores. Isso pode ser lido como intermediação?
2. **Árbitro.** Se a Iris (ou o dono) atuar como árbitro padrão, decide
   disputas sobre troca de Real por bitcoin. Isso aproxima de "participação
   em serviço"? É mais seguro o árbitro ser sempre escolhido pelo usuário,
   nunca a Iris?
3. **Art. 76-A da Res. 521.** Se transferir para carteira autocustodiada for
   câmbio, o usuário que vende sats a outro usuário Iris faz câmbio sem
   autorização? O risco recai sobre o usuário, sobre a Iris, ou sobre nenhum?
4. **Vouchers.** O lojista que vende voucher no balcão está trocando Real por
   bitcoin *para terceiros*, com habitualidade — vira PSAV? A Iris, que fornece
   a ferramenta de emissão, tem alguma responsabilidade?
5. **Pagar conta.** Quem paga o boleto de outro e recebe sats presta serviço
   de pagamento? E se fizer isso com habitualidade?
6. **Prevenção à lavagem.** Sem KYC, a Iris tem algum dever de comunicação ao
   COAF mesmo não sendo PSAV? Limites de valor no app (hoje: teto de
   200.000 sats no pagamento offline) ajudam a defesa?
7. **Distribuição.** Publicar o app nas lojas (Google Play/App Store) com
   P2P e vouchers muda alguma coisa (as lojas têm regras próprias para cripto)?

## 4. Estado atual no app (deliberado)

Trocas P2P, Pagar conta e emissão de vouchers estão **atrás do portão de
desenvolvedor** (dez toques na área de Pix) e só rodam na testnet4 nos testes.
Nada disso deve ir para a rede principal antes da resposta às perguntas acima.

## 5. Fontes

- Resoluções BCB 519/520/521: [Mattos Filho](https://www.mattosfilho.com.br/?p=118234),
  [BMA](https://www.bmalaw.com.br/conteudo/institucional/informativos-e-newsletters/banco-central-regulamenta-o-uso-de-ativos-virtuais-e-o-funcionamento-e-a-autorizacao-das-sociedades-prestadoras-de-servicos-de-ativos-virtuais/pdf),
  [Chambers](https://chambers.com/articles/o-novo-marco-regulatório-do-banco-central-para-ativos-virtuais-análise-das-resoluções),
  [Notabene](https://notabene.id/post/brazils-central-bank-regulates-virtual-asset-service-providers-what-bcb-resolutions-mean-for-crypto-compliance),
  [Conjur](https://www.conjur.com.br/?p=872048),
  [AMDJUS sobre P2P](https://amdjus.com.br/bcb-estabelece-regulamentacao-inedita-para-ativos-virtuais-e-peer-to-peer/),
  [Cescon Barrieu](https://cesconbarrieu.com.br/novas-resolucoes-do-banco-central-sobre-ativos-virtuais/)
- Lei 14.478/2022: [Justen](https://justen.com.br/ultimos_artigos/reflexoes-sobre-regulacao-dos-servicos-de-ativos-virtuais-no-brasil/),
  [Capital Aberto](https://www.capitalaberto.com.br/opiniao/artigos/2025/10/mercado-brasileiro-de-criptomoedas-estrutura-legal-e-perspectivas-regulatorias)
- Receita Federal IN 1888/2019: [LegisWeb](https://www.legisweb.com.br/legislacao/?id=377332)

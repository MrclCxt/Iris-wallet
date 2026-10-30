"""Teste de ponta a ponta do Lightning do Iris, sem celular e sem internet.

Sobe um bitcoind em regtest e dois iris-noded (A e B), e prova o caminho do
dinheiro: A recebe on-chain, abre canal com B, paga uma fatura de B, assina um
pagamento on-chain sem transmitir que B transmite, o canal fecha e o saldo
volta para a blockchain. Termina com código 0 só se tudo bater.

    python scripts/regtest_canal.py --bitcoin-bin <pasta com bitcoind e bitcoin-cli>

O daemon tem de estar compilado (cargo build --release em daemon/).
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = ".exe" if os.name == "nt" else ""
RPC_PORTA = 18543
RPC_USUARIO = "iris"
RPC_SENHA = "iris"

SEMENTES = {
    "A": "abandon abandon abandon abandon abandon abandon abandon abandon "
         "abandon abandon abandon about",
    "B": "legal winner thank year wave sausage worth useful legal winner "
         "thank yellow",
}
PORTAS = {"A": (18390, 19735), "B": (18391, 19736)}

PAGAMENTO_SATS = 10_000
CANAL_SATS = 500_000
OFFLINE_SATS = 20_000
GARANTIA_SATS = 15_000


def log(msg):
    print(f"[regtest] {msg}", flush=True)


def falhar(msg):
    log(f"FALHOU: {msg}")
    sys.exit(1)


def bitcoind_rpc(metodo, *params, carteira=None):
    url = f"http://127.0.0.1:{RPC_PORTA}/"
    if carteira:
        url += f"wallet/{carteira}"
    corpo = json.dumps({"jsonrpc": "1.0", "id": "iris", "method": metodo,
                        "params": list(params)}).encode()
    req = urllib.request.Request(url, corpo, {"Content-Type": "application/json"})
    import base64
    cred = base64.b64encode(f"{RPC_USUARIO}:{RPC_SENHA}".encode()).decode()
    req.add_header("Authorization", f"Basic {cred}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            resposta = json.load(r)
    except urllib.error.HTTPError as e:
        resposta = json.load(e)
    if resposta.get("error"):
        raise RuntimeError(f"{metodo}: {resposta['error']}")
    return resposta["result"]


def daemon(nome, metodo, rota, corpo=None):
    porta = PORTAS[nome][0]
    dados = json.dumps(corpo or {}).encode() if metodo == "POST" else None
    req = urllib.request.Request(f"http://127.0.0.1:{porta}{rota}", dados,
                                 method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{nome} {rota}: {e.read().decode()}")


def esperar(descricao, condicao, segundos=120):
    fim = time.time() + segundos
    ultimo = None
    while time.time() < fim:
        try:
            if condicao():
                return
        except Exception as e:  # noqa: BLE001 — o nó pode ainda não estar pronto
            ultimo = e
        time.sleep(1)
    falhar(f"tempo esgotado esperando {descricao} (último erro: {ultimo})")


_B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def wif_regtest(comprimida):
    """Chave privada de teste em WIF (prefixo 0xef), para o teste de varredura."""
    corpo = b"\xef" + os.urandom(32) + (b"\x01" if comprimida else b"")
    dados = corpo + hashlib.sha256(hashlib.sha256(corpo).digest()).digest()[:4]
    n = int.from_bytes(dados, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = _B58[r] + out
    return "1" * (len(dados) - len(dados.lstrip(b"\x00"))) + out


def esperar_evento(nome, tipo, hash_hex, segundos=60):
    """Consome a fila de eventos do daemon até achar [tipo] para [hash_hex]."""
    fim = time.time() + segundos
    while time.time() < fim:
        e = daemon(nome, "GET", "/event")["event"]
        if e is None:
            time.sleep(1)
            continue
        daemon(nome, "POST", "/event_handled")
        if e.get("type") == tipo and e.get("payment_hash") == hash_hex:
            return e
    falhar(f"{nome} não recebeu o evento {tipo} de {hash_hex[:12]}…")


def minerar(n, endereco):
    bitcoind_rpc("generatetoaddress", n, endereco)


def sincronizar(*nomes):
    for n in nomes:
        try:
            daemon(n, "POST", "/sync")
        except RuntimeError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitcoin-bin", required=True)
    ap.add_argument("--daemon", default=os.path.join(
        RAIZ, "daemon", "target", "release", f"iris-noded{EXE}"))
    ap.add_argument("--flutter", default=shutil.which("flutter"),
                    help="flutter para o teste de troca com o código do app")
    ap.add_argument("--manter", action="store_true",
                    help="não apaga a pasta temporária (para investigar falhas)")
    args = ap.parse_args()

    if not os.path.exists(args.daemon):
        falhar(f"daemon não encontrado em {args.daemon}")

    pasta = tempfile.mkdtemp(prefix="iris_regtest_")
    processos = []
    try:
        log(f"pasta de trabalho: {pasta}")
        btc_dados = os.path.join(pasta, "bitcoind")
        os.makedirs(btc_dados)
        processos.append(subprocess.Popen([
            os.path.join(args.bitcoin_bin, f"bitcoind{EXE}"),
            "-regtest", f"-datadir={btc_dados}", "-server", "-listen=0",
            f"-rpcport={RPC_PORTA}", f"-rpcuser={RPC_USUARIO}",
            f"-rpcpassword={RPC_SENHA}", "-fallbackfee=0.0002", "-txindex",
        ], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT))
        esperar("o bitcoind", lambda: bitcoind_rpc("getblockchaininfo"), 60)

        bitcoind_rpc("createwallet", "mineradora")
        mina = bitcoind_rpc("getnewaddress", carteira="mineradora")
        minerar(101, mina)
        log("bitcoind de pé, 101 blocos minerados")

        for nome in ("A", "B"):
            semente = os.path.join(pasta, f"semente_{nome}.txt")
            with open(semente, "w") as f:
                f.write(SEMENTES[nome])
            rest, p2p = PORTAS[nome]
            saida = open(os.path.join(pasta, f"daemon_{nome}.log"), "w")
            processos.append(subprocess.Popen([
                args.daemon, "--rede", "regtest", "--mnemonic-file", semente,
                "--data-dir", os.path.join(pasta, f"no_{nome}"),
                "--port", str(rest), "--p2p-porta", str(p2p),
                "--bitcoind-rpc",
                f"{RPC_USUARIO}:{RPC_SENHA}@127.0.0.1:{RPC_PORTA}",
            ], stdout=saida, stderr=subprocess.STDOUT))
        for nome in ("A", "B"):
            esperar(f"o daemon {nome}",
                    lambda n=nome: daemon(n, "GET", "/health")["network"] == "regtest",
                    90)
        log("dois daemons de pé na regtest")

        # B também recebe on-chain: canal com âncoras exige reserva dos dois lados.
        for nome, btc in (("A", 1.0), ("B", 0.1)):
            endereco = daemon(nome, "GET", "/onchain_address")["address"]
            bitcoind_rpc("sendtoaddress", endereco, btc, carteira="mineradora")
        minerar(6, mina)
        for nome in ("A", "B"):
            esperar(f"saldo on-chain de {nome}", lambda n=nome: (
                sincronizar(n) or
                daemon(n, "GET", "/balances")["onchain_spendable_sats"] > 0))
        log("A e B com saldo on-chain")

        id_b = daemon("B", "GET", "/node_id")["node_id"]
        daemon("A", "POST", "/open_channel", {
            "node_id": id_b, "host": "127.0.0.1", "port": PORTAS["B"][1],
            "amount_sats": CANAL_SATS,
        })
        esperar("a transação de abertura chegar ao mempool",
                lambda: len(bitcoind_rpc("getrawmempool")) > 0, 60)
        minerar(6, mina)

        def canal_utilizavel():
            sincronizar("A", "B")
            canais = daemon("A", "GET", "/channels")["channels"]
            return any(c["usable"] for c in canais)
        esperar("o canal ficar utilizável", canal_utilizavel)
        canal = daemon("A", "GET", "/channels")["channels"][0]
        log(f"canal aberto: {canal['capacity_sats']} sats")

        fatura = daemon("B", "POST", "/invoice", {
            "amount_msat": PAGAMENTO_SATS * 1000, "description": "teste regtest",
        })["invoice"]
        if not fatura.startswith("lnbcrt"):
            falhar(f"fatura com prefixo errado para a regtest: {fatura[:12]}")
        daemon("A", "POST", "/pay", {"invoice": fatura})

        def b_recebeu():
            return daemon("B", "GET", "/balances")["lightning_sats"] >= PAGAMENTO_SATS
        esperar("B receber o pagamento", b_recebeu, 60)

        recebidos = [p for p in daemon("B", "GET", "/payments")["payments"]
                     if p["incoming"] and not p["onchain"]
                     and p["status"] == "confirmed"]
        if len(recebidos) != 1 or recebidos[0]["amount_sats"] != PAGAMENTO_SATS:
            falhar(f"histórico de B deveria ter um recebimento de {PAGAMENTO_SATS}: "
                   f"{recebidos}")
        log(f"B recebeu {PAGAMENTO_SATS} sats pelo canal, uma linha no histórico")

        # Pagamento offline: A assina sem transmitir, a transação viaja (aqui,
        # pelo próprio teste — no app, por QR/NFC) e B transmite.
        endereco_b = daemon("B", "GET", "/onchain_address")["address"]
        assinada = daemon("A", "POST", "/sign_onchain", {
            "address": endereco_b, "amount_sats": OFFLINE_SATS,
        })
        if assinada["txid"] in bitcoind_rpc("getrawmempool"):
            falhar("a transação assinada offline foi transmitida sozinha")
        daemon("B", "POST", "/broadcast", {"tx_hex": assinada["tx_hex"]})
        if assinada["txid"] not in bitcoind_rpc("getrawmempool"):
            falhar("B transmitiu, mas a transação não chegou ao mempool")
        onchain_b_offline = daemon("B", "GET", "/balances")["onchain_total_sats"]
        minerar(1, mina)
        esperar("B ver o pagamento offline confirmado", lambda: (
            sincronizar("B") or
            daemon("B", "GET", "/balances")["onchain_total_sats"]
            >= onchain_b_offline + OFFLINE_SATS))
        log(f"pagamento offline: A assinou {OFFLINE_SATS} sats sem rede, "
            "B transmitiu e recebeu")

        # Taxa honesta: o app escolhe a taxa, vê o valor EXATO antes de
        # confirmar, e uma prévia cancelada não prende moedas.
        endereco_b2 = daemon("B", "GET", "/onchain_address")["address"]
        previa = daemon("A", "POST", "/sign_onchain", {
            "address": endereco_b2, "amount_sats": 12_000,
            "fee_rate_sat_per_kwu": 2500, "registrar": False,
        })
        # Desistiu da prévia: um novo envio pode usar as mesmas moedas.
        envio = daemon("A", "POST", "/sign_onchain", {
            "address": endereco_b2, "amount_sats": 12_000,
            "fee_rate_sat_per_kwu": 2500, "registrar": False,
        })
        decod = bitcoind_rpc("decoderawtransaction", envio["tx_hex"])
        por_vb = envio["fee_sats"] / decod["vsize"]
        if not 9.5 <= por_vb <= 11:
            falhar(f"taxa pedida 10 sat/vB, saiu {por_vb:.2f}")
        daemon("A", "POST", "/register_tx", {"tx_hex": envio["tx_hex"]})
        daemon("B", "POST", "/broadcast", {"tx_hex": envio["tx_hex"]})
        no_mempool = bitcoind_rpc("getmempoolentry", envio["txid"])
        taxa_real = round(no_mempool["fees"]["base"] * 1e8)
        if taxa_real != envio["fee_sats"]:
            falhar(f"app mostrou {envio['fee_sats']} sats de taxa, rede viu {taxa_real}")
        if previa["txid"] in bitcoind_rpc("getrawmempool"):
            falhar("a prévia cancelada foi transmitida")
        minerar(1, mina)
        log(f"taxa: pedida 10 sat/vB, saiu {por_vb:.1f}; o app mostrou "
            f"{envio['fee_sats']} sats e a rede cobrou {taxa_real}; prévia "
            "cancelada não prendeu as moedas")

        # Garantia de troca sem custódia (hold invoice): A vende sats, B compra.
        # A guarda o segredo; B cria a fatura só com o hash. O pagamento fica
        # travado até A revelar o segredo — ninguém no meio segura o dinheiro.
        segredo = os.urandom(32)
        h = hashlib.sha256(segredo).hexdigest()
        ln_b = daemon("B", "GET", "/balances")["lightning_sats"]
        fatura = daemon("B", "POST", "/hold_invoice", {
            "amount_msat": GARANTIA_SATS * 1000, "payment_hash": h,
        })["invoice"]
        daemon("A", "POST", "/pay", {"invoice": fatura})
        travado = esperar_evento("B", "payment_claimable", h)
        if daemon("B", "GET", "/balances")["lightning_sats"] != ln_b:
            falhar("B recebeu antes do segredo ser revelado")
        try:
            daemon("B", "POST", "/claim", {"payment_hash": h,
                   "preimage": os.urandom(32).hex(),
                   "amount_msat": travado["amount_msat"]})
            falhar("B conseguiu resgatar com um segredo errado")
        except RuntimeError:
            pass
        daemon("B", "POST", "/claim", {"payment_hash": h,
               "preimage": segredo.hex(), "amount_msat": travado["amount_msat"]})
        esperar("B receber a troca depois do segredo", lambda: (
            daemon("B", "GET", "/balances")["lightning_sats"]
            >= ln_b + GARANTIA_SATS), 60)
        log(f"garantia: {GARANTIA_SATS} sats travados até o segredo; "
            "segredo errado recusado; com o certo, B recebeu")

        # Troca desfeita: B recusa (ou o tempo acaba) e os sats voltam para A.
        h2 = hashlib.sha256(os.urandom(32)).hexdigest()
        fatura2 = daemon("B", "POST", "/hold_invoice", {
            "amount_msat": GARANTIA_SATS * 1000, "payment_hash": h2,
        })["invoice"]
        ln_a = daemon("A", "GET", "/balances")["lightning_sats"]
        daemon("A", "POST", "/pay", {"invoice": fatura2})
        esperar_evento("B", "payment_claimable", h2)
        daemon("B", "POST", "/fail", {"payment_hash": h2})
        esperar_evento("A", "payment_failed", h2)
        esperar("o saldo de A voltar", lambda: (
            daemon("A", "GET", "/balances")["lightning_sats"] >= ln_a), 60)
        log("troca desfeita: B recusou e os sats voltaram para A")

        # Troca P2P com o código real do app (TrocaService + RemoteNodeApi),
        # conversando por um relay local: caminho feliz e disputa com árbitro.
        if args.flutter:
            env = dict(os.environ,
                       IRIS_DAEMON_A=f"http://127.0.0.1:{PORTAS['A'][0]}",
                       IRIS_DAEMON_B=f"http://127.0.0.1:{PORTAS['B'][0]}",
                       IRIS_SEMENTE_A=SEMENTES["A"],
                       IRIS_SEMENTE_B=SEMENTES["B"],
                       IRIS_BITCOIND=f"http://{RPC_USUARIO}:{RPC_SENHA}@127.0.0.1:{RPC_PORTA}",
                       IRIS_WIF_SEGWIT=wif_regtest(True),
                       IRIS_WIF_LEGADO=wif_regtest(False))
            r = subprocess.run(
                [args.flutter, "test", "test/integracao"],
                cwd=RAIZ, env=env, shell=(os.name == "nt"))
            if r.returncode != 0:
                falhar("os testes do app contra a regtest falharam")
            log("app contra a regtest: troca P2P (caminho feliz e disputa pelo "
                "árbitro) e varredura de chave SegWit e legada aceitas pelo "
                "Bitcoin Core")
        else:
            log("flutter não encontrado: pulando a troca P2P do app")

        onchain_b_antes = daemon("B", "GET", "/balances")["onchain_total_sats"]
        daemon("A", "POST", "/close_channel", {
            "user_channel_id": canal["user_channel_id"],
            "counterparty_node_id": id_b,
        })
        esperar("a transação de fechamento chegar ao mempool",
                lambda: len(bitcoind_rpc("getrawmempool")) > 0, 60)
        minerar(6, mina)

        def fechou():
            sincronizar("A", "B")
            sem_canal = not daemon("A", "GET", "/channels")["channels"]
            b = daemon("B", "GET", "/balances")
            return sem_canal and b["onchain_total_sats"] > onchain_b_antes
        esperar("o canal fechar e o saldo de B voltar à blockchain", fechou)
        log("canal fechado cooperativamente; saldo de B voltou para o on-chain")

        log("PASSOU")
    finally:
        for p in reversed(processos):
            p.terminate()
        for p in processos:
            try:
                p.wait(timeout=20)
            except subprocess.TimeoutExpired:
                p.kill()
        if args.manter:
            log(f"pasta mantida em {pasta}")
        else:
            shutil.rmtree(pasta, ignore_errors=True)


if __name__ == "__main__":
    main()

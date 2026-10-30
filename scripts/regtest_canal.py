"""Teste de ponta a ponta do Lightning do Iris, sem celular e sem internet.

Sobe um bitcoind em regtest e dois iris-noded (A e B), e prova o caminho do
dinheiro: A recebe on-chain, abre canal com B, paga uma fatura de B, assina um
pagamento on-chain sem transmitir que B transmite, o canal fecha e o saldo
volta para a blockchain. Termina com código 0 só se tudo bater.

    python scripts/regtest_canal.py --bitcoin-bin <pasta com bitcoind e bitcoin-cli>

O daemon tem de estar compilado (cargo build --release em daemon/).
"""

import argparse
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

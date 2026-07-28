//! iris-noded — daemon local do nó Lightning do Iris Wallet.
//!
//! Roda o LDK Node como processo/serviço no próprio dispositivo e expõe uma
//! API REST **apenas em 127.0.0.1** (nunca na rede). O app Flutter conecta
//! neste daemon quando o "modo daemon" está configurado — útil para desktops
//! PDV que ficam ligados o dia todo. As chaves nunca saem da máquina.
//!
//! Uso:
//!   iris-noded --mnemonic-file ./seed.txt --data-dir ./iris_node_data \
//!              --port 8380 --esplora https://mempool.space/testnet4/api
//!
//! A API espelha o contrato do `RemoteNodeApi` do app:
//!   GET  /health           GET  /node_id         GET  /balances
//!   POST /invoice          POST /pay             GET  /onchain_address
//!   GET  /channels         POST /open_channel    POST /sync
//!   POST /set_forwarding_fee                     GET  /event
//!   POST /event_handled

use clap::Parser;
use ldk_node::bitcoin::Network;
use ldk_node::lightning_invoice::Bolt11Invoice;
use ldk_node::{Builder, ChannelConfig, Event, Node, UserChannelId};
use serde_json::{json, Value};
use std::fs;
use std::io::Read;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Parser)]
#[command(version, about)]
struct Args {
    /// Arquivo texto contendo a mnemônica BIP39 (12/24 palavras)
    #[arg(long)]
    mnemonic_file: String,

    /// Diretório de dados do nó
    #[arg(long, default_value = "./iris_node_data")]
    data_dir: String,

    /// Porta local (bind sempre em 127.0.0.1)
    #[arg(long, default_value_t = 8380)]
    port: u16,

    /// Servidor Esplora (testnet4 por padrão)
    #[arg(long, default_value = "https://mempool.space/testnet4/api")]
    esplora: String,
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn event_json(event: &Event) -> Value {
    match event {
        Event::PaymentReceived {
            payment_hash,
            amount_msat,
            ..
        } => json!({
            "type": "payment_received",
            "payment_hash": hex(&payment_hash.0),
            "amount_msat": amount_msat,
        }),
        Event::PaymentSuccessful { payment_hash, .. } => json!({
            "type": "payment_successful",
            "payment_hash": hex(&payment_hash.0),
        }),
        Event::PaymentFailed { payment_hash, .. } => json!({
            "type": "payment_failed",
            "payment_hash": hex(&payment_hash.0),
        }),
        _ => json!({ "type": "other" }),
    }
}

fn handle(node: &Arc<Node>, method: &str, path: &str, body: Value) -> Result<Value, String> {
    match (method, path) {
        ("GET", "/health") => Ok(json!({ "status": "ok" })),
        ("GET", "/node_id") => Ok(json!({ "node_id": node.node_id().to_string() })),
        ("GET", "/balances") => {
            let b = node.list_balances();
            Ok(json!({
                "lightning_sats": b.total_lightning_balance_sats,
                "onchain_total_sats": b.total_onchain_balance_sats,
                "onchain_spendable_sats": b.spendable_onchain_balance_sats,
            }))
        }
        ("POST", "/invoice") => {
            let description = body["description"].as_str().unwrap_or("Iris Wallet");
            let expiry = body["expiry_secs"].as_u64().unwrap_or(3600) as u32;
            let bolt11 = node.bolt11_payment();
            let invoice = match body["amount_msat"].as_u64() {
                Some(msat) => bolt11
                    .receive(msat, description, expiry)
                    .map_err(|e| e.to_string())?,
                None => bolt11
                    .receive_variable_amount(description, expiry)
                    .map_err(|e| e.to_string())?,
            };
            Ok(json!({ "invoice": invoice.to_string() }))
        }
        ("POST", "/pay") => {
            let invoice_str = body["invoice"].as_str().ok_or("invoice ausente")?;
            let invoice =
                Bolt11Invoice::from_str(invoice_str).map_err(|e| format!("fatura inválida: {e}"))?;
            let bolt11 = node.bolt11_payment();
            match body["amount_msat"].as_u64() {
                Some(msat) => bolt11
                    .send_using_amount(&invoice, msat)
                    .map(|_| ())
                    .map_err(|e| e.to_string())?,
                None => bolt11.send(&invoice).map(|_| ()).map_err(|e| e.to_string())?,
            }
            Ok(json!({ "status": "sent" }))
        }
        ("GET", "/onchain_address") => {
            let addr = node
                .onchain_payment()
                .new_address()
                .map_err(|e| e.to_string())?;
            Ok(json!({ "address": addr.to_string() }))
        }
        ("POST", "/send_onchain") => {
            let address_str = body["address"].as_str().ok_or("address ausente")?;
            let sats = body["amount_sats"].as_u64().ok_or("amount_sats ausente")?;
            let address = address_str
                .parse::<ldk_node::bitcoin::Address<_>>()
                .map_err(|e| format!("endereço inválido: {e}"))?
                .assume_checked();
            let txid = node
                .onchain_payment()
                .send_to_address(&address, sats)
                .map_err(|e| e.to_string())?;
            Ok(json!({ "txid": txid.to_string() }))
        }
        ("GET", "/channels") => {
            let channels: Vec<Value> = node
                .list_channels()
                .iter()
                .map(|ch| {
                    json!({
                        "capacity_sats": ch.channel_value_sats,
                        "inbound_sats": ch.inbound_capacity_msat / 1000,
                        "outbound_sats": ch.outbound_capacity_msat / 1000,
                        "usable": ch.is_usable,
                        "public": ch.is_public,
                        "counterparty": ch.counterparty_node_id.to_string(),
                        // Necessários para /set_forwarding_fee mirar este canal.
                        "user_channel_id": ch.user_channel_id.0.to_string(),
                        // Taxa de roteamento HOJE deste canal — 100% do usuário,
                        // creditada pelo próprio protocolo Lightning quando este
                        // nó encaminha um pagamento de terceiros. O daemon/app
                        // nunca retêm nada disso.
                        "forwarding_fee_proportional_ppm": ch.config.forwarding_fee_proportional_millionths(),
                        "forwarding_fee_base_msat": ch.config.forwarding_fee_base_msat(),
                    })
                })
                .collect();
            Ok(json!({ "channels": channels }))
        }
        ("POST", "/open_channel") => {
            let node_id = body["node_id"].as_str().ok_or("node_id ausente")?;
            let host = body["host"].as_str().ok_or("host ausente")?;
            let port = body["port"].as_u64().ok_or("port ausente")? as u16;
            let amount = body["amount_sats"].as_u64().ok_or("amount_sats ausente")?;
            let pubkey = node_id.parse().map_err(|_| "node_id inválido")?;
            let addr = format!("{host}:{port}")
                .parse()
                .map_err(|_| "endereço inválido")?;
            node.connect_open_channel(pubkey, addr, amount, None, None, true)
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/set_forwarding_fee") => {
            // Define a taxa de roteamento QUE ESTE USUÁRIO cobra quando o
            // próprio nó dele encaminha um pagamento de outra pessoa pela
            // rede. É nativo do protocolo Lightning: o LDK credita o valor
            // direto no saldo deste nó — nunca passa pelo Iris, nunca vira
            // receita do app. O usuário decide a taxa (ou deixa 0 para
            // priorizar ser escolhido em rotas, já que taxa menor atrai mais
            // roteamento).
            let user_channel_id_str = body["user_channel_id"]
                .as_str()
                .ok_or("user_channel_id ausente")?;
            let user_channel_id: u128 = user_channel_id_str
                .parse()
                .map_err(|_| "user_channel_id inválido")?;
            let counterparty_str = body["counterparty_node_id"]
                .as_str()
                .ok_or("counterparty_node_id ausente")?;
            let counterparty = counterparty_str
                .parse()
                .map_err(|_| "counterparty_node_id inválido")?;
            let proportional_ppm = body["forwarding_fee_proportional_ppm"]
                .as_u64()
                .unwrap_or(0) as u32;
            let base_msat = body["forwarding_fee_base_msat"]
                .as_u64()
                .unwrap_or(1000) as u32;

            let config = ChannelConfig::new();
            config.set_forwarding_fee_proportional_millionths(proportional_ppm);
            config.set_forwarding_fee_base_msat(base_msat);

            node.update_channel_config(
                &UserChannelId(user_channel_id),
                counterparty,
                Arc::new(config),
            )
            .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/sync") => {
            node.sync_wallets().map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("GET", "/event") => match node.next_event() {
            Some(e) => Ok(json!({ "event": event_json(&e) })),
            None => Ok(json!({ "event": null })),
        },
        ("POST", "/event_handled") => {
            node.event_handled();
            Ok(json!({}))
        }
        _ => Err(format!("rota desconhecida: {method} {path}")),
    }
}

/// Backends Esplora candidatos, na ordem de preferência: o passado por
/// `--esplora` primeiro (respeita a escolha explícita do usuário), depois os
/// mesmos dois usados pelo nó embarcado (ver `escolherEsplora` em
/// `node_backend.dart`). Servidores públicos de testnet oscilam (429 de
/// rate-limit, timeout) — sem isto, uma falha transitória de UM servidor
/// derrubava o daemon inteiro com panic (`FeerateEstimationUpdateFailed`),
/// já observado na prática.
fn escolher_esplora(preferido: &str) -> String {
    // Testnet4: só o mempool.space serve API HTTP nessa rede (o
    // blockstream.info devolve HTML nesse caminho). Sem fallback real.
    let fallback = ["https://mempool.space/testnet4/api"];
    let mut candidatos: Vec<&str> = vec![preferido];
    candidatos.extend(fallback.iter().filter(|&&u| u != preferido));

    for base in candidatos {
        let url = format!("{base}/blocks/tip/height");
        match ureq::get(&url).timeout(std::time::Duration::from_secs(6)).call() {
            Ok(resp) if resp.status() == 200 => {
                println!("iris-noded: Esplora escolhido: {base}");
                return base.to_string();
            }
            Ok(resp) => println!(
                "iris-noded: Esplora {base} respondeu HTTP {}; tentando outro.",
                resp.status()
            ),
            Err(e) => println!("iris-noded: Esplora {base} indisponível ({e}); tentando outro."),
        }
    }
    println!("iris-noded: nenhum Esplora respondeu; usando {preferido} mesmo assim.");
    preferido.to_string()
}

/// Constrói e inicia o nó, tentando de novo (com uma nova escolha de Esplora
/// a cada tentativa) se a primeira falhar — a causa mais comum é o backend
/// escolhido ter degradado bem no momento do boot, não um problema real da
/// carteira. Só desiste (panic) depois de esgotar as tentativas.
fn construir_e_iniciar(mnemonic: &str, args: &Args) -> Node {
    const TENTATIVAS: u32 = 3;
    let mut ultimo_erro = None;

    for tentativa in 1..=TENTATIVAS {
        let esplora = escolher_esplora(&args.esplora);
        let mut builder = Builder::new();
        builder.set_entropy_bip39_mnemonic(
            mnemonic.parse().expect("mnemônica inválida"),
            None,
        );
        // ldk-node 0.3 não conhece Testnet4 (depende do crate bitcoin 0.30;
        // testnet4 só existe a partir do 0.32). Os dados da cadeia vêm da
        // testnet4 pelo Esplora acima e os endereços são iguais nas duas
        // redes; o que fica na testnet3 é só o ChainHash anunciado no
        // Lightning. Ver a mesma nota em `node_backend.dart`.
        builder.set_network(Network::Testnet);
        builder.set_storage_dir_path(args.data_dir.clone());
        builder.set_esplora_server(esplora);

        // build() e start() erram com tipos diferentes (BuildError vs Error);
        // normaliza os dois para String antes de encadear.
        let build_result = builder
            .build()
            .map_err(|e| e.to_string())
            .and_then(|node| node.start().map_err(|e| e.to_string()).map(|_| node));
        match build_result {
            Ok(node) => return node,
            Err(e) => {
                println!(
                    "iris-noded: tentativa {tentativa}/{TENTATIVAS} de iniciar o nó falhou: {e}"
                );
                ultimo_erro = Some(e);
                if tentativa < TENTATIVAS {
                    std::thread::sleep(std::time::Duration::from_secs(3));
                }
            }
        }
    }
    panic!("falha ao iniciar o nó após {TENTATIVAS} tentativas: {ultimo_erro:?}");
}

fn main() {
    let args = Args::parse();

    let mnemonic = fs::read_to_string(&args.mnemonic_file)
        .expect("não foi possível ler o arquivo da mnemônica")
        .trim()
        .to_string();

    let node = Arc::new(construir_e_iniciar(&mnemonic, &args));

    println!("iris-noded: nó {} rodando (testnet4)", node.node_id());
    // Bind exclusivamente no loopback: o daemon nunca é exposto à rede.
    let server = tiny_http::Server::http(("127.0.0.1", args.port))
        .expect("falha ao abrir a porta local");
    println!("iris-noded: API REST em http://127.0.0.1:{}", args.port);

    for mut request in server.incoming_requests() {
        let method = request.method().as_str().to_uppercase();
        let path = request.url().split('?').next().unwrap_or("/").to_string();

        let mut body_str = String::new();
        let _ = request.as_reader().read_to_string(&mut body_str);
        let body: Value = serde_json::from_str(&body_str).unwrap_or(json!({}));

        let (status, payload) = match handle(&node, &method, &path, body) {
            Ok(v) => (200, v),
            Err(e) => (500, json!({ "error": e })),
        };

        let response = tiny_http::Response::from_string(payload.to_string())
            .with_status_code(status)
            .with_header(
                "Content-Type: application/json"
                    .parse::<tiny_http::Header>()
                    .unwrap(),
            );
        let _ = request.respond(response);
    }
}

use clap::Parser;
use ldk_node::bitcoin::Network;
use ldk_node::config::ChannelConfig;
use ldk_node::lightning_invoice::{Bolt11Invoice, Bolt11InvoiceDescription, Description};
use ldk_node::payment::{PaymentDirection, PaymentKind, PaymentStatus};
use ldk_node::{Builder, Event, Node, UserChannelId};
use serde_json::{json, Value};
use std::fs;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, clap::ValueEnum)]
enum Rede {
    Testnet4,
    Bitcoin,
    /// Blockchain local de teste (exige --bitcoind-rpc ou --esplora próprio).
    Regtest,
}

impl Rede {
    fn network(self) -> Network {
        match self {
            Rede::Testnet4 => Network::Testnet4,
            Rede::Bitcoin => Network::Bitcoin,
            Rede::Regtest => Network::Regtest,
        }
    }

    fn nome(self) -> &'static str {
        match self {
            Rede::Testnet4 => "testnet4",
            Rede::Bitcoin => "bitcoin",
            Rede::Regtest => "regtest",
        }
    }

    fn genesis(self) -> &'static str {
        match self {
            Rede::Testnet4 => "00000000da84f2bafbbc53dee25a72ae507ff4914b867c565be350b0da8bf043",
            Rede::Bitcoin => "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
            Rede::Regtest => "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206",
        }
    }

    fn esploras(self) -> &'static [&'static str] {
        match self {
            Rede::Testnet4 => &[
                "https://mempool.space/testnet4/api",
                "https://blockstream.info/testnet4/api",
                "https://mempool.va1.mempool.space/testnet4/api",
            ],
            Rede::Bitcoin => &[
                "https://mempool.space/api",
                "https://blockstream.info/api",
                "https://mempool.va1.mempool.space/api",
            ],
            Rede::Regtest => &[],
        }
    }

    fn pasta_padrao(self) -> &'static str {
        match self {
            Rede::Testnet4 => "./iris_node_data_tn4n",
            Rede::Bitcoin => "./iris_node_data_main",
            Rede::Regtest => "./iris_node_data_regtest",
        }
    }
}

#[derive(Parser)]
#[command(version, about)]
struct Args {
    #[arg(long)]
    mnemonic_file: String,

    #[arg(long, value_enum, default_value = "testnet4")]
    rede: Rede,

    /// Padrão: ./iris_node_data_tn4n na testnet4, ./iris_node_data_main na Bitcoin.
    #[arg(long)]
    data_dir: Option<String>,

    #[arg(long, default_value_t = 8380)]
    port: u16,

    /// Porta Lightning (P2P) para outros nós abrirem canal com este; 0 desliga.
    /// A API REST continua só em 127.0.0.1.
    #[arg(long, default_value_t = 9735)]
    p2p_porta: u16,

    /// Servidor Esplora próprio; pode repetir. Entram antes dos padrões.
    #[arg(long)]
    esplora: Vec<String>,

    /// Nó Bitcoin próprio, no formato usuario:senha@host:porta. Com ele, o
    /// daemon não consulta servidor de terceiro nenhum: os endereços da
    /// carteira não saem desta máquina.
    #[arg(long)]
    bitcoind_rpc: Option<String>,
}

enum Fonte {
    Esplora(String),
    Bitcoind { host: String, porta: u16, usuario: String, senha: String },
}

impl Fonte {
    fn descricao(&self) -> String {
        match self {
            Fonte::Esplora(u) => u.clone(),
            Fonte::Bitcoind { host, porta, .. } => format!("bitcoind {host}:{porta}"),
        }
    }
}

fn ler_bitcoind_rpc(s: &str) -> Fonte {
    let (cred, destino) = s
        .rsplit_once('@')
        .expect("--bitcoind-rpc deve ser usuario:senha@host:porta");
    let (usuario, senha) = cred
        .split_once(':')
        .expect("--bitcoind-rpc deve ser usuario:senha@host:porta");
    let (host, porta) = destino
        .rsplit_once(':')
        .expect("--bitcoind-rpc deve ser usuario:senha@host:porta");
    Fonte::Bitcoind {
        host: host.to_string(),
        porta: porta.parse().expect("porta do bitcoind inválida"),
        usuario: usuario.to_string(),
        senha: senha.to_string(),
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn descricao(s: &str) -> Bolt11InvoiceDescription {
    let d = Description::new(s.to_string())
        .unwrap_or_else(|_| Description::new(String::new()).expect("vazia é sempre válida"));
    Bolt11InvoiceDescription::Direct(d)
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
            "payment_hash": payment_hash.map(|h| hex(&h.0)).unwrap_or_default(),
        }),
        _ => json!({ "type": "other" }),
    }
}

fn pagamentos(node: &Node) -> Value {
    let lista: Vec<Value> = node
        .list_payments()
        .iter()
        .filter_map(|p| {
            let msat = p.amount_msat?;
            let onchain = matches!(p.kind, PaymentKind::Onchain { .. });
            // Mesmo id que o nó embarcado mostra: no on-chain é o txid, cuja
            // forma legível tem os bytes invertidos.
            let id = match &p.kind {
                PaymentKind::Onchain { txid, .. } => txid.to_string(),
                _ => hex(&p.id.0),
            };
            Some(json!({
                "id": id,
                "amount_sats": (msat as f64 / 1000.0).round() as u64,
                "incoming": p.direction == PaymentDirection::Inbound,
                "onchain": onchain,
                "status": match p.status {
                    PaymentStatus::Succeeded => "confirmed",
                    PaymentStatus::Failed => "failed",
                    _ => "pending",
                },
                "timestamp": p.latest_update_timestamp,
            }))
        })
        .collect();
    json!({ "payments": lista })
}

fn handle(node: &Arc<Node>, rede: Rede, method: &str, path: &str, body: Value) -> Result<Value, String> {
    match (method, path) {
        ("GET", "/health") => Ok(json!({ "status": "ok", "network": rede.nome() })),
        ("GET", "/node_id") => Ok(json!({ "node_id": node.node_id().to_string() })),
        ("GET", "/balances") => {
            let b = node.list_balances();
            Ok(json!({
                "lightning_sats": b.total_lightning_balance_sats,
                "onchain_total_sats": b.total_onchain_balance_sats,
                "onchain_spendable_sats": b.spendable_onchain_balance_sats,
            }))
        }
        ("GET", "/payments") => Ok(pagamentos(node)),
        ("POST", "/invoice") => {
            let desc = descricao(body["description"].as_str().unwrap_or("Iris Wallet"));
            let expiry = body["expiry_secs"].as_u64().unwrap_or(3600) as u32;
            let bolt11 = node.bolt11_payment();
            let invoice = match body["amount_msat"].as_u64() {
                Some(msat) => bolt11.receive(msat, &desc, expiry),
                None => bolt11.receive_variable_amount(&desc, expiry),
            }
            .map_err(|e| e.to_string())?;
            Ok(json!({ "invoice": invoice.to_string() }))
        }
        ("POST", "/offer") => {
            let desc = body["description"].as_str().unwrap_or("Iris Wallet");
            let offer = node
                .bolt12_payment()
                .receive_variable_amount(desc, None)
                .map_err(|e| e.to_string())?;
            Ok(json!({ "offer": offer.to_string() }))
        }
        ("POST", "/pay") => {
            let invoice_str = body["invoice"].as_str().ok_or("invoice ausente")?;
            let invoice =
                Bolt11Invoice::from_str(invoice_str).map_err(|e| format!("fatura inválida: {e}"))?;
            let bolt11 = node.bolt11_payment();
            match body["amount_msat"].as_u64() {
                Some(msat) => bolt11.send_using_amount(&invoice, msat, None),
                None => bolt11.send(&invoice, None),
            }
            .map_err(|e| e.to_string())?;
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
                .require_network(rede.network())
                .map_err(|_| "endereço de outra rede".to_string())?;
            let txid = node
                .onchain_payment()
                .send_to_address(&address, sats, None)
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
                        "public": ch.is_announced,
                        "counterparty": ch.counterparty_node_id.to_string(),
                        "user_channel_id": ch.user_channel_id.0.to_string(),
                        "forwarding_fee_proportional_ppm": ch.config.forwarding_fee_proportional_millionths,
                        "forwarding_fee_base_msat": ch.config.forwarding_fee_base_msat,
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
            node.open_channel(pubkey, addr, amount, None, None)
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/set_forwarding_fee") => {
            let user_channel_id: u128 = body["user_channel_id"]
                .as_str()
                .ok_or("user_channel_id ausente")?
                .parse()
                .map_err(|_| "user_channel_id inválido")?;
            let counterparty = body["counterparty_node_id"]
                .as_str()
                .ok_or("counterparty_node_id ausente")?
                .parse()
                .map_err(|_| "counterparty_node_id inválido")?;
            let mut config = ChannelConfig::default();
            config.forwarding_fee_proportional_millionths =
                body["forwarding_fee_proportional_ppm"].as_u64().unwrap_or(0) as u32;
            config.forwarding_fee_base_msat =
                body["forwarding_fee_base_msat"].as_u64().unwrap_or(1000) as u32;
            node.update_channel_config(&UserChannelId(user_channel_id), counterparty, config)
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/close_channel") => {
            let user_channel_id: u128 = body["user_channel_id"]
                .as_str()
                .ok_or("user_channel_id ausente")?
                .parse()
                .map_err(|_| "user_channel_id inválido")?;
            let counterparty = body["counterparty_node_id"]
                .as_str()
                .ok_or("counterparty_node_id ausente")?
                .parse()
                .map_err(|_| "counterparty_node_id inválido")?;
            node.close_channel(&UserChannelId(user_channel_id), counterparty)
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/sync") => {
            node.sync_wallets().map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/full_scan") => {
            node.full_scan_wallets().map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("GET", "/event") => match node.next_event() {
            Some(e) => Ok(json!({ "event": event_json(&e) })),
            None => Ok(json!({ "event": null })),
        },
        ("POST", "/event_handled") => {
            node.event_handled().map_err(|e| format!("{e:?}"))?;
            Ok(json!({}))
        }
        _ => Err(format!("rota desconhecida: {method} {path}")),
    }
}

/// `None` quando o servidor está pronto; senão, o motivo.
fn verificar_esplora(base: &str, rede: Rede) -> Option<String> {
    let timeout = std::time::Duration::from_secs(8);
    let genesis = match ureq::get(&format!("{base}/block-height/0")).timeout(timeout).call() {
        Ok(r) => r.into_string().unwrap_or_default(),
        Err(e) => return Some(format!("indisponível ({e})")),
    };
    if genesis.trim() != rede.genesis() {
        return Some("está em outra rede".into());
    }
    match ureq::get(&format!("{base}/fee-estimates")).timeout(timeout).call() {
        Ok(_) => None,
        Err(e) => Some(format!("não informa taxas ({e})")),
    }
}

fn esploras_em_ordem(proprios: &[String], rede: Rede) -> Vec<String> {
    let mut lista: Vec<String> = Vec::new();
    for u in proprios.iter().map(|s| s.trim_end_matches('/').to_string())
        .chain(rede.esploras().iter().map(|s| s.to_string()))
    {
        if !lista.contains(&u) {
            lista.push(u);
        }
    }
    for i in 0..lista.len() {
        match verificar_esplora(&lista[i], rede) {
            None => {
                println!("iris-noded: Esplora escolhido: {}", lista[i]);
                lista.rotate_left(i);
                return lista;
            }
            Some(motivo) => println!("iris-noded: Esplora {} {motivo}; tentando outro.", lista[i]),
        }
    }
    println!("iris-noded: nenhum Esplora passou na verificação; tentando na ordem.");
    lista
}

fn construir_e_iniciar(mnemonic: &str, args: &Args) -> Node {
    const TENTATIVAS: usize = 3;
    let fontes: Vec<Fonte> = match &args.bitcoind_rpc {
        Some(s) => vec![ler_bitcoind_rpc(s)],
        None => esploras_em_ordem(&args.esplora, args.rede)
            .into_iter()
            .map(Fonte::Esplora)
            .collect(),
    };
    if fontes.is_empty() {
        panic!("a rede {} exige --bitcoind-rpc ou --esplora", args.rede.nome());
    }
    let mut ultimo_erro = None;

    for tentativa in 0..TENTATIVAS {
        let fonte = &fontes[tentativa % fontes.len()];
        let mut builder = Builder::new();
        builder.set_entropy_bip39_mnemonic(mnemonic.parse().expect("mnemônica inválida"), None);
        builder.set_network(args.rede.network());
        builder.set_storage_dir_path(
            args.data_dir.clone().unwrap_or_else(|| args.rede.pasta_padrao().to_string()),
        );
        match fonte {
            Fonte::Esplora(url) => {
                builder.set_chain_source_esplora(url.clone(), None);
            }
            Fonte::Bitcoind { host, porta, usuario, senha } => {
                builder.set_chain_source_bitcoind_rpc(
                    host.clone(),
                    *porta,
                    usuario.clone(),
                    senha.clone(),
                );
            }
        }
        if args.p2p_porta != 0 {
            let endereco = format!("0.0.0.0:{}", args.p2p_porta)
                .parse()
                .expect("porta P2P inválida");
            builder
                .set_listening_addresses(vec![endereco])
                .expect("endereço P2P inválido");
        }

        let resultado = builder
            .build()
            .map_err(|e| e.to_string())
            .and_then(|node| node.start().map_err(|e| e.to_string()).map(|_| node));
        match resultado {
            Ok(node) => return node,
            Err(e) => {
                println!(
                    "iris-noded: tentativa {}/{TENTATIVAS} de iniciar o nó falhou ({}): {e}",
                    tentativa + 1,
                    fonte.descricao()
                );
                ultimo_erro = Some(e);
                if tentativa + 1 < TENTATIVAS {
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

    println!("iris-noded: nó {} rodando ({})", node.node_id(), args.rede.nome());

    let server = tiny_http::Server::http(("127.0.0.1", args.port))
        .expect("falha ao abrir a porta local");
    println!("iris-noded: API REST em http://127.0.0.1:{}", args.port);
    if args.p2p_porta != 0 {
        println!(
            "iris-noded: aceitando canais em {}@<ip-desta-máquina>:{}",
            node.node_id(),
            args.p2p_porta
        );
    }

    for mut request in server.incoming_requests() {
        let method = request.method().as_str().to_uppercase();
        let path = request.url().split('?').next().unwrap_or("/").to_string();

        let mut body_str = String::new();
        let _ = request.as_reader().read_to_string(&mut body_str);
        let body: Value = serde_json::from_str(&body_str).unwrap_or(json!({}));

        let (status, payload) = match handle(&node, args.rede, &method, &path, body) {
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

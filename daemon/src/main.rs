use clap::Parser;
use ldk_node::bitcoin::Network;
use ldk_node::config::ChannelConfig;
use ldk_node::lightning_invoice::{Bolt11Invoice, Bolt11InvoiceDescription, Description};
use ldk_node::payment::{PaymentDirection, PaymentKind, PaymentStatus};
use ldk_node::bitcoin::hashes::Hash;
use ldk_node::lightning_types::payment::{PaymentHash, PaymentPreimage};
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
    /// Semente CIFRADA no formato do app (enc1$...). Senha em IRIS_SENHA ou
    /// digitada no terminal. Semente em texto puro só com --aceitar-semente-em-claro.
    #[arg(long)]
    mnemonic_file: Option<String>,

    /// Aceita arquivo de semente em texto puro (testes/regtest). Não use com
    /// dinheiro de verdade: qualquer programa que leia o arquivo leva tudo.
    #[arg(long)]
    aceitar_semente_em_claro: bool,

    /// Cifra a semente de um arquivo em texto puro e sai. Grava em --saida.
    #[arg(long)]
    cifrar: Option<String>,

    #[arg(long)]
    saida: Option<String>,

    /// Onde gravar o token da API (padrão: pasta do usuário, ver README).
    #[arg(long)]
    token_file: Option<String>,

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

#[derive(Clone)]
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

/// Transmite uma transação já assinada pelo mesmo servidor que o nó usa.
fn transmitir(fonte: &Fonte, tx_hex: &str) -> Result<String, String> {
    let timeout = std::time::Duration::from_secs(20);
    match fonte {
        Fonte::Esplora(url) => ureq::post(&format!("{url}/tx"))
            .timeout(timeout)
            .send_string(tx_hex)
            .map_err(|e| match e {
                ureq::Error::Status(_, r) => r.into_string().unwrap_or_default(),
                outro => outro.to_string(),
            })?
            .into_string()
            .map_err(|e| e.to_string()),
        Fonte::Bitcoind { host, porta, usuario, senha } => {
            use std::io::Write;
            let mut cred = Vec::new();
            write!(cred, "{usuario}:{senha}").unwrap();
            let pedido = json!({
                "jsonrpc": "1.0", "id": "iris", "method": "sendrawtransaction",
                "params": [tx_hex],
            });
            let texto = match ureq::post(&format!("http://{host}:{porta}/"))
                .timeout(timeout)
                .set("Authorization", &format!("Basic {}", base64(&cred)))
                .set("Content-Type", "application/json")
                .send_string(&pedido.to_string())
            {
                Ok(r) => r.into_string(),
                Err(ureq::Error::Status(_, r)) => r.into_string(),
                Err(e) => return Err(e.to_string()),
            }
            .map_err(|e| e.to_string())?;
            let resp: Value = serde_json::from_str(&texto).map_err(|e| e.to_string())?;
            if !resp["error"].is_null() {
                return Err(resp["error"]["message"].as_str().unwrap_or("erro").to_string());
            }
            Ok(resp["result"].as_str().unwrap_or_default().to_string())
        }
    }
}

fn base64(dados: &[u8]) -> String {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for bloco in dados.chunks(3) {
        let b = [bloco[0], *bloco.get(1).unwrap_or(&0), *bloco.get(2).unwrap_or(&0)];
        let n = (b[0] as u32) << 16 | (b[1] as u32) << 8 | b[2] as u32;
        for i in 0..4 {
            if i <= bloco.len() {
                out.push(T[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
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

fn ler_32(v: &Value, nome: &str) -> Result<[u8; 32], String> {
    let s = v.as_str().ok_or(format!("{nome} ausente"))?;
    if s.len() != 64 {
        return Err(format!("{nome} deve ter 64 caracteres hex"));
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16)
            .map_err(|_| format!("{nome} não é hex"))?;
    }
    Ok(out)
}

fn ler_hash(v: &Value) -> Result<PaymentHash, String> {
    ler_32(v, "payment_hash").map(PaymentHash)
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
        Event::PaymentClaimable {
            payment_hash,
            claimable_amount_msat,
            claim_deadline,
            ..
        } => json!({
            "type": "payment_claimable",
            "payment_hash": hex(&payment_hash.0),
            "amount_msat": claimable_amount_msat,
            "claim_deadline": claim_deadline,
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

fn handle(
    node: &Arc<Node>,
    rede: Rede,
    fonte: &Fonte,
    method: &str,
    path: &str,
    body: Value,
) -> Result<Value, String> {
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
        // Garantia de troca sem custódia: a fatura é criada para um hash cujo
        // segredo só o outro lado tem. O pagamento fica travado até o segredo
        // aparecer (/claim) ou ser recusado (/fail) — ou expirar e voltar.
        ("POST", "/hold_invoice") => {
            let hash = ler_hash(&body["payment_hash"])?;
            let desc = descricao(body["description"].as_str().unwrap_or("Iris: troca"));
            let expiry = body["expiry_secs"].as_u64().unwrap_or(3600) as u32;
            let msat = body["amount_msat"].as_u64().ok_or("amount_msat ausente")?;
            let invoice = node
                .bolt11_payment()
                .receive_for_hash(msat, &desc, expiry, hash)
                .map_err(|e| e.to_string())?;
            Ok(json!({ "invoice": invoice.to_string() }))
        }
        ("POST", "/claim") => {
            let hash = ler_hash(&body["payment_hash"])?;
            let preimagem = ler_32(&body["preimage"], "preimage")?;
            if ldk_node::bitcoin::hashes::sha256::Hash::hash(&preimagem).to_byte_array() != hash.0 {
                return Err("o segredo não corresponde ao hash da fatura".into());
            }
            let msat = body["amount_msat"].as_u64().ok_or("amount_msat ausente")?;
            node.bolt11_payment()
                .claim_for_hash(hash, msat, PaymentPreimage(preimagem))
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/fail") => {
            let hash = ler_hash(&body["payment_hash"])?;
            node.bolt11_payment().fail_for_hash(hash).map_err(|e| e.to_string())?;
            Ok(json!({}))
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
        ("POST", "/sign_onchain") => {
            // Assina sem transmitir: a transação viaja por QR/NFC até alguém com
            // internet. Até lá, quem recebe tem só uma promessa.
            let address_str = body["address"].as_str().ok_or("address ausente")?;
            let sats = body["amount_sats"].as_u64().ok_or("amount_sats ausente")?;
            let address = address_str
                .parse::<ldk_node::bitcoin::Address<_>>()
                .map_err(|e| format!("endereço inválido: {e}"))?
                .require_network(rede.network())
                .map_err(|_| "endereço de outra rede".to_string())?;
            let taxa = body["fee_rate_sat_per_kwu"]
                .as_u64()
                .map(ldk_node::bitcoin::FeeRate::from_sat_per_kwu);
            let registrar = body["registrar"].as_bool().unwrap_or(true);
            let (tx, fee) = node
                .onchain_payment()
                .sign_to_address(&address, sats, taxa, registrar)
                .map_err(|e| e.to_string())?;
            Ok(json!({
                "txid": tx.compute_txid().to_string(),
                "tx_hex": ldk_node::bitcoin::consensus::encode::serialize_hex(&tx),
                "fee_sats": fee,
            }))
        }
        ("POST", "/register_tx") => {
            let tx: ldk_node::bitcoin::Transaction =
                ldk_node::bitcoin::consensus::encode::deserialize_hex(
                    body["tx_hex"].as_str().ok_or("tx_hex ausente")?.trim(),
                )
                .map_err(|e| format!("transação inválida: {e}"))?;
            node.onchain_payment()
                .register_unconfirmed(&tx)
                .map_err(|e| e.to_string())?;
            Ok(json!({}))
        }
        ("POST", "/broadcast") => {
            let tx_hex = body["tx_hex"].as_str().ok_or("tx_hex ausente")?.trim();
            let tx: ldk_node::bitcoin::Transaction =
                ldk_node::bitcoin::consensus::encode::deserialize_hex(tx_hex)
                    .map_err(|e| format!("transação inválida: {e}"))?;
            let txid = transmitir(fonte, tx_hex)?;
            Ok(json!({ "txid": if txid.is_empty() { tx.compute_txid().to_string() } else { txid } }))
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

fn construir_e_iniciar(mnemonic: &str, args: &Args) -> (Node, Fonte) {
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
            Ok(node) => return (node, fonte.clone()),
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

// ---------------------------------------------------------------- semente

const ITERACOES: u32 = 200_000;

fn chave_de(senha: &str, sal: &[u8], iteracoes: u32) -> [u8; 32] {
    let mut k = [0u8; 32];
    pbkdf2::pbkdf2_hmac::<sha2::Sha256>(senha.as_bytes(), sal, iteracoes, &mut k);
    k
}

/// Mesmo formato do app (lib/core/seed_crypto.dart): enc1$iter$sal$nonce$mac$cifra.
fn decifrar_semente(blob: &str, senha: &str) -> Result<String, String> {
    use aes_gcm::aead::{Aead, KeyInit, Payload};
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD;
    let p: Vec<&str> = blob.trim().split('$').collect();
    if p.len() != 6 || p[0] != "enc1" {
        return Err("formato de semente cifrada inválido".into());
    }
    let iter: u32 = p[1].parse().map_err(|_| "iterações inválidas")?;
    let sal = b64.decode(p[2]).map_err(|_| "sal inválido")?;
    let nonce = b64.decode(p[3]).map_err(|_| "nonce inválido")?;
    let mut cifra = b64.decode(p[5]).map_err(|_| "cifra inválida")?;
    cifra.extend(b64.decode(p[4]).map_err(|_| "mac inválido")?);
    let k = chave_de(senha, &sal, iter);
    let aes = aes_gcm::Aes256Gcm::new_from_slice(&k).map_err(|_| "chave inválida")?;
    let claro = aes
        .decrypt(aes_gcm::Nonce::from_slice(&nonce), Payload { msg: &cifra, aad: &[] })
        .map_err(|_| "senha incorreta".to_string())?;
    String::from_utf8(claro).map_err(|_| "semente corrompida".into())
}

fn cifrar_semente(semente: &str, senha: &str) -> String {
    use aes_gcm::aead::{Aead, KeyInit};
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD;
    let mut sal = [0u8; 16];
    let mut nonce = [0u8; 12];
    getrandom::getrandom(&mut sal).expect("gerador do sistema indisponível");
    getrandom::getrandom(&mut nonce).expect("gerador do sistema indisponível");
    let k = chave_de(senha, &sal, ITERACOES);
    let aes = aes_gcm::Aes256Gcm::new_from_slice(&k).unwrap();
    let saida = aes
        .encrypt(aes_gcm::Nonce::from_slice(&nonce), semente.as_bytes())
        .expect("falha ao cifrar");
    let (cifra, mac) = saida.split_at(saida.len() - 16);
    format!(
        "enc1${}${}${}${}${}",
        ITERACOES,
        b64.encode(sal),
        b64.encode(nonce),
        b64.encode(mac),
        b64.encode(cifra)
    )
}

fn senha(pergunta: &str) -> String {
    std::env::var("IRIS_SENHA").unwrap_or_else(|_| {
        rpassword::prompt_password(pergunta).expect("não foi possível ler a senha")
    })
}

fn ler_semente(args: &Args) -> String {
    let caminho = args
        .mnemonic_file
        .as_ref()
        .expect("informe --mnemonic-file com a semente cifrada");
    let conteudo = fs::read_to_string(caminho)
        .expect("não foi possível ler o arquivo da semente")
        .trim()
        .to_string();
    if conteudo.starts_with("enc1$") {
        return decifrar_semente(&conteudo, &senha("Senha da semente: "))
            .unwrap_or_else(|e| panic!("iris-noded: {e}"));
    }
    if !args.aceitar_semente_em_claro {
        eprintln!(
            "iris-noded: a semente está em TEXTO PURO em {caminho}. Cifre com\n  \
             iris-noded --cifrar {caminho} --saida semente.enc\n\
             e apague o arquivo original. (Para testes: --aceitar-semente-em-claro.)"
        );
        std::process::exit(2);
    }
    conteudo
}

// ---------------------------------------------------------------- token da API

fn caminho_token(args: &Args) -> std::path::PathBuf {
    if let Some(t) = &args.token_file {
        return t.into();
    }
    let base = std::env::var("APPDATA")
        .or_else(|_| std::env::var("XDG_CONFIG_HOME"))
        .or_else(|_| std::env::var("HOME").map(|h| format!("{h}/.config")))
        .expect("pasta do usuário não encontrada");
    std::path::Path::new(&base).join("iris-noded").join("api_token")
}

/// Token novo a cada partida, gravado só para o usuário. O app lê o arquivo;
/// um site no navegador não consegue — e sem o token nada passa.
fn criar_token(caminho: &std::path::Path) -> String {
    let mut b = [0u8; 32];
    getrandom::getrandom(&mut b).expect("gerador do sistema indisponível");
    let token = hex(&b);
    if let Some(d) = caminho.parent() {
        fs::create_dir_all(d).expect("não foi possível criar a pasta do token");
    }
    fs::write(caminho, &token).expect("não foi possível gravar o token");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(caminho, fs::Permissions::from_mode(0o600));
    }
    token
}

fn iguais_tempo_constante(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Barra o que não veio do app: sem token, de página web (Origin), de outro
/// host (DNS rebinding) ou com corpo que não é JSON (POST "simples" de CSRF).
fn autorizar(req: &tiny_http::Request, token: &str, porta: u16) -> Result<(), (u16, &'static str)> {
    let header = |nome: &str| {
        req.headers()
            .iter()
            .find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(nome))
            .map(|h| h.value.as_str().to_string())
    };
    if header("Origin").is_some() {
        return Err((403, "pedido vindo de página web recusado"));
    }
    let host = header("Host").unwrap_or_default();
    if host != format!("127.0.0.1:{porta}") && host != format!("localhost:{porta}") {
        return Err((403, "host inválido"));
    }
    let enviado = header("X-Iris-Token").unwrap_or_default();
    if !iguais_tempo_constante(enviado.as_bytes(), token.as_bytes()) {
        return Err((401, "token ausente ou inválido"));
    }
    if req.method().as_str().eq_ignore_ascii_case("POST") {
        let tipo = header("Content-Type").unwrap_or_default().to_ascii_lowercase();
        if !tipo.starts_with("application/json") {
            return Err((415, "corpo precisa ser application/json"));
        }
    }
    Ok(())
}

fn main() {
    let args = Args::parse();

    if let Some(origem) = &args.cifrar {
        let destino = args.saida.as_ref().expect("informe --saida para o arquivo cifrado");
        let claro = fs::read_to_string(origem).expect("não foi possível ler a semente").trim().to_string();
        let s1 = senha("Nova senha da semente: ");
        if std::env::var("IRIS_SENHA").is_err() {
            let s2 = rpassword::prompt_password("Repita a senha: ").expect("senha");
            if s1 != s2 {
                eprintln!("iris-noded: as senhas não conferem");
                std::process::exit(2);
            }
        }
        fs::write(destino, cifrar_semente(&claro, &s1)).expect("não foi possível gravar");
        println!("iris-noded: semente cifrada em {destino}. Apague {origem} com segurança.");
        return;
    }

    let mnemonic = ler_semente(&args);

    let (node, fonte) = construir_e_iniciar(&mnemonic, &args);
    let node = Arc::new(node);

    println!("iris-noded: nó {} rodando ({})", node.node_id(), args.rede.nome());

    let server = tiny_http::Server::http(("127.0.0.1", args.port))
        .expect("falha ao abrir a porta local");
    let arquivo_token = caminho_token(&args);
    let token = criar_token(&arquivo_token);
    println!("iris-noded: API REST em http://127.0.0.1:{}", args.port);
    println!("iris-noded: token da API em {}", arquivo_token.display());
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

        let (status, payload) = match autorizar(&request, &token, args.port) {
            Err((codigo, motivo)) => (codigo, json!({ "error": motivo })),
            Ok(()) => {
                let mut body_str = String::new();
                let _ = request.as_reader().read_to_string(&mut body_str);
                let body: Result<Value, _> = if body_str.trim().is_empty() {
                    Ok(json!({}))
                } else {
                    serde_json::from_str(&body_str)
                };
                match body {
                    Err(_) => (400, json!({ "error": "JSON inválido" })),
                    Ok(body) => match handle(&node, args.rede, &fonte, &method, &path, body) {
                        Ok(v) => (200, v),
                        Err(e) => (500, json!({ "error": e })),
                    },
                }
            }
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

#[cfg(test)]
mod testes {
    use super::*;

    const SEMENTE: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    /// Gerado pelo app (lib/core/seed_crypto.dart) com o PIN 123456.
    const BLOB_DO_APP: &str = "enc1$200000$fjOv7QxrP8tgqiaSr75WzA==$yhnYvWPJ6Cav04lu$ONVucqGDMt0NnE+P8F5Fbg==$qxr+1pLZgKG2jabD9fV3EAomPSw2fo0tMoWCn5aPpANuG07zZF5kvYQm+oXij5/xASCYjymQx+CfwjdHdOF2p6auMC3OziPaVnpAsyiVKci6ypc+v1qSwTfxctX1";

    #[test]
    fn abre_semente_cifrada_pelo_app() {
        assert_eq!(decifrar_semente(BLOB_DO_APP, "123456").unwrap(), SEMENTE);
    }

    #[test]
    fn recusa_senha_errada() {
        assert!(decifrar_semente(BLOB_DO_APP, "123457").is_err());
    }

    #[test]
    fn cifra_e_decifra_de_volta() {
        let blob = cifrar_semente(SEMENTE, "senha forte");
        assert!(blob.starts_with("enc1$200000$"));
        assert_eq!(decifrar_semente(&blob, "senha forte").unwrap(), SEMENTE);
        assert_ne!(cifrar_semente(SEMENTE, "x"), cifrar_semente(SEMENTE, "x"), "sal e nonce novos");
    }

    #[test]
    fn comparacao_de_token() {
        assert!(iguais_tempo_constante(b"abc", b"abc"));
        assert!(!iguais_tempo_constante(b"abc", b"abd"));
        assert!(!iguais_tempo_constante(b"abc", b"abcd"));
    }
}

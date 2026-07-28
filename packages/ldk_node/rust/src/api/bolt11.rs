use crate::api::types::{PaymentHash, PaymentId, PaymentPreimage};
use crate::frb_generated::RustOpaque;
use crate::utils::error::LdkNodeError;
use std::str::FromStr;

/// PORTE 0.7.0: os métodos `receive*` passaram a exigir
/// `&Bolt11InvoiceDescription` no lugar de `&str`. Este helper faz a ponte a
/// partir da String que a API Dart continua enviando, para a assinatura
/// pública do pacote não mudar.
///
/// Descrição inválida (acima do limite do BOLT11) vira descrição vazia em vez
/// de derrubar a criação da fatura — sem descrição a fatura ainda é válida e
/// pagável, que é o que importa para quem está cobrando.
fn descricao_bolt11(s: &str) -> ldk_node::lightning_invoice::Bolt11InvoiceDescription {
    use ldk_node::lightning_invoice::{Bolt11InvoiceDescription, Description};
    let d = Description::new(s.to_string())
        .unwrap_or_else(|_| Description::new(String::new()).expect("vazia é sempre válida"));
    Bolt11InvoiceDescription::Direct(d)
}

pub struct LdkBolt11Payment {
    pub ptr: RustOpaque<ldk_node::payment::Bolt11Payment>,
}
impl From<ldk_node::payment::Bolt11Payment> for LdkBolt11Payment {
    fn from(value: ldk_node::payment::Bolt11Payment) -> Self {
        LdkBolt11Payment {
            ptr: RustOpaque::new(value),
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
///Represents a syntactically and semantically correct lightning BOLT11 invoice.
///
pub struct Bolt11Invoice {
    pub signed_raw_invoice: String,
}

impl TryFrom<Bolt11Invoice> for ldk_node::lightning_invoice::Bolt11Invoice {
    type Error = LdkNodeError;

    fn try_from(value: Bolt11Invoice) -> Result<Self, Self::Error> {
        ldk_node::lightning_invoice::Bolt11Invoice::from_str(value.signed_raw_invoice.as_str())
            .map_err(|_| LdkNodeError::InvalidInvoice)
    }
}
impl From<ldk_node::lightning_invoice::Bolt11Invoice> for Bolt11Invoice {
    fn from(value: ldk_node::lightning_invoice::Bolt11Invoice) -> Self {
        Bolt11Invoice {
            signed_raw_invoice: value.to_string(),
        }
    }
}

impl LdkBolt11Payment {
    pub fn send(&self, invoice: Bolt11Invoice) -> Result<PaymentId, LdkNodeError> {
        self.ptr
            .send(&(invoice.try_into()?), None)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
    pub fn send_using_amount(
        &self,
        invoice: Bolt11Invoice,
        amount_msat: u64,
    ) -> anyhow::Result<PaymentId, LdkNodeError> {
        self.ptr
            .send_using_amount(&(invoice.try_into()?), amount_msat, None)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }

    pub fn send_probes(&self, invoice: Bolt11Invoice) -> anyhow::Result<(), LdkNodeError> {
        self.ptr
            .send_probes(&(invoice.try_into()?), None)
            .map_err(|e| e.into())
    }

    pub fn send_probes_using_amount(
        &self,
        invoice: Bolt11Invoice,
        amount_msat: u64,
    ) -> Result<(), LdkNodeError> {
        self.ptr
            .send_probes_using_amount(&(invoice.try_into()?), amount_msat, None)
            .map_err(|e| e.into())
    }
    pub fn claim_for_hash(
        &self,
        payment_hash: PaymentHash,
        claimable_amount_msat: u64,
        preimage: PaymentPreimage,
    ) -> anyhow::Result<(), LdkNodeError> {
        self.ptr
            .claim_for_hash(payment_hash.into(), claimable_amount_msat, preimage.into())
            .map_err(|e| e.into())
    }
    pub fn fail_for_hash(&self, payment_hash: PaymentHash) -> anyhow::Result<(), LdkNodeError> {
        self.ptr
            .fail_for_hash(payment_hash.into())
            .map_err(|e| e.into())
    }
    pub fn receive(
        &self,
        amount_msat: u64,
        description: String,
        expiry_secs: u32,
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        self.ptr
            .receive(amount_msat, &descricao_bolt11(description.as_str()), expiry_secs)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }

    pub fn receive_for_hash(
        &self,
        payment_hash: PaymentHash,
        amount_msat: u64,
        description: String,
        expiry_secs: u32,
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        self.ptr
            .receive_for_hash(
                amount_msat,
                &descricao_bolt11(description.as_str()),
                expiry_secs,
                payment_hash.into(),
            )
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
    pub fn receive_variable_amount(
        &self,
        description: String,
        expiry_secs: u32,
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        self.ptr
            .receive_variable_amount(&descricao_bolt11(description.as_str()), expiry_secs)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
    pub fn receive_variable_amount_via_jit_channel(
        &self,
        description: String,
        expiry_secs: u32,
        max_proportional_lsp_fee_limit_ppm_msat: Option<u64>,
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        match self.ptr.receive_variable_amount_via_jit_channel(
            &descricao_bolt11(description.as_str()),
            expiry_secs,
            max_proportional_lsp_fee_limit_ppm_msat,
        ) {
            Ok(e) => Ok(e.into()),
            Err(e) => Err(e.into()),
        }
    }

    pub fn receive_variable_amount_for_hash(
        &self,
        description: String,
        expiry_secs: u32,
        payment_hash: PaymentHash
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        match self.ptr.receive_variable_amount_for_hash(
            &descricao_bolt11(description.as_str()),
            expiry_secs,
            payment_hash.into()
        ) {
            Ok(e) => Ok(e.into()),
            Err(e) => Err(e.into()),
        }
    }

    pub fn receive_via_jit_channel(
        &self,
        amount_msat: u64,
        description: String,
        expiry_secs: u32,
        max_total_lsp_fee_limit_msat: Option<u64>,
    ) -> anyhow::Result<Bolt11Invoice, LdkNodeError> {
        match self.ptr.receive_via_jit_channel(
            amount_msat,
            &descricao_bolt11(description.as_str()),
            expiry_secs,
            max_total_lsp_fee_limit_msat,
        ) {
            Ok(e) => Ok(e.into()),
            Err(e) => Err(e.into()),
        }
    }
}

use crate::api::types::{Address, Txid};
use crate::frb_generated::RustOpaque;
use crate::utils::error::LdkNodeError;

pub struct SignedTransaction {
    pub txid: String,
    pub tx_hex: String,
    /// Taxa exata que a transação paga, em sats.
    pub fee_sats: u64,
}

pub struct LdkOnChainPayment {
    pub ptr: RustOpaque<ldk_node::payment::OnchainPayment>,
}
impl From<ldk_node::payment::OnchainPayment> for LdkOnChainPayment {
    fn from(value: ldk_node::payment::OnchainPayment) -> Self {
        LdkOnChainPayment {
            ptr: RustOpaque::new(value),
        }
    }
}

impl LdkOnChainPayment {
    pub fn new_address(&self) -> Result<Address, LdkNodeError> {
        self.ptr
            .new_address()
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
    pub fn send_to_address(
        &self,
        address: Address,
        amount_sats: u64,
    ) -> Result<Txid, LdkNodeError> {
        self.ptr
            .send_to_address(&(address.try_into()?), amount_sats, None)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
    /// Assina sem transmitir. `fee_rate_sat_per_kwu`: taxa escolhida pelo app
    /// (None = estimativa do nó). `registrar`: marca como pendente já (pagamento
    /// offline) ou deixa como prévia para [`Self::register_transaction`].
    pub fn sign_to_address(
        &self,
        address: Address,
        amount_sats: u64,
        fee_rate_sat_per_kwu: Option<u64>,
        registrar: bool,
    ) -> Result<SignedTransaction, LdkNodeError> {
        let taxa = fee_rate_sat_per_kwu.map(ldk_node::bitcoin::FeeRate::from_sat_per_kwu);
        self.ptr
            .sign_to_address(&(address.try_into()?), amount_sats, taxa, registrar)
            .map_err(|e| e.into())
            .map(|(tx, fee_sats)| SignedTransaction {
                txid: tx.compute_txid().to_string(),
                tx_hex: ldk_node::bitcoin::consensus::encode::serialize_hex(&tx),
                fee_sats,
            })
    }

    /// Marca como pendente uma transação assinada em prévia, depois que o
    /// usuário confirmou a taxa.
    pub fn register_transaction(&self, tx_hex: String) -> Result<(), LdkNodeError> {
        let tx: ldk_node::bitcoin::Transaction =
            ldk_node::bitcoin::consensus::encode::deserialize_hex(tx_hex.trim())
                .map_err(|_| LdkNodeError::OnchainTxCreationFailed)?;
        self.ptr.register_unconfirmed(&tx).map_err(|e| e.into())
    }
    pub fn send_all_to_address(&self, address: Address) -> Result<Txid, LdkNodeError> {
        self.ptr
            .send_all_to_address(&(address.try_into()?), true, None)
            .map_err(|e| e.into())
            .map(|e| e.into())
    }
}

use crate::api::builder::LdkMnemonic;
use crate::utils::error::{LdkBuilderError, LdkNodeError};
use flutter_rust_bridge::*;
use ldk_node::lightning::util::ser::{Readable, Writeable};
use std::default::Default;
use std::str::FromStr;
use std::string::ToString;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SocketAddress {
    TcpIpV4 {
        addr: [u8; 4],
        port: u16,
    },
    TcpIpV6 {
        addr: [u8; 16],
        port: u16,
    },
    OnionV2([u8; 12]),
    OnionV3 {
        ed25519_pubkey: [u8; 32],
        checksum: u16,
        version: u8,
        port: u16,
    },
    Hostname {
        addr: String,
        port: u16,
    },
}
impl From<ldk_node::lightning::ln::msgs::SocketAddress> for SocketAddress {
    fn from(value: ldk_node::lightning::ln::msgs::SocketAddress) -> Self {
        match value {
            ldk_node::lightning::ln::msgs::SocketAddress::TcpIpV4 { addr, port } => {
                SocketAddress::TcpIpV4 { addr, port }
            }
            ldk_node::lightning::ln::msgs::SocketAddress::TcpIpV6 { addr, port } => {
                SocketAddress::TcpIpV6 { addr, port }
            }
            ldk_node::lightning::ln::msgs::SocketAddress::OnionV2(e) => SocketAddress::OnionV2(e),
            ldk_node::lightning::ln::msgs::SocketAddress::OnionV3 {
                ed25519_pubkey,
                checksum,
                version,
                port,
            } => SocketAddress::OnionV3 {
                ed25519_pubkey,
                checksum,
                version,
                port,
            },
            ldk_node::lightning::ln::msgs::SocketAddress::Hostname { hostname, port } => {
                SocketAddress::Hostname {
                    addr: hostname.to_string(),
                    port,
                }
            }
        }
    }
}
impl TryFrom<SocketAddress> for ldk_node::lightning::ln::msgs::SocketAddress {
    type Error = LdkBuilderError;

    fn try_from(value: SocketAddress) -> Result<Self, Self::Error> {
        match value {
            SocketAddress::TcpIpV4 { addr, port } => {
                Ok(ldk_node::lightning::ln::msgs::SocketAddress::TcpIpV4 { addr, port })
            }
            SocketAddress::TcpIpV6 { addr, port } => {
                Ok(ldk_node::lightning::ln::msgs::SocketAddress::TcpIpV6 { addr, port })
            }
            SocketAddress::OnionV2(e) => {
                Ok(ldk_node::lightning::ln::msgs::SocketAddress::OnionV2(e))
            }
            SocketAddress::OnionV3 {
                ed25519_pubkey,
                checksum,
                version,
                port,
            } => Ok(ldk_node::lightning::ln::msgs::SocketAddress::OnionV3 {
                ed25519_pubkey,
                checksum,
                version,
                port,
            }),
            SocketAddress::Hostname { addr, port } => {
                Ok(ldk_node::lightning::ln::msgs::SocketAddress::Hostname {
                    hostname: ldk_node::lightning::util::ser::Hostname::try_from(addr)
                        .map_err(|_| LdkBuilderError::SocketAddressParseError)?,
                    port,
                })
            }
        }
    }
}
#[derive(Clone, Debug)]

pub struct ChannelConfig {

    pub forwarding_fee_proportional_millionths: u32,

    pub forwarding_fee_base_msat: u32,

    pub cltv_expiry_delta: u16,

    pub max_dust_htlc_exposure: Option<MaxDustHTLCExposure>,

    pub force_close_avoidance_max_fee_satoshis: u64,

    pub accept_underpaying_htlcs: bool,
}

impl From<ldk_node::config::ChannelConfig> for ChannelConfig {
    fn from(value: ldk_node::config::ChannelConfig) -> Self {
        ChannelConfig {
            forwarding_fee_proportional_millionths: value.forwarding_fee_proportional_millionths,
            forwarding_fee_base_msat: value.forwarding_fee_base_msat,
            cltv_expiry_delta: value.cltv_expiry_delta,
            max_dust_htlc_exposure: None,
            force_close_avoidance_max_fee_satoshis: value.force_close_avoidance_max_fee_satoshis,
            accept_underpaying_htlcs: value.accept_underpaying_htlcs,
        }
    }
}
#[derive(Debug, Clone)]
pub enum MaxDustHTLCExposure {

    FixedLimitMsat(u64),

    FeeRateMultiplier(u64),
}
impl From<ChannelConfig> for ldk_node::config::ChannelConfig {
    fn from(e: ChannelConfig) -> Self {

        let mut config = ldk_node::config::ChannelConfig::default();
        config.accept_underpaying_htlcs = e.accept_underpaying_htlcs;
        config.cltv_expiry_delta = e.cltv_expiry_delta;
        config.forwarding_fee_base_msat = e.forwarding_fee_base_msat;
        config.force_close_avoidance_max_fee_satoshis = e.force_close_avoidance_max_fee_satoshis;
        config.forwarding_fee_proportional_millionths = e.forwarding_fee_proportional_millionths;
        if let Some(max_dust_htlc_exposure) = e.max_dust_htlc_exposure {
            use ldk_node::config::MaxDustHTLCExposure as LdkMaxDust;

            config.max_dust_htlc_exposure = match max_dust_htlc_exposure {
                MaxDustHTLCExposure::FixedLimitMsat(e) => {
                    LdkMaxDust::FixedLimit { limit_msat: e }
                }
                MaxDustHTLCExposure::FeeRateMultiplier(e) => {
                    LdkMaxDust::FeeRateMultiplier { multiplier: e }
                }
            };
        }
        config
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChannelId {
    pub data: [u8; 32],
}

impl From<ldk_node::lightning::ln::types::ChannelId> for ChannelId {
    fn from(value: ldk_node::lightning::ln::types::ChannelId) -> Self {
        ChannelId { data: value.0 }
    }
}
impl From<ChannelId> for ldk_node::lightning::ln::types::ChannelId {
    fn from(value: ChannelId) -> Self {
        ldk_node::lightning::ln::types::ChannelId(value.data)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserChannelId {
    pub data: Vec<u8>,
}

impl From<ldk_node::UserChannelId> for UserChannelId {
    fn from(value: ldk_node::UserChannelId) -> Self {
        UserChannelId {
            data: value.encode(),
        }
    }
}
impl TryFrom<UserChannelId> for ldk_node::UserChannelId {
    type Error = LdkNodeError;

    fn try_from(value: UserChannelId) -> Result<Self, Self::Error> {
        let mut encoded = value.data.as_slice();
        ldk_node::UserChannelId::read(&mut encoded).map_err(|e| e.into())
    }
}
impl From<ldk_node::lightning::events::ClosureReason> for ClosureReason {
    fn from(value: ldk_node::lightning::events::ClosureReason) -> Self {
        match value {
            ldk_node::lightning::events::ClosureReason::CounterpartyForceClosed { peer_msg } => {
                ClosureReason::CounterpartyForceClosed {
                    peer_msg: peer_msg.0,
                }
            }
            ldk_node::lightning::events::ClosureReason::HolderForceClosed { .. } => {
                ClosureReason::HolderForceClosed
            }

            ldk_node::lightning::events::ClosureReason::CommitmentTxConfirmed => {
                ClosureReason::CommitmentTxConfirmed
            }
            ldk_node::lightning::events::ClosureReason::FundingTimedOut => {
                ClosureReason::FundingTimedOut
            }
            ldk_node::lightning::events::ClosureReason::ProcessingError { err } => {
                ClosureReason::ProcessingError { err }
            }
            ldk_node::lightning::events::ClosureReason::DisconnectedPeer => {
                ClosureReason::DisconnectedPeer
            }
            ldk_node::lightning::events::ClosureReason::OutdatedChannelManager => {
                ClosureReason::OutdatedChannelManager
            }
            ldk_node::lightning::events::ClosureReason::CounterpartyCoopClosedUnfundedChannel => {
                ClosureReason::CounterpartyCoopClosedUnfundedChannel
            }
            ldk_node::lightning::events::ClosureReason::FundingBatchClosure => {
                ClosureReason::FundingBatchClosure
            }
            ldk_node::lightning::events::ClosureReason::LegacyCooperativeClosure => {
                ClosureReason::LegacyCooperativeClosure
            }
            ldk_node::lightning::events::ClosureReason::CounterpartyInitiatedCooperativeClosure => {
                ClosureReason::CounterpartyInitiatedCooperativeClosure
            }
            ldk_node::lightning::events::ClosureReason::LocallyInitiatedCooperativeClosure => {
                ClosureReason::LocallyInitiatedCooperativeClosure
            }
            ldk_node::lightning::events::ClosureReason::HTLCsTimedOut { .. } => {
                ClosureReason::HTLCsTimedOut
            }

            outro => ClosureReason::ProcessingError {
                err: format!("{:?}", outro),
            },
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PaymentFailureReason {

    RecipientRejected,

    UserAbandoned,

    RetriesExhausted,

    PaymentExpired,

    RouteNotFound,

    UnexpectedError,
}
impl From<ldk_node::lightning::events::PaymentFailureReason> for PaymentFailureReason {
    fn from(value: ldk_node::lightning::events::PaymentFailureReason) -> Self {
        match value {
            ldk_node::lightning::events::PaymentFailureReason::RecipientRejected => {
                PaymentFailureReason::RecipientRejected
            }
            ldk_node::lightning::events::PaymentFailureReason::UserAbandoned => {
                PaymentFailureReason::UserAbandoned
            }
            ldk_node::lightning::events::PaymentFailureReason::RetriesExhausted => {
                PaymentFailureReason::RetriesExhausted
            }
            ldk_node::lightning::events::PaymentFailureReason::PaymentExpired => {
                PaymentFailureReason::PaymentExpired
            }
            ldk_node::lightning::events::PaymentFailureReason::RouteNotFound => {
                PaymentFailureReason::RouteNotFound
            }
            ldk_node::lightning::events::PaymentFailureReason::UnexpectedError => {
                PaymentFailureReason::UnexpectedError
            }

            _ => PaymentFailureReason::UnexpectedError,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]

pub enum ClosureReason {

    CounterpartyForceClosed {

        peer_msg: String,
    },

    HolderForceClosed,

    LegacyCooperativeClosure,

    CounterpartyInitiatedCooperativeClosure,

    LocallyInitiatedCooperativeClosure,

    CommitmentTxConfirmed,

    FundingTimedOut,

    ProcessingError {

        err: String,
    },

    DisconnectedPeer,

    OutdatedChannelManager,

    CounterpartyCoopClosedUnfundedChannel,

    FundingBatchClosure,

    HTLCsTimedOut,
}

#[derive(Eq, PartialEq, Debug, Clone)]
pub struct PaymentId(pub [u8; 32]);

impl From<ldk_node::lightning::ln::channelmanager::PaymentId> for PaymentId {
    fn from(value: ldk_node::lightning::ln::channelmanager::PaymentId) -> Self {
        PaymentId(value.0)
    }
}
impl From<PaymentId> for ldk_node::lightning::ln::channelmanager::PaymentId {
    fn from(value: PaymentId) -> Self {
        ldk_node::lightning::ln::channelmanager::PaymentId(value.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {

    PaymentClaimable {

        payment_id: PaymentId,

        payment_hash: PaymentHash,

        claimable_amount_msat: u64,

        claim_deadline: Option<u32>,
    },

    PaymentSuccessful {

        payment_id: Option<PaymentId>,

        payment_hash: PaymentHash,

        fee_paid_msat: Option<u64>,
    },

    PaymentFailed {

        payment_id: Option<PaymentId>,

        payment_hash: PaymentHash,

        reason: Option<PaymentFailureReason>,
    },

    PaymentReceived {

        payment_id: Option<PaymentId>,

        payment_hash: PaymentHash,

        amount_msat: u64,
    },

    ChannelPending {

        channel_id: ChannelId,

        user_channel_id: UserChannelId,

        former_temporary_channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        funding_txo: OutPoint,
    },

    ChannelReady {

        channel_id: ChannelId,

        user_channel_id: UserChannelId,

        counterparty_node_id: Option<PublicKey>,
    },

    ChannelClosed {

        channel_id: ChannelId,

        user_channel_id: UserChannelId,

        counterparty_node_id: Option<PublicKey>,

        reason: Option<ClosureReason>,
    },

    Unknown {

        kind: String,
    },
}

impl From<ldk_node::Event> for Event {
    fn from(value: ldk_node::Event) -> Self {
        match value {
            ldk_node::Event::PaymentSuccessful {
                payment_id,
                payment_hash,
                fee_paid_msat,
                ..
            } => Event::PaymentSuccessful {
                payment_id: payment_id.map(|e| e.into()),
                payment_hash: PaymentHash {
                    data: payment_hash.0,
                },
                fee_paid_msat,
            },
            ldk_node::Event::PaymentFailed {
                payment_id,
                payment_hash,
                reason,
                ..
            } => Event::PaymentFailed {
                payment_id: payment_id.map(|e| e.into()),
                payment_hash: PaymentHash {
                    data: payment_hash.map(|h| h.0).unwrap_or([0u8; 32]),
                },
                reason: reason.map(|e| e.into()),
            },
            ldk_node::Event::PaymentReceived {
                payment_id,
                payment_hash,
                amount_msat,
                ..
            } => Event::PaymentReceived {
                payment_id: payment_id.map(|e| e.into()),
                payment_hash: PaymentHash {
                    data: payment_hash.0,
                },
                amount_msat,
            },
            ldk_node::Event::ChannelReady {
                channel_id,
                user_channel_id,
                counterparty_node_id,
                ..
            } => Event::ChannelReady {
                channel_id: channel_id.into(),
                user_channel_id: user_channel_id.into(),
                counterparty_node_id: counterparty_node_id.map(|x| x.into()),
            },
            ldk_node::Event::ChannelClosed {
                channel_id,
                user_channel_id,
                counterparty_node_id,
                reason,
                ..
            } => Event::ChannelClosed {
                channel_id: channel_id.into(),
                user_channel_id: user_channel_id.into(),
                counterparty_node_id: counterparty_node_id.map(|x| x.into()),
                reason: reason.map(|e| e.into()),
            },
            ldk_node::Event::ChannelPending {
                channel_id,
                user_channel_id,
                former_temporary_channel_id,
                counterparty_node_id,
                funding_txo,
                ..
            } => Event::ChannelPending {
                channel_id: channel_id.into(),
                user_channel_id: user_channel_id.into(),
                former_temporary_channel_id: former_temporary_channel_id.into(),
                counterparty_node_id: PublicKey {
                    hex: counterparty_node_id.to_string(),
                },
                funding_txo: funding_txo.into(),
            },
            ldk_node::Event::PaymentClaimable {
                payment_id,
                payment_hash,
                claimable_amount_msat,
                claim_deadline,
                ..
            } => Event::PaymentClaimable {
                payment_id: payment_id.into(),
                payment_hash: payment_hash.into(),
                claimable_amount_msat: claimable_amount_msat,
                claim_deadline: claim_deadline,
            },
            outro => Event::Unknown {
                kind: format!("{:?}", outro),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Txid {
    pub hash: String,
}

impl TryFrom<Txid> for ldk_node::bitcoin::Txid {
    type Error = LdkNodeError;

    fn try_from(value: Txid) -> Result<Self, Self::Error> {
        ldk_node::bitcoin::Txid::from_str(value.hash.as_str())
            .map_err(|_| LdkNodeError::InvalidTxid)
    }
}

impl From<ldk_node::bitcoin::Txid> for Txid {
    fn from(value: ldk_node::bitcoin::Txid) -> Self {
        Txid {
            hash: value.to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutPoint {
    pub txid: Txid,
    pub vout: u32,
}

impl From<ldk_node::bitcoin::OutPoint> for OutPoint {
    fn from(value: ldk_node::bitcoin::OutPoint) -> Self {
        OutPoint {
            txid: Txid {
                hash: value.txid.to_raw_hash().to_string(),
            },
            vout: value.vout,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PaymentStatus {

    Pending,

    Succeeded,

    Failed,
}

impl From<ldk_node::payment::PaymentStatus> for PaymentStatus {
    fn from(value: ldk_node::payment::PaymentStatus) -> Self {
        match value {
            ldk_node::payment::PaymentStatus::Pending => PaymentStatus::Pending,
            ldk_node::payment::PaymentStatus::Succeeded => PaymentStatus::Succeeded,
            ldk_node::payment::PaymentStatus::Failed => PaymentStatus::Failed,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum PaymentDirection {

    Inbound,

    Outbound,
}

impl From<ldk_node::payment::PaymentDirection> for PaymentDirection {
    fn from(value: ldk_node::payment::PaymentDirection) -> Self {
        match value {
            ldk_node::payment::PaymentDirection::Inbound => PaymentDirection::Inbound,
            ldk_node::payment::PaymentDirection::Outbound => PaymentDirection::Outbound,
        }
    }
}

impl From<PaymentDirection> for ldk_node::payment::PaymentDirection {
    fn from(value: PaymentDirection) -> Self {
        match value {
            PaymentDirection::Inbound => ldk_node::payment::PaymentDirection::Inbound,
            PaymentDirection::Outbound => ldk_node::payment::PaymentDirection::Outbound,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct PaymentHash {
    pub data: [u8; 32],
}

impl From<PaymentHash> for ldk_node::lightning_types::payment::PaymentHash {
    fn from(value: PaymentHash) -> Self {
        ldk_node::lightning_types::payment::PaymentHash(value.data)
    }
}

impl From<ldk_node::lightning_types::payment::PaymentHash> for PaymentHash {
    fn from(value: ldk_node::lightning_types::payment::PaymentHash) -> Self {
        PaymentHash { data: value.0 }
    }
}

#[derive(Hash, Copy, Clone, PartialEq, Eq, Debug)]
pub struct PaymentPreimage {
    pub data: [u8; 32],
}

impl From<ldk_node::lightning_types::payment::PaymentPreimage> for PaymentPreimage {
    fn from(value: ldk_node::lightning_types::payment::PaymentPreimage) -> Self {
        Self { data: value.0 }
    }
}

impl From<PaymentPreimage> for ldk_node::lightning_types::payment::PaymentPreimage {
    fn from(value: PaymentPreimage) -> Self {
        ldk_node::lightning_types::payment::PaymentPreimage(value.data)
    }
}

#[derive(Hash, Copy, Clone, PartialEq, Eq, Debug)]
pub struct PaymentSecret {
    pub data: [u8; 32],
}

impl From<ldk_node::lightning_invoice::PaymentSecret> for PaymentSecret {
    fn from(value: ldk_node::lightning_invoice::PaymentSecret) -> Self {
        PaymentSecret { data: value.0 }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PaymentDetails {

    pub id: PaymentId,

    pub kind: PaymentKind,

    pub amount_msat: Option<u64>,

    pub direction: PaymentDirection,

    pub status: PaymentStatus,

    pub latest_update_timestamp: u64,
}

impl From<ldk_node::payment::PaymentDetails> for PaymentDetails {
    fn from(value: ldk_node::payment::PaymentDetails) -> Self {
        PaymentDetails {
            id: value.id.into(),
            status: value.status.into(),
            amount_msat: value.amount_msat,
            direction: value.direction.into(),
            kind: value.kind.into(),
            latest_update_timestamp: value.latest_update_timestamp,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct LSPFeeLimits {

    pub max_total_opening_fee_msat: Option<u64>,

    pub max_proportional_opening_fee_ppm_msat: Option<u64>,
}
impl From<ldk_node::payment::LSPFeeLimits> for LSPFeeLimits {
    fn from(value: ldk_node::payment::LSPFeeLimits) -> Self {
        LSPFeeLimits {
            max_total_opening_fee_msat: value.max_total_opening_fee_msat,
            max_proportional_opening_fee_ppm_msat: value.max_proportional_opening_fee_ppm_msat,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OfferId(pub [u8; 32]);

impl From<ldk_node::lightning::offers::offer::OfferId> for OfferId {
    fn from(value: ldk_node::lightning::offers::offer::OfferId) -> Self {
        Self(value.0)
    }
}
impl From<OfferId> for ldk_node::lightning::offers::offer::OfferId {
    fn from(value: OfferId) -> Self {
        Self(value.0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PaymentKind {

    Onchain,

    Bolt11 {

        hash: PaymentHash,

        preimage: Option<PaymentPreimage>,

        secret: Option<PaymentSecret>,
    },

    Bolt11Jit {

        hash: PaymentHash,

        preimage: Option<PaymentPreimage>,

        secret: Option<PaymentSecret>,

        lsp_fee_limits: LSPFeeLimits,
    },

    Spontaneous {

        hash: PaymentHash,

        preimage: Option<PaymentPreimage>,
    },

    Bolt12Offer {

        hash: Option<PaymentHash>,

        preimage: Option<PaymentPreimage>,

        secret: Option<PaymentSecret>,

        offer_id: OfferId,
    },

    Bolt12Refund {

        hash: Option<PaymentHash>,

        preimage: Option<PaymentPreimage>,

        secret: Option<PaymentSecret>,
    },
}
impl From<ldk_node::payment::PaymentKind> for PaymentKind {
    fn from(value: ldk_node::payment::PaymentKind) -> Self {
        match value {
            ldk_node::payment::PaymentKind::Onchain { .. } => PaymentKind::Onchain,
            ldk_node::payment::PaymentKind::Bolt11 {
                hash,
                preimage,
                secret,
                ..

            } => PaymentKind::Bolt11 {
                hash: hash.into(),
                preimage: preimage.map(|e| e.into()),
                secret: secret.map(|e| e.into()),
            },
            ldk_node::payment::PaymentKind::Bolt11Jit {
                hash,
                preimage,
                secret,
                lsp_fee_limits,
                ..
            } => PaymentKind::Bolt11Jit {
                hash: hash.into(),
                preimage: preimage.map(|e| e.into()),
                secret: secret.map(|e| e.into()),
                lsp_fee_limits: lsp_fee_limits.into(),
            },
            ldk_node::payment::PaymentKind::Spontaneous { hash, preimage, .. } => {
                PaymentKind::Spontaneous {
                    hash: hash.into(),
                    preimage: preimage.map(|e| e.into()),
                }
            }
            ldk_node::payment::PaymentKind::Bolt12Offer {
                hash,
                preimage,
                secret,
                offer_id,
                ..
            } => PaymentKind::Bolt12Offer {
                hash: hash.map(|e| e.into()),
                preimage: preimage.map(|e| e.into()),
                secret: secret.map(|e| e.into()),
                offer_id: offer_id.into(),
            },
            ldk_node::payment::PaymentKind::Bolt12Refund {
                hash,
                preimage,
                secret,
                ..
            } => PaymentKind::Bolt12Refund {
                hash: hash.map(|e| e.into()),
                preimage: preimage.map(|e| e.into()),
                secret: secret.map(|e| e.into()),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublicKey {
    pub hex: String,
}

impl TryFrom<PublicKey> for ldk_node::bitcoin::secp256k1::PublicKey {
    type Error = LdkNodeError;

    fn try_from(value: PublicKey) -> Result<Self, Self::Error> {
        ldk_node::bitcoin::secp256k1::PublicKey::from_str(value.hex.as_str())
            .map_err(|_| LdkNodeError::InvalidPublicKey)
    }
}
impl From<ldk_node::bitcoin::secp256k1::PublicKey> for PublicKey {
    fn from(value: ldk_node::bitcoin::secp256k1::PublicKey) -> Self {
        PublicKey {
            hex: value.to_string(),
        }
    }
}

pub struct Address {
    pub s: String,
}

impl TryFrom<Address> for ldk_node::bitcoin::Address {
    type Error = LdkNodeError;

    fn try_from(value: Address) -> Result<Self, Self::Error> {
        ldk_node::bitcoin::Address::from_str(value.s.as_str())
            .map(|e| e.assume_checked())
            .map_err(|_| LdkNodeError::InvalidAddress)
    }
}
impl From<ldk_node::bitcoin::Address> for Address {
    fn from(value: ldk_node::bitcoin::Address) -> Self {
        Address {
            s: value.to_string(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ChannelDetails {

    pub channel_id: ChannelId,

    pub counterparty_node_id: PublicKey,

    pub funding_txo: Option<OutPoint>,

    pub channel_value_sats: u64,

    pub unspendable_punishment_reserve: Option<u64>,

    pub user_channel_id: UserChannelId,

    pub feerate_sat_per_1000_weight: u32,

    pub outbound_capacity_msat: u64,

    pub inbound_capacity_msat: u64,

    pub confirmations_required: Option<u32>,

    pub confirmations: Option<u32>,

    pub is_outbound: bool,

    pub is_channel_ready: bool,

    pub is_usable: bool,

    pub is_public: bool,

    pub cltv_expiry_delta: Option<u16>,

    pub counterparty_unspendable_punishment_reserve: u64,

    pub counterparty_outbound_htlc_minimum_msat: Option<u64>,

    pub counterparty_outbound_htlc_maximum_msat: Option<u64>,

    pub counterparty_forwarding_info_fee_base_msat: Option<u32>,

    pub counterparty_forwarding_info_fee_proportional_millionths: Option<u32>,

    pub counterparty_forwarding_info_cltv_expiry_delta: Option<u16>,

    pub next_outbound_htlc_limit_msat: u64,

    pub next_outbound_htlc_minimum_msat: u64,

    pub force_close_spend_delay: Option<u16>,

    pub inbound_htlc_minimum_msat: u64,

    pub inbound_htlc_maximum_msat: Option<u64>,

    pub config: ChannelConfig,
}
impl From<&ldk_node::ChannelDetails> for ChannelDetails {
    fn from(value: &ldk_node::ChannelDetails) -> Self {
        ChannelDetails {
            channel_id: value.clone().channel_id.into(),
            counterparty_node_id: value.clone().counterparty_node_id.into(),
            funding_txo: value.clone().funding_txo.map(|x| x.into()),
            channel_value_sats: value.clone().channel_value_sats,
            unspendable_punishment_reserve: value.clone().unspendable_punishment_reserve,
            user_channel_id: value.clone().user_channel_id.into(),
            feerate_sat_per_1000_weight: value.clone().feerate_sat_per_1000_weight,
            outbound_capacity_msat: value.clone().outbound_capacity_msat,
            inbound_capacity_msat: value.clone().inbound_capacity_msat,
            confirmations_required: value.clone().confirmations_required,
            confirmations: value.clone().confirmations,
            is_outbound: value.clone().is_outbound,
            is_channel_ready: value.clone().is_channel_ready,
            is_usable: value.clone().is_usable,
            is_public: value.clone().is_announced,
            cltv_expiry_delta: value.clone().cltv_expiry_delta,
            counterparty_unspendable_punishment_reserve: value
                .clone()
                .counterparty_unspendable_punishment_reserve,
            counterparty_outbound_htlc_minimum_msat: value
                .clone()
                .counterparty_outbound_htlc_minimum_msat,
            counterparty_outbound_htlc_maximum_msat: value
                .clone()
                .counterparty_outbound_htlc_maximum_msat,
            counterparty_forwarding_info_fee_base_msat: value
                .clone()
                .counterparty_forwarding_info_fee_base_msat,
            counterparty_forwarding_info_fee_proportional_millionths: value
                .counterparty_forwarding_info_fee_proportional_millionths,
            counterparty_forwarding_info_cltv_expiry_delta: value
                .counterparty_forwarding_info_cltv_expiry_delta,
            next_outbound_htlc_limit_msat: value.next_outbound_htlc_limit_msat,
            next_outbound_htlc_minimum_msat: value.next_outbound_htlc_minimum_msat,
            force_close_spend_delay: value.force_close_spend_delay,
            inbound_htlc_minimum_msat: value.inbound_htlc_minimum_msat,
            inbound_htlc_maximum_msat: value.inbound_htlc_maximum_msat,
            config: value.config.clone().into(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Network {

    Bitcoin,

    Testnet,

    Testnet4,

    Signet,

    Regtest,
}

impl From<Network> for ldk_node::bitcoin::Network {
    fn from(value: Network) -> Self {
        match value {
            Network::Bitcoin => ldk_node::bitcoin::Network::Bitcoin,
            Network::Testnet => ldk_node::bitcoin::Network::Testnet,
            Network::Testnet4 => ldk_node::bitcoin::Network::Testnet4,
            Network::Signet => ldk_node::bitcoin::Network::Signet,
            Network::Regtest => ldk_node::bitcoin::Network::Regtest,
        }
    }
}
impl From<ldk_node::bitcoin::Network> for Network {
    fn from(value: ldk_node::bitcoin::Network) -> Self {
        match value {
            ldk_node::bitcoin::Network::Bitcoin => Network::Bitcoin,
            ldk_node::bitcoin::Network::Testnet => Network::Testnet,
            ldk_node::bitcoin::Network::Testnet4 => Network::Testnet4,
            ldk_node::bitcoin::Network::Signet => Network::Signet,
            ldk_node::bitcoin::Network::Regtest => Network::Regtest,
            _ => Network::Bitcoin,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerDetails {

    pub node_id: PublicKey,

    pub address: SocketAddress,

    pub is_connected: bool,
}

impl From<ldk_node::PeerDetails> for PeerDetails {
    fn from(value: ldk_node::PeerDetails) -> Self {
        PeerDetails {
            node_id: value.node_id.into(),
            address: value.address.into(),
            is_connected: value.is_connected,
        }
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum LogLevel {

    Gossip,

    Trace,

    Debug,

    Info,

    Warn,

    Error,
}

impl From<LogLevel> for ldk_node::logger::LogLevel {
    fn from(value: LogLevel) -> Self {
        match value {
            LogLevel::Gossip => ldk_node::logger::LogLevel::Gossip,
            LogLevel::Trace => ldk_node::logger::LogLevel::Trace,
            LogLevel::Debug => ldk_node::logger::LogLevel::Debug,
            LogLevel::Info => ldk_node::logger::LogLevel::Info,
            LogLevel::Warn => ldk_node::logger::LogLevel::Warn,
            LogLevel::Error => ldk_node::logger::LogLevel::Error,
        }
    }
}

impl From<ldk_node::logger::LogLevel> for LogLevel {
    fn from(value: ldk_node::logger::LogLevel) -> Self {
        match value {
            ldk_node::logger::LogLevel::Gossip => LogLevel::Gossip,
            ldk_node::logger::LogLevel::Trace => LogLevel::Trace,
            ldk_node::logger::LogLevel::Debug => LogLevel::Debug,
            ldk_node::logger::LogLevel::Info => LogLevel::Info,
            ldk_node::logger::LogLevel::Warn => LogLevel::Warn,
            ldk_node::logger::LogLevel::Error => LogLevel::Error,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AnchorChannelsConfig {

    pub trusted_peers_no_reserve: Vec<PublicKey>,

    pub per_channel_reserve_sats: u64,
}

impl TryFrom<AnchorChannelsConfig> for ldk_node::config::AnchorChannelsConfig {
    type Error = LdkBuilderError;

    fn try_from(value: AnchorChannelsConfig) -> Result<Self, Self::Error> {
        let trusted_peers_no_reserve: Result<
            Vec<ldk_node::bitcoin::secp256k1::PublicKey>,
            LdkBuilderError,
        > = value
            .trusted_peers_no_reserve
            .into_iter()
            .map(|x| x.try_into().map_err(|_| LdkBuilderError::InvalidPublicKey))
            .collect();
        Ok(Self {
            trusted_peers_no_reserve: trusted_peers_no_reserve?,
            per_channel_reserve_sats: value.per_channel_reserve_sats,
        })
    }
}

impl From<ldk_node::config::AnchorChannelsConfig> for AnchorChannelsConfig {
    fn from(value: ldk_node::config::AnchorChannelsConfig) -> Self {
        Self {
            trusted_peers_no_reserve: value
                .trusted_peers_no_reserve
                .into_iter()
                .map(|e| e.into())
                .collect(),
            per_channel_reserve_sats: value.per_channel_reserve_sats,
        }
    }
}

impl TryFrom<Config> for ldk_node::config::Config {
    type Error = LdkBuilderError;

    fn try_from(value: Config) -> Result<Self, Self::Error> {
        let addresses = if let Some(addresses) = value.listening_addresses {
            let addr_vec: Result<
                Vec<ldk_node::lightning::ln::msgs::SocketAddress>,
                LdkBuilderError,
            > = addresses
                .into_iter()
                .map(|socket_addr| socket_addr.try_into())
                .collect();
            Some(addr_vec?)
        } else {
            None
        };
        let anchor_channels_config =
            if let Some(anchor_channels_config) = value.anchor_channels_config {
                let anchr_channels_config: Result<ldk_node::config::AnchorChannelsConfig, LdkBuilderError> =
                    anchor_channels_config.try_into();
                Some(anchr_channels_config?)
            } else {
                None
            };
        let trusted_peers_0conf: Result<
            Vec<ldk_node::bitcoin::secp256k1::PublicKey>,
            LdkBuilderError,
        > = value
            .trusted_peers_0conf
            .into_iter()
            .map(|x| x.try_into().map_err(|_| LdkBuilderError::InvalidPublicKey))
            .collect();

        let mut cfg = ldk_node::config::Config::default();
        cfg.storage_dir_path = value.storage_dir_path;
        cfg.network = value.network.into();
        cfg.listening_addresses = addresses;
        cfg.trusted_peers_0conf = trusted_peers_0conf?;
        cfg.probing_liquidity_limit_multiplier = value.probing_liquidity_limit_multiplier;
        cfg.anchor_channels_config = anchor_channels_config;
        Ok(cfg)
    }
}
impl From<ldk_node::config::Config> for Config {
    fn from(value: ldk_node::config::Config) -> Self {

        Config {
            storage_dir_path: value.storage_dir_path,
            log_dir_path: None,
            network: value.network.into(),
            listening_addresses: value.listening_addresses.map(|vec_socket_addr| {
                vec_socket_addr
                    .into_iter()
                    .map(|socket_addr| socket_addr.into())
                    .collect()
            }),
            default_cltv_expiry_delta: 144,
            onchain_wallet_sync_interval_secs: 80,
            wallet_sync_interval_secs: 30,
            fee_rate_cache_update_interval_secs: 600,
            trusted_peers_0conf: value
                .trusted_peers_0conf
                .into_iter()
                .map(|x| x.into())
                .collect(),
            log_level: LogLevel::Debug,
            probing_liquidity_limit_multiplier: value.probing_liquidity_limit_multiplier,
            anchor_channels_config: value.anchor_channels_config.map(|e| e.into()),
        }
    }
}

#[frb(serialize)]
#[derive(Debug, Clone)]
pub struct Config {
    #[frb(non_final)]
    pub storage_dir_path: String,
    #[frb(non_final)]
    pub log_dir_path: Option<String>,

    #[frb(non_final)]
    pub network: Network,

    #[frb(non_final)]
    pub listening_addresses: Option<Vec<SocketAddress>>,

    #[frb(non_final)]
    pub default_cltv_expiry_delta: u32,

    #[frb(non_final)]
    pub onchain_wallet_sync_interval_secs: u64,

    #[frb(non_final)]
    pub wallet_sync_interval_secs: u64,

    #[frb(non_final)]
    pub fee_rate_cache_update_interval_secs: u64,

    pub trusted_peers_0conf: Vec<PublicKey>,

    pub probing_liquidity_limit_multiplier: u64,

    #[frb(non_final)]
    pub log_level: LogLevel,
    #[frb(non_final)]
    pub anchor_channels_config: Option<AnchorChannelsConfig>,
}
impl Default for AnchorChannelsConfig {
    fn default() -> Self {
        AnchorChannelsConfig {
            trusted_peers_no_reserve: vec![],
            per_channel_reserve_sats: 25000,
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            storage_dir_path: DEFAULT_STORAGE_DIR_PATH.to_string(),
            log_dir_path: None,
            network: DEFAULT_NETWORK,
            listening_addresses: None,
            default_cltv_expiry_delta: DEFAULT_CLTV_EXPIRY_DELTA,
            onchain_wallet_sync_interval_secs: DEFAULT_BDK_WALLET_SYNC_INTERVAL_SECS,
            wallet_sync_interval_secs: DEFAULT_LDK_WALLET_SYNC_INTERVAL_SECS,
            fee_rate_cache_update_interval_secs: DEFAULT_FEE_RATE_CACHE_UPDATE_INTERVAL_SECS,
            trusted_peers_0conf: vec![],
            probing_liquidity_limit_multiplier: 3,
            log_level: DEFAULT_LOG_LEVEL,
            anchor_channels_config: Some(Default::default()),
        }
    }
}

#[derive(Debug, Clone)]
pub enum ChainDataSourceConfig {
    Esplora(String),
}

#[derive(Debug, Clone)]
pub enum EntropySourceConfig {
    SeedFile(String),
    SeedBytes([u8; 64]),
    Bip39Mnemonic {
        mnemonic: LdkMnemonic,
        passphrase: Option<String>,
    },
}

#[derive(Debug, Clone)]
pub enum GossipSourceConfig {
    P2PNetwork,
    RapidGossipSync(String),
}

#[derive(Debug, Clone)]
pub struct LiquiditySourceConfig {

    pub lsps2_service: (SocketAddress, PublicKey, Option<String>),
}
impl From<ldk_node::BalanceDetails> for BalanceDetails {
    fn from(value: ldk_node::BalanceDetails) -> Self {
        Self {
            total_onchain_balance_sats: value.total_onchain_balance_sats,
            spendable_onchain_balance_sats: value.spendable_onchain_balance_sats,
            total_lightning_balance_sats: value.total_lightning_balance_sats,
            lightning_balances: value
                .lightning_balances
                .iter()
                .map(|e| e.clone().into())
                .collect(),
            pending_balances_from_channel_closures: value
                .pending_balances_from_channel_closures
                .iter()
                .map(|e| e.clone().into())
                .collect(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct BalanceDetails {

    pub total_onchain_balance_sats: u64,

    pub spendable_onchain_balance_sats: u64,

    pub total_lightning_balance_sats: u64,

    pub lightning_balances: Vec<LightningBalance>,

    pub pending_balances_from_channel_closures: Vec<PendingSweepBalance>,
}

#[derive(Debug, Clone)]
pub enum LightningBalance {

    ClaimableOnChannelClose {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,
    },

    ClaimableAwaitingConfirmations {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,

        confirmation_height: u32,
    },

    ContentiousClaimable {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,

        timeout_height: u32,

        payment_hash: PaymentHash,

        payment_preimage: PaymentPreimage,
    },

    MaybeTimeoutClaimableHTLC {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,

        claimable_height: u32,

        payment_hash: PaymentHash,
    },

    MaybePreimageClaimableHTLC {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,

        expiry_height: u32,

        payment_hash: PaymentHash,
    },

    CounterpartyRevokedOutputClaimable {

        channel_id: ChannelId,

        counterparty_node_id: PublicKey,

        amount_satoshis: u64,
    },
}
impl From<ldk_node::LightningBalance> for LightningBalance {
    fn from(value: ldk_node::LightningBalance) -> Self {
        match value {
            ldk_node::LightningBalance::ClaimableOnChannelClose {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                ..
            } => LightningBalance::ClaimableOnChannelClose {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
            },
            ldk_node::LightningBalance::ClaimableAwaitingConfirmations {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                confirmation_height,
                ..
            } => LightningBalance::ClaimableAwaitingConfirmations {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
                confirmation_height,
            },
            ldk_node::LightningBalance::ContentiousClaimable {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                timeout_height,
                payment_hash,
                payment_preimage,
                ..
            } => LightningBalance::ContentiousClaimable {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
                timeout_height,
                payment_hash: payment_hash.into(),
                payment_preimage: payment_preimage.into(),
            },
            ldk_node::LightningBalance::MaybeTimeoutClaimableHTLC {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                claimable_height,
                payment_hash,
                ..
            } => LightningBalance::MaybeTimeoutClaimableHTLC {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
                claimable_height,
                payment_hash: payment_hash.into(),
            },
            ldk_node::LightningBalance::MaybePreimageClaimableHTLC {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                expiry_height,
                payment_hash,
                ..
            } => LightningBalance::MaybePreimageClaimableHTLC {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
                expiry_height,
                payment_hash: payment_hash.into(),
            },
            ldk_node::LightningBalance::CounterpartyRevokedOutputClaimable {
                channel_id,
                counterparty_node_id,
                amount_satoshis,
                ..
            } => LightningBalance::CounterpartyRevokedOutputClaimable {
                channel_id: channel_id.into(),
                counterparty_node_id: counterparty_node_id.into(),
                amount_satoshis,
            },
        }
    }
}

#[derive(Debug, Clone)]
pub enum PendingSweepBalance {

    PendingBroadcast {

        channel_id: Option<ChannelId>,

        amount_satoshis: u64,
    },

    BroadcastAwaitingConfirmation {

        channel_id: Option<ChannelId>,

        latest_broadcast_height: u32,

        latest_spending_txid: Txid,

        amount_satoshis: u64,
    },

    AwaitingThresholdConfirmations {

        channel_id: Option<ChannelId>,

        latest_spending_txid: Txid,

        confirmation_hash: String,

        confirmation_height: u32,

        amount_satoshis: u64,
    },
}

impl From<ldk_node::PendingSweepBalance> for PendingSweepBalance {
    fn from(value: ldk_node::PendingSweepBalance) -> Self {
        match value {
            ldk_node::PendingSweepBalance::PendingBroadcast {
                channel_id,
                amount_satoshis,
                ..
            } => PendingSweepBalance::PendingBroadcast {
                channel_id: channel_id.map(|e| e.into()),
                amount_satoshis,
            },
            ldk_node::PendingSweepBalance::BroadcastAwaitingConfirmation {
                channel_id,
                latest_broadcast_height,
                latest_spending_txid,
                amount_satoshis,
                ..
            } => PendingSweepBalance::BroadcastAwaitingConfirmation {
                channel_id: channel_id.map(|e| e.into()),
                latest_broadcast_height,
                latest_spending_txid: latest_spending_txid.into(),
                amount_satoshis,
            },
            ldk_node::PendingSweepBalance::AwaitingThresholdConfirmations {
                channel_id,
                latest_spending_txid,
                confirmation_hash,
                confirmation_height,
                amount_satoshis,
                ..
            } => PendingSweepBalance::AwaitingThresholdConfirmations {
                channel_id: channel_id.map(|e| e.into()),
                latest_spending_txid: latest_spending_txid.into(),
                confirmation_hash: confirmation_hash.to_string(),
                confirmation_height,
                amount_satoshis,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BestBlock {

    pub block_hash: String,

    pub height: u32,
}

impl From<ldk_node::lightning::chain::BestBlock> for BestBlock {
    fn from(value: ldk_node::lightning::chain::BestBlock) -> Self {
        BestBlock {
            block_hash: value.block_hash.to_string(),
            height: value.height,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NodeStatus {

    pub is_running: bool,

    pub is_listening: bool,

    pub current_best_block: BestBlock,

    pub latest_wallet_sync_timestamp: Option<u64>,

    pub latest_onchain_wallet_sync_timestamp: Option<u64>,

    pub latest_fee_rate_cache_update_timestamp: Option<u64>,

    pub latest_rgs_snapshot_timestamp: Option<u64>,

    pub latest_node_announcement_broadcast_timestamp: Option<u64>,
}
impl From<ldk_node::NodeStatus> for NodeStatus {
    fn from(value: ldk_node::NodeStatus) -> Self {
        Self {
            is_running: value.is_running,

            is_listening: false,
            current_best_block: value.current_best_block.into(),

            latest_wallet_sync_timestamp: value.latest_lightning_wallet_sync_timestamp,
            latest_onchain_wallet_sync_timestamp: value.latest_onchain_wallet_sync_timestamp,
            latest_fee_rate_cache_update_timestamp: value.latest_fee_rate_cache_update_timestamp,
            latest_rgs_snapshot_timestamp: value.latest_rgs_snapshot_timestamp,
            latest_node_announcement_broadcast_timestamp: value
                .latest_node_announcement_broadcast_timestamp,
        }
    }
}

const DEFAULT_STORAGE_DIR_PATH: &str = "/tmp/ldk_node/";
const DEFAULT_NETWORK: Network = Network::Testnet;
const DEFAULT_CLTV_EXPIRY_DELTA: u32 = 144;
const DEFAULT_BDK_WALLET_SYNC_INTERVAL_SECS: u64 = 60;
const DEFAULT_LDK_WALLET_SYNC_INTERVAL_SECS: u64 = 20;
const DEFAULT_FEE_RATE_CACHE_UPDATE_INTERVAL_SECS: u64 = 60;
const DEFAULT_LOG_LEVEL: LogLevel = LogLevel::Debug;

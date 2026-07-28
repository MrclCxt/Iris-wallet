use ldk_node::{BuildError, NodeError};

#[derive(Debug, PartialEq)]
pub enum LdkNodeError {
    InvalidTxid,

    AlreadyRunning,

    NotRunning,

    OnchainTxCreationFailed,

    ConnectionFailed,

    InvoiceCreationFailed,

    PaymentSendingFailed,

    ProbeSendingFailed,

    ChannelCreationFailed,

    ChannelClosingFailed,

    ChannelConfigUpdateFailed,

    PersistenceFailed,

    WalletOperationFailed,

    OnchainTxSigningFailed,

    MessageSigningFailed,

    TxSyncFailed,

    GossipUpdateFailed,

    InvalidAddress,

    InvalidSocketAddress,

    InvalidPublicKey,

    InvalidSecretKey,

    InvalidPaymentHash,

    InvalidPaymentPreimage,

    InvalidPaymentSecret,

    InvalidAmount,

    InvalidInvoice,

    InvalidChannelId,

    InvalidNetwork,

    DuplicatePayment,

    InsufficientFunds,

    FeerateEstimationUpdateFailed,

    LiquidityRequestFailed,

    LiquiditySourceUnavailable,

    LiquidityFeeTooHigh,

    InvalidPaymentId,

    Decode(DecodeError),

    Bolt12Parse(Bolt12ParseError),

    InvoiceRequestCreationFailed,

    OfferCreationFailed,

    RefundCreationFailed,

    FeerateEstimationUpdateTimeout,

    WalletOperationTimeout,

    TxSyncTimeout,

    GossipUpdateTimeout,

    InvalidOfferId,

    InvalidNodeId,

    InvalidOffer,

    InvalidRefund,

    UnsupportedCurrency,
}
#[allow(dead_code)]
#[derive(Debug)]
pub enum LdkBuilderError {
    SocketAddressParseError,

    InvalidSeedBytes,

    InvalidSeedFile,

    InvalidSystemTime,

    InvalidChannelMonitor,

    InvalidListeningAddress,

    ReadFailed,

    WriteFailed,

    StoragePathAccessFailed,

    KVStoreSetupFailed,

    WalletSetupFailed,

    LoggerSetupFailed,

    InvalidPublicKey,
}

impl From<NodeError> for LdkNodeError {
    fn from(value: NodeError) -> Self {
        match value {
            NodeError::AlreadyRunning => LdkNodeError::AlreadyRunning,
            NodeError::NotRunning => LdkNodeError::NotRunning,
            NodeError::OnchainTxCreationFailed => LdkNodeError::OnchainTxCreationFailed,
            NodeError::ConnectionFailed => LdkNodeError::ConnectionFailed,
            NodeError::InvoiceCreationFailed => LdkNodeError::InvoiceCreationFailed,
            NodeError::PaymentSendingFailed => LdkNodeError::PaymentSendingFailed,
            NodeError::ProbeSendingFailed => LdkNodeError::ProbeSendingFailed,
            NodeError::ChannelCreationFailed => LdkNodeError::ChannelCreationFailed,
            NodeError::ChannelClosingFailed => LdkNodeError::ChannelClosingFailed,
            NodeError::ChannelConfigUpdateFailed => LdkNodeError::ChannelConfigUpdateFailed,
            NodeError::PersistenceFailed => LdkNodeError::PersistenceFailed,
            NodeError::WalletOperationFailed => LdkNodeError::WalletOperationFailed,
            NodeError::OnchainTxSigningFailed => LdkNodeError::OnchainTxSigningFailed,
            NodeError::TxSyncFailed => LdkNodeError::TxSyncFailed,
            NodeError::GossipUpdateFailed => LdkNodeError::GossipUpdateFailed,
            NodeError::InvalidAddress => LdkNodeError::InvalidAddress,
            NodeError::InvalidSocketAddress => LdkNodeError::InvalidSocketAddress,
            NodeError::InvalidPublicKey => LdkNodeError::InvalidPublicKey,
            NodeError::InvalidSecretKey => LdkNodeError::InvalidSecretKey,
            NodeError::InvalidPaymentHash => LdkNodeError::InvalidPaymentHash,
            NodeError::InvalidPaymentPreimage => LdkNodeError::InvalidPaymentPreimage,
            NodeError::InvalidPaymentSecret => LdkNodeError::InvalidPaymentSecret,
            NodeError::InvalidAmount => LdkNodeError::InvalidAmount,
            NodeError::InvalidInvoice => LdkNodeError::InvalidInvoice,
            NodeError::InvalidChannelId => LdkNodeError::InvalidChannelId,
            NodeError::InvalidNetwork => LdkNodeError::InvalidNetwork,
            NodeError::DuplicatePayment => LdkNodeError::DuplicatePayment,
            NodeError::InsufficientFunds => LdkNodeError::InsufficientFunds,
            NodeError::FeerateEstimationUpdateFailed => LdkNodeError::FeerateEstimationUpdateFailed,
            NodeError::LiquidityRequestFailed => LdkNodeError::LiquidityRequestFailed,
            NodeError::LiquiditySourceUnavailable => LdkNodeError::LiquiditySourceUnavailable,
            NodeError::LiquidityFeeTooHigh => LdkNodeError::LiquidityFeeTooHigh,
            NodeError::InvalidPaymentId => LdkNodeError::InvalidPaymentId,
            NodeError::InvoiceRequestCreationFailed => LdkNodeError::InvoiceRequestCreationFailed,
            NodeError::OfferCreationFailed => LdkNodeError::OfferCreationFailed,
            NodeError::RefundCreationFailed => LdkNodeError::RefundCreationFailed,
            NodeError::FeerateEstimationUpdateTimeout => {
                LdkNodeError::FeerateEstimationUpdateTimeout
            }
            NodeError::WalletOperationTimeout => LdkNodeError::WalletOperationTimeout,
            NodeError::TxSyncTimeout => LdkNodeError::TxSyncTimeout,
            NodeError::GossipUpdateTimeout => LdkNodeError::GossipUpdateTimeout,
            NodeError::InvalidOfferId => LdkNodeError::InvalidOfferId,
            NodeError::InvalidNodeId => LdkNodeError::InvalidNodeId,
            NodeError::InvalidOffer => LdkNodeError::InvalidOffer,
            NodeError::InvalidRefund => LdkNodeError::InvalidRefund,
            NodeError::UnsupportedCurrency => LdkNodeError::UnsupportedCurrency,

            _ => LdkNodeError::PersistenceFailed,
        }
    }
}
impl From<BuildError> for LdkBuilderError {
    fn from(value: BuildError) -> Self {
        match value {
            BuildError::InvalidSeedBytes => LdkBuilderError::InvalidSeedBytes,
            BuildError::InvalidSeedFile => LdkBuilderError::InvalidSeedFile,
            BuildError::InvalidSystemTime => LdkBuilderError::InvalidSystemTime,
            BuildError::ReadFailed => LdkBuilderError::ReadFailed,
            BuildError::WriteFailed => LdkBuilderError::WriteFailed,
            BuildError::StoragePathAccessFailed => LdkBuilderError::StoragePathAccessFailed,
            BuildError::WalletSetupFailed => LdkBuilderError::WalletSetupFailed,
            BuildError::LoggerSetupFailed => LdkBuilderError::LoggerSetupFailed,
            BuildError::InvalidChannelMonitor => LdkBuilderError::InvalidChannelMonitor,
            BuildError::KVStoreSetupFailed => LdkBuilderError::KVStoreSetupFailed,
            BuildError::InvalidListeningAddresses => LdkBuilderError::InvalidListeningAddress,

            _ => LdkBuilderError::WalletSetupFailed,
        }
    }
}

impl From<ldk_node::bip39::Error> for LdkBuilderError {
    fn from(value: ldk_node::bip39::Error) -> Self {
        match value {
            ldk_node::bip39::Error::BadWordCount(_) => LdkBuilderError::InvalidSeedBytes,
            ldk_node::bip39::Error::UnknownWord(_) => LdkBuilderError::InvalidSeedBytes,
            ldk_node::bip39::Error::BadEntropyBitCount(_) => LdkBuilderError::InvalidSeedBytes,
            ldk_node::bip39::Error::InvalidChecksum => LdkBuilderError::InvalidSeedBytes,
            ldk_node::bip39::Error::AmbiguousLanguages(_) => LdkBuilderError::InvalidSeedBytes,
        }
    }
}
impl From<ldk_node::lightning::ln::msgs::DecodeError> for LdkNodeError {
    fn from(value: ldk_node::lightning::ln::msgs::DecodeError) -> Self {
        LdkNodeError::Decode(value.into())
    }
}
impl From<ldk_node::lightning::ln::msgs::DecodeError> for DecodeError {
    fn from(e: ldk_node::lightning::ln::msgs::DecodeError) -> Self {
        match e {
            ldk_node::lightning::ln::msgs::DecodeError::UnknownVersion => {
                DecodeError::UnknownVersion
            }
            ldk_node::lightning::ln::msgs::DecodeError::UnknownRequiredFeature => {
                DecodeError::UnknownRequiredFeature
            }
            ldk_node::lightning::ln::msgs::DecodeError::InvalidValue => DecodeError::InvalidValue,
            ldk_node::lightning::ln::msgs::DecodeError::ShortRead => DecodeError::ShortRead,
            ldk_node::lightning::ln::msgs::DecodeError::BadLengthDescriptor => {
                DecodeError::BadLengthDescriptor
            }
            ldk_node::lightning::ln::msgs::DecodeError::Io(e) => DecodeError::Io(format!("{:?}", e)),
            ldk_node::lightning::ln::msgs::DecodeError::UnsupportedCompression => {
                DecodeError::UnsupportedCompression
            }
            ldk_node::lightning::ln::msgs::DecodeError::DangerousValue => {
                DecodeError::DangerousValue
            }
        }
    }
}
#[derive(Debug, PartialEq)]
pub enum DecodeError {
    UnknownVersion,
    UnknownRequiredFeature,
    InvalidValue,
    ShortRead,
    BadLengthDescriptor,
    Io(String),
    UnsupportedCompression,
    DangerousValue,
}

#[derive(Debug, PartialEq)]
pub enum Bolt12ParseError {
    InvalidContinuation,
    InvalidBech32Hrp,
    Bech32(String),
    Decode(DecodeError),
    InvalidSemantics(String),
    InvalidSignature(String),
}
impl From<ldk_node::lightning::offers::parse::Bolt12ParseError> for LdkNodeError {
    fn from(value: ldk_node::lightning::offers::parse::Bolt12ParseError) -> Self {
        match value {
            ldk_node::lightning::offers::parse::Bolt12ParseError::InvalidContinuation => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::InvalidContinuation)
            }
            ldk_node::lightning::offers::parse::Bolt12ParseError::InvalidBech32Hrp => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::InvalidBech32Hrp)
            }
            ldk_node::lightning::offers::parse::Bolt12ParseError::Bech32(e) => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::Bech32(e.to_string()))
            }
            ldk_node::lightning::offers::parse::Bolt12ParseError::Decode(e) => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::Decode(e.into()))
            }
            ldk_node::lightning::offers::parse::Bolt12ParseError::InvalidSemantics(e) => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::InvalidSemantics(format!("{:?}", e)))
            }
            ldk_node::lightning::offers::parse::Bolt12ParseError::InvalidSignature(e) => {
                LdkNodeError::Bolt12Parse(Bolt12ParseError::InvalidSignature(e.to_string()))
            }

            _ => LdkNodeError::Bolt12Parse(Bolt12ParseError::InvalidBech32Hrp),
        }
    }
}

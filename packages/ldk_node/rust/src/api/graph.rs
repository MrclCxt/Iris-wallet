use crate::api::types::SocketAddress;
use crate::frb_generated::RustOpaque;
use crate::utils::error::LdkNodeError;
use ldk_node::lightning::util::ser::Writeable;

pub struct NodeId {
    pub compressed: Vec<u8>,
}

impl From<ldk_node::lightning::routing::gossip::NodeId> for NodeId {
    fn from(value: ldk_node::lightning::routing::gossip::NodeId) -> Self {
        Self {
            compressed: value.encode(),
        }
    }
}
impl TryFrom<NodeId> for ldk_node::lightning::routing::gossip::NodeId {
    type Error = LdkNodeError;

    fn try_from(value: NodeId) -> Result<Self, Self::Error> {
        ldk_node::lightning::routing::gossip::NodeId::from_slice(value.compressed.as_slice())
            .map_err(|e| e.into())
    }
}

pub struct RoutingFees {

    pub base_msat: u32,

    pub proportional_millionths: u32,
}
impl From<ldk_node::lightning::routing::gossip::RoutingFees> for RoutingFees {
    fn from(value: ldk_node::lightning_invoice::RoutingFees) -> Self {
        Self {
            base_msat: value.base_msat,
            proportional_millionths: value.proportional_millionths,
        }
    }
}
pub struct ChannelUpdateInfo {

    pub last_update: u32,

    pub enabled: bool,

    pub cltv_expiry_delta: u16,

    pub htlc_minimum_msat: u64,

    pub htlc_maximum_msat: u64,

    pub fees: RoutingFees,
}

pub struct ChannelInfo {

    pub node_one: NodeId,

    pub one_to_two: Option<ChannelUpdateInfo>,

    pub node_two: NodeId,

    pub two_to_one: Option<ChannelUpdateInfo>,

    pub capacity_sats: Option<u64>,
}
impl From<ldk_node::lightning::routing::gossip::ChannelInfo> for ChannelInfo {
    fn from(value: ldk_node::lightning::routing::gossip::ChannelInfo) -> Self {
        Self {
            node_one: value.node_one.into(),
            one_to_two: value.one_to_two.map(|e| e.into()),
            node_two: value.node_two.into(),
            two_to_one: value.two_to_one.map(|e| e.into()),
            capacity_sats: value.capacity_sats,
        }
    }
}

impl From<ldk_node::lightning::routing::gossip::ChannelUpdateInfo> for ChannelUpdateInfo {
    fn from(value: ldk_node::lightning::routing::gossip::ChannelUpdateInfo) -> Self {
        ChannelUpdateInfo {
            last_update: value.last_update,
            enabled: value.enabled,
            cltv_expiry_delta: value.cltv_expiry_delta,
            htlc_minimum_msat: value.htlc_minimum_msat,
            htlc_maximum_msat: value.htlc_maximum_msat,
            fees: value.fees.into(),
        }
    }
}

pub struct NodeInfo {
    pub channels: Vec<u64>,

    pub announcement_info: Option<NodeAnnouncementInfo>,
}

impl From<ldk_node::lightning::routing::gossip::NodeInfo> for NodeInfo {
    fn from(value: ldk_node::lightning::routing::gossip::NodeInfo) -> Self {
        NodeInfo {
            channels: value.channels,
            announcement_info: value.announcement_info.map(|e| e.into()),
        }
    }
}
pub struct NodeAnnouncementInfo {

    pub last_update: u32,

    pub alias: String,

    pub addresses: Vec<SocketAddress>,
}

impl From<ldk_node::lightning::routing::gossip::NodeAnnouncementInfo> for NodeAnnouncementInfo {
    fn from(value: ldk_node::lightning::routing::gossip::NodeAnnouncementInfo) -> Self {
        Self {
            last_update: value.last_update(),
            alias: value.alias().to_string(),
            addresses: value
                .addresses()
                .iter()
                .map(|e| e.to_owned().into())
                .collect(),
        }
    }
}
pub struct LdkNetworkGraph {
    pub ptr: RustOpaque<ldk_node::graph::NetworkGraph>,
}
impl From<ldk_node::graph::NetworkGraph> for LdkNetworkGraph {
    fn from(value: ldk_node::graph::NetworkGraph) -> Self {
        LdkNetworkGraph {
            ptr: RustOpaque::new(value),
        }
    }
}

impl LdkNetworkGraph {

    pub fn list_channels(&self) -> Vec<u64> {
        self.ptr.list_channels()
    }

    pub fn channel(&self, short_channel_id: u64) -> Option<ChannelInfo> {
        self.ptr.channel(short_channel_id).map(|e| e.into())
    }

    pub fn list_nodes(&self) -> Vec<NodeId> {
        self.ptr
            .list_nodes()
            .iter()
            .map(|e| e.to_owned().into())
            .collect()
    }

    pub fn node(&self, node_id: NodeId) -> Result<Option<NodeInfo>, LdkNodeError> {
        Ok(self.ptr.node(&(node_id.try_into()?)).map(|e| e.into()))
    }
}

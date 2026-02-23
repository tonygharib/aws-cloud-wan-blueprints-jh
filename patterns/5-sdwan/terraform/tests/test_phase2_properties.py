"""
Property tests for Phase2 Lambda VPN/BGP script builder.
Feature: lambda-stepfunctions-orchestration

Validates: Requirements 3.3, 3.4, 3.5, 3.6, 3.7, 3.11
"""

import sys
import os
import ipaddress

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import phase2_handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase2_handler import (
    build_vpn_bgp_script,
    TUNNELS,
    ROUTER_CONFIG,
    get_tunnel_info,
)
from ssm_utils import get_region_for_instance

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

ROUTER_NAMES = list(ROUTER_CONFIG.keys())

router_name_st = st.sampled_from(ROUTER_NAMES)
tunnel_st = st.sampled_from(TUNNELS)

# Fake but structurally valid instance configs for script generation
FAKE_INSTANCE_CONFIGS = {
    "nv-sdwan": {
        "instance_id": "i-nv-sdwan",
        "outside_eip": "54.1.1.1",
        "outside_private_ip": "10.201.2.10",
        "region": "us-east-1",
    },
    "nv-branch1": {
        "instance_id": "i-nv-branch1",
        "outside_eip": "54.2.2.2",
        "outside_private_ip": "10.201.2.20",
        "region": "us-east-1",
    },
    "fra-sdwan": {
        "instance_id": "i-fra-sdwan",
        "outside_eip": "3.1.1.1",
        "outside_private_ip": "10.202.2.10",
        "region": "eu-central-1",
    },
    "fra-branch1": {
        "instance_id": "i-fra-branch1",
        "outside_eip": "3.2.2.2",
        "outside_private_ip": "10.202.2.20",
        "region": "eu-central-1",
    },
}


# =============================================================================
# Property 5: IPsec address field correctness
# =============================================================================
# **Validates: Requirements 3.3**


@settings(max_examples=100)
@given(router_name=router_name_st)
def test_property5_ipsec_address_field_correctness(router_name):
    """
    Property 5: IPsec address field correctness.

    *For any* tunnel in the VPN topology and for each router in that tunnel,
    the generated vbash script SHALL use the router's own outside private IP
    as local-address, the peer's outside EIP as the peer address, and the
    peer's outside private IP as authentication remote-id.

    **Validates: Requirements 3.3**
    """
    script = build_vpn_bgp_script(router_name, FAKE_INSTANCE_CONFIGS)
    tunnel_infos = get_tunnel_info(router_name)

    my_private_ip = FAKE_INSTANCE_CONFIGS[router_name]["outside_private_ip"]

    for t in tunnel_infos:
        peer_name = t["peer_name"]
        peer_eip = FAKE_INSTANCE_CONFIGS[peer_name]["outside_eip"]
        peer_private_ip = FAKE_INSTANCE_CONFIGS[peer_name]["outside_private_ip"]

        # local-address must be the router's own outside private IP
        assert f"local-address {my_private_ip}" in script, (
            f"local-address should be {my_private_ip} for {router_name}"
        )

        # peer address must be the peer's outside EIP
        assert f"peer {peer_eip}" in script, (
            f"peer address should be {peer_eip} (peer {peer_name} EIP)"
        )

        # authentication remote-id must be the peer's outside private IP
        assert f"remote-id {peer_private_ip}" in script, (
            f"remote-id should be {peer_private_ip} (peer {peer_name} private IP)"
        )


# =============================================================================
# Property 6: IPsec encryption algorithm
# =============================================================================
# **Validates: Requirements 3.4**


@settings(max_examples=100)
@given(router_name=router_name_st)
def test_property6_ipsec_encryption_algorithm(router_name):
    """
    Property 6: IPsec encryption algorithm.

    *For any* generated VPN configuration script, the IKE and ESP proposal
    encryption SHALL be "aes256" and SHALL NOT contain "aes256gcm128".

    **Validates: Requirements 3.4**
    """
    script = build_vpn_bgp_script(router_name, FAKE_INSTANCE_CONFIGS)

    # Must contain aes256 encryption for both IKE and ESP
    assert "encryption aes256" in script, (
        f"Script for {router_name} must specify 'encryption aes256'"
    )

    # Must NOT contain aes256gcm128
    assert "aes256gcm128" not in script, (
        f"Script for {router_name} must NOT contain 'aes256gcm128'"
    )


# =============================================================================
# Property 7: Tunnel topology validity
# =============================================================================
# **Validates: Requirements 3.5, 3.11**


@settings(max_examples=100)
@given(tunnel=tunnel_st)
def test_property7_tunnel_topology_validity(tunnel):
    """
    Property 7: Tunnel topology validity.

    *For any* tunnel in the VPN topology, the two VTI addresses SHALL be
    consecutive addresses within the same /30 subnet, and both routers in
    the tunnel SHALL be in the same AWS region (intra-region only).

    **Validates: Requirements 3.5, 3.11**
    """
    addr_a = ipaddress.ip_interface(tunnel["vti_a"]["addr"])
    addr_b = ipaddress.ip_interface(tunnel["vti_b"]["addr"])

    # Both must be /30
    assert addr_a.network.prefixlen == 30, (
        f"VTI A address must be /30, got /{addr_a.network.prefixlen}"
    )
    assert addr_b.network.prefixlen == 30, (
        f"VTI B address must be /30, got /{addr_b.network.prefixlen}"
    )

    # Both must be in the same /30 subnet
    assert addr_a.network == addr_b.network, (
        f"VTI addresses must share the same /30 subnet: "
        f"{addr_a.network} vs {addr_b.network}"
    )

    # The two host addresses must be the two usable IPs in the /30
    hosts = list(addr_a.network.hosts())
    assert addr_a.ip in hosts and addr_b.ip in hosts, (
        f"VTI addresses must be the two usable hosts in {addr_a.network}"
    )

    # Intra-region only: both routers must be in the same region
    region_a = get_region_for_instance(tunnel["router_a"])
    region_b = get_region_for_instance(tunnel["router_b"])
    assert region_a == region_b, (
        f"Tunnel routers must be in the same region: "
        f"{tunnel['router_a']}={region_a}, {tunnel['router_b']}={region_b}"
    )


# =============================================================================
# Property 8: Per-router configuration consistency
# =============================================================================
# **Validates: Requirements 3.6, 3.7**


@settings(max_examples=100)
@given(router_name=router_name_st)
def test_property8_per_router_configuration_consistency(router_name):
    """
    Property 8: Per-router configuration consistency.

    *For any* router in the topology, the BGP ASN SHALL be 65001 if the
    router role is "sdwan" and 65002 if the role is "branch", and all
    loopback /32 addresses SHALL be pairwise distinct across all routers.

    **Validates: Requirements 3.6, 3.7**
    """
    cfg = ROUTER_CONFIG[router_name]

    # ASN must match role
    if cfg["role"] == "sdwan":
        assert cfg["asn"] == 65001, (
            f"sdwan router {router_name} must have ASN 65001, got {cfg['asn']}"
        )
    elif cfg["role"] == "branch":
        assert cfg["asn"] == 65002, (
            f"branch router {router_name} must have ASN 65002, got {cfg['asn']}"
        )

    # All loopback addresses must be pairwise distinct
    loopbacks = [ROUTER_CONFIG[r]["loopback"] for r in ROUTER_CONFIG]
    assert len(loopbacks) == len(set(loopbacks)), (
        f"Loopback addresses must be unique, got: {loopbacks}"
    )

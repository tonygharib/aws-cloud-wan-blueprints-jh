"""
Property tests for Phase 3 Lambda — Cloud WAN BGP Configuration.
Feature: stepfunctions-phase-reorder

Validates: Requirements 6.1, 6.2, 6.3, 6.4
"""

import sys
import os

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import phase3_handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase3_handler import (
    build_cloudwan_bgp_script,
    SDWAN_ROUTERS,
    SDWAN_BGP_ASN,
    PRIVATE_SUBNET_GW,
)

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Valid IPv4 octets for generating Cloud WAN peer IPs
ipv4_octet = st.integers(min_value=1, max_value=254)

cloudwan_peer_ip_st = st.tuples(ipv4_octet, ipv4_octet, ipv4_octet, ipv4_octet).map(
    lambda t: f"{t[0]}.{t[1]}.{t[2]}.{t[3]}"
)

# Valid ASN range for Cloud WAN (private 2-byte ASN range)
cloudwan_asn_st = st.integers(min_value=64512, max_value=65534).map(str)

sdwan_router_st = st.sampled_from(SDWAN_ROUTERS)

# Whether to include a second peer IP (redundancy)
include_peer2_st = st.booleans()


def _make_configs(router_name, peer_ip1, peer_ip2, cloudwan_asn):
    """Build a minimal configs dict for build_cloudwan_bgp_script()."""
    cfg = {
        router_name: {
            "instance_id": "i-fake",
            "region": "us-east-1",
            "cloudwan_peer_ip1": peer_ip1,
            "cloudwan_asn": cloudwan_asn,
        }
    }
    if peer_ip2:
        cfg[router_name]["cloudwan_peer_ip2"] = peer_ip2
    return cfg


# =============================================================================
# Property 1: Cloud WAN BGP script generation preserves configuration logic
# =============================================================================
# **Validates: Requirements 1.7**


@settings(max_examples=100)
@given(
    router_name=sdwan_router_st,
    peer_ip1=cloudwan_peer_ip_st,
    peer_ip2=cloudwan_peer_ip_st,
    cloudwan_asn=cloudwan_asn_st,
    include_peer2=include_peer2_st,
)
def test_property1_cloudwan_bgp_script_generation(
    router_name, peer_ip1, peer_ip2, cloudwan_asn, include_peer2
):
    """
    Feature: stepfunctions-phase-reorder, Property 1: Cloud WAN BGP script
    generation preserves configuration logic.

    *For any* valid Cloud WAN peer IP pair and ASN value, the
    build_cloudwan_bgp_script() function SHALL produce a vbash script
    containing: (a) a static route to each peer IP via the correct private
    subnet gateway, (b) a BGP neighbor entry for each peer IP with the
    correct remote ASN, and (c) ebgp-multihop 4 for each neighbor.

    **Validates: Requirements 1.7**
    """
    actual_peer2 = peer_ip2 if include_peer2 else None
    configs = _make_configs(router_name, peer_ip1, actual_peer2, cloudwan_asn)

    script = build_cloudwan_bgp_script(router_name, configs)
    gw = PRIVATE_SUBNET_GW[router_name]

    # (a) Static route to peer_ip1 via correct gateway
    assert f"route {peer_ip1}/32 next-hop {gw}" in script, (
        f"Script must contain static route for {peer_ip1} via {gw}"
    )

    # (b) BGP neighbor for peer_ip1 with correct remote ASN
    assert f"neighbor {peer_ip1} remote-as {cloudwan_asn}" in script, (
        f"Script must configure BGP neighbor {peer_ip1} with ASN {cloudwan_asn}"
    )

    # (c) ebgp-multihop 4 for peer_ip1
    assert f"neighbor {peer_ip1} ebgp-multihop 4" in script, (
        f"Script must set ebgp-multihop 4 for neighbor {peer_ip1}"
    )

    if include_peer2:
        # (a) Static route to peer_ip2
        assert f"route {peer_ip2}/32 next-hop {gw}" in script, (
            f"Script must contain static route for {peer_ip2} via {gw}"
        )

        # (b) BGP neighbor for peer_ip2
        assert f"neighbor {peer_ip2} remote-as {cloudwan_asn}" in script, (
            f"Script must configure BGP neighbor {peer_ip2} with ASN {cloudwan_asn}"
        )

        # (c) ebgp-multihop 4 for peer_ip2
        assert f"neighbor {peer_ip2} ebgp-multihop 4" in script, (
            f"Script must set ebgp-multihop 4 for neighbor {peer_ip2}"
        )

    # Script must use the correct local ASN
    assert f"bgp {SDWAN_BGP_ASN}" in script, (
        f"Script must use local ASN {SDWAN_BGP_ASN}"
    )

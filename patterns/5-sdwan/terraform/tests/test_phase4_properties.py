"""
Property tests for Phase 4 Cloud WAN BGP vbash script generation.
Feature: cloudwan-sdwan-bgp-integration

Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.7
"""

import sys
import os

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import phase4_cloudwan_bgp
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase4_cloudwan_bgp import (
    build_cloudwan_bgp_script,
    SDWAN_BGP_ASN,
    CLOUDWAN_ASN,
    PRIVATE_SUBNET_GW,
)

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

ROUTER_NAMES = ["nv-sdwan", "fra-sdwan"]

router_name_st = st.sampled_from(ROUTER_NAMES)

# Generate valid link-local IPs in the 169.254.x.x range for inside CIDRs
link_local_octet3 = st.integers(min_value=0, max_value=255)
# Use .1 for cloud WAN peer and .2 for appliance (matching /29 allocation)
cloudwan_peer_ip_st = st.builds(
    lambda o3: f"169.254.{o3}.1",
    link_local_octet3,
)
appliance_ip_st = st.builds(
    lambda o3: f"169.254.{o3}.2",
    link_local_octet3,
)

# Private subnet gateways — realistic 10.x.y.1 addresses
private_gw_st = st.builds(
    lambda b, c: f"10.{b}.{c}.1",
    st.integers(min_value=0, max_value=255),
    st.integers(min_value=0, max_value=255),
)


# =============================================================================
# Property 3: VyOS tunnel-less connectivity setup
# =============================================================================
# **Validates: Requirements 5.1, 5.2**


@settings(max_examples=100)
@given(
    router_name=router_name_st,
    cloudwan_peer_ip=cloudwan_peer_ip_st,
    appliance_ip=appliance_ip_st,
    private_gw=private_gw_st,
)
def test_property3_vyos_tunnelless_connectivity_setup(
    router_name, cloudwan_peer_ip, appliance_ip, private_gw
):
    """
    Property 3: VyOS tunnel-less connectivity setup.

    *For any* SDWAN router targeted by the configuration script, the generated
    vbash script SHALL contain: (a) a dummy interface (dum0) with the appliance's
    inside address from the Connect Peer CIDR, and (b) a static route for the
    Cloud WAN peer IP with next-hop set to the private subnet gateway.

    **Validates: Requirements 5.1, 5.2**
    """
    script = build_cloudwan_bgp_script(
        router_name, cloudwan_peer_ip, appliance_ip, private_gw
    )

    # (a) Dummy interface dum0 with appliance inside address
    assert f"set interfaces dummy dum0 address {appliance_ip}/32" in script, (
        f"Script must configure dum0 with {appliance_ip}/32"
    )

    # (b) Static route to Cloud WAN peer via private subnet gateway
    assert (
        f"set protocols static route {cloudwan_peer_ip}/32 next-hop {private_gw}"
        in script
    ), (
        f"Script must add static route for {cloudwan_peer_ip}/32 via {private_gw}"
    )


# =============================================================================
# Property 4: VyOS BGP neighbor configuration correctness
# =============================================================================
# **Validates: Requirements 5.3, 5.4, 5.5**


@settings(max_examples=100)
@given(
    router_name=router_name_st,
    cloudwan_peer_ip=cloudwan_peer_ip_st,
    appliance_ip=appliance_ip_st,
)
def test_property4_vyos_bgp_neighbor_configuration_correctness(
    router_name, cloudwan_peer_ip, appliance_ip
):
    """
    Property 4: VyOS BGP neighbor configuration correctness.

    *For any* SDWAN router targeted by the configuration script, the generated
    vbash script SHALL configure a BGP neighbor with: (a) the Cloud WAN peer IP
    as the neighbor address, (b) the Core Network ASN (64512) as remote-as, and
    (c) the appliance inside address as update-source.

    **Validates: Requirements 5.3, 5.4, 5.5**
    """
    script = build_cloudwan_bgp_script(router_name, cloudwan_peer_ip, appliance_ip)

    # (a) BGP neighbor with Cloud WAN peer IP and correct ASN
    assert (
        f"set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} remote-as {CLOUDWAN_ASN}"
        in script
    ), (
        f"Script must configure BGP neighbor {cloudwan_peer_ip} with remote-as {CLOUDWAN_ASN}"
    )

    # (b) Verify the Core Network ASN is 64512
    assert CLOUDWAN_ASN == 64512, "Core Network ASN must be 64512"

    # (c) Update-source set to appliance inside address
    assert (
        f"set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} update-source {appliance_ip}"
        in script
    ), (
        f"Script must set update-source to {appliance_ip}"
    )


# =============================================================================
# Property 5: Existing BGP configuration preservation
# =============================================================================
# **Validates: Requirements 5.7**


@settings(max_examples=100)
@given(
    router_name=router_name_st,
    cloudwan_peer_ip=cloudwan_peer_ip_st,
    appliance_ip=appliance_ip_st,
)
def test_property5_existing_bgp_configuration_preservation(
    router_name, cloudwan_peer_ip, appliance_ip
):
    """
    Property 5: Existing BGP configuration preservation.

    *For any* SDWAN router targeted by the configuration script, the generated
    vbash script SHALL NOT contain any "delete" commands that would remove
    existing BGP neighbors, VTI interfaces, loopback addresses, or IPsec VPN
    configuration.

    **Validates: Requirements 5.7**
    """
    script = build_cloudwan_bgp_script(router_name, cloudwan_peer_ip, appliance_ip)

    # Script must not contain any delete commands
    for line in script.splitlines():
        stripped = line.strip()
        # Skip empty lines and comments
        if not stripped or stripped.startswith("#"):
            continue
        assert not stripped.startswith("delete "), (
            f"Script must not contain delete commands, found: '{stripped}'"
        )

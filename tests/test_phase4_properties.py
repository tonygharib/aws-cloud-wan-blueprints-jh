"""
Property tests for Phase 4 Lambda — Verification via SSM Run Command.
Feature: stepfunctions-phase-reorder

Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
"""

import json
import sys
import os
from unittest.mock import MagicMock, patch

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import handlers
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase4_handler import (
    build_verify_command,
    parse_verify_output,
    get_ping_targets,
    persist_results_to_ssm,
    TUNNELS,
    ROUTERS,
    SDWAN_ROUTERS,
)

# Phase 2 tunnel topology — source of truth for VTI addresses
from phase2_handler import TUNNELS as PHASE2_TUNNELS

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

sdwan_router_st = st.sampled_from(SDWAN_ROUTERS)
all_router_st = st.sampled_from(ROUTERS)
random_stdout_st = st.text(min_size=0, max_size=500)

# Valid IPv4 for Cloud WAN peer IPs in configs
ipv4_octet = st.integers(min_value=1, max_value=254)
cloudwan_peer_ip_st = st.tuples(ipv4_octet, ipv4_octet, ipv4_octet, ipv4_octet).map(
    lambda t: f"{t[0]}.{t[1]}.{t[2]}.{t[3]}"
)


def _make_configs_with_cloudwan(router_name, peer_ip1, peer_ip2=None):
    """Build a minimal configs dict with Cloud WAN peer IPs for verification."""
    cfg = {
        router_name: {
            "instance_id": "i-fake",
            "region": "us-east-1",
            "cloudwan_peer_ip1": peer_ip1,
        }
    }
    if peer_ip2:
        cfg[router_name]["cloudwan_peer_ip2"] = peer_ip2
    return cfg


# =============================================================================
# Property 2: SDWAN routers include Cloud WAN BGP check in verification command
# =============================================================================
# **Validates: Requirements 4.1, 4.2, 4.5**


@settings(max_examples=100)
@given(
    router_name=sdwan_router_st,
    peer_ip1=cloudwan_peer_ip_st,
    peer_ip2=cloudwan_peer_ip_st,
)
def test_property2_sdwan_routers_include_cloudwan_bgp_check(
    router_name, peer_ip1, peer_ip2
):
    """
    Feature: stepfunctions-phase-reorder, Property 2: SDWAN routers include
    Cloud WAN BGP check in verification command.

    *For any* router in {nv-sdwan, fra-sdwan}, the build_verify_command()
    function SHALL produce a shell script that includes a 'show ip bgp
    neighbors' command for Cloud WAN peer verification, in addition to the
    existing IPsec, BGP summary, interfaces, and ping checks.

    **Validates: Requirements 4.1, 4.2, 4.5**
    """
    configs = _make_configs_with_cloudwan(router_name, peer_ip1, peer_ip2)
    cmd = build_verify_command(router_name, configs=configs)

    # Must contain existing checks
    assert "show vpn ipsec sa" in cmd, "Must include IPsec SA check"
    assert "show ip bgp summary" in cmd, "Must include BGP summary check"
    assert "show interfaces" in cmd, "Must include interfaces check"

    # Must contain Cloud WAN BGP neighbor checks for both peer IPs
    assert f"show ip bgp neighbors {peer_ip1}" in cmd, (
        f"Must include Cloud WAN BGP check for peer {peer_ip1}"
    )
    assert f"show ip bgp neighbors {peer_ip2}" in cmd, (
        f"Must include Cloud WAN BGP check for peer {peer_ip2}"
    )

    # Must contain ping tests
    assert "Ping" in cmd or "ping" in cmd, "Must include ping tests"


# =============================================================================
# Property 3: Router-type-dependent cloudwan_bgp field in verification details
# =============================================================================
# **Validates: Requirements 4.3, 4.4**


@settings(max_examples=100)
@given(router_name=all_router_st, stdout=random_stdout_st)
def test_property3_router_type_dependent_cloudwan_bgp_field(router_name, stdout):
    """
    Feature: stepfunctions-phase-reorder, Property 3: Router-type-dependent
    cloudwan_bgp field in verification details.

    *For any* router and any verification output string, the
    parse_verify_output() function SHALL set cloudwan_bgp to "ok" or "fail"
    when the router is an SDWAN router (nv-sdwan, fra-sdwan), and to
    "not_applicable" when the router is a branch router (nv-branch1,
    fra-branch1).

    **Validates: Requirements 4.3, 4.4**
    """
    details = parse_verify_output(stdout, router_name)

    assert "cloudwan_bgp" in details, (
        f"Verification details for {router_name} must include cloudwan_bgp key"
    )

    if router_name in SDWAN_ROUTERS:
        assert details["cloudwan_bgp"] in ("ok", "fail"), (
            f"SDWAN router {router_name} cloudwan_bgp must be 'ok' or 'fail', "
            f"got '{details['cloudwan_bgp']}'"
        )
    else:
        assert details["cloudwan_bgp"] == "not_applicable", (
            f"Branch router {router_name} cloudwan_bgp must be 'not_applicable', "
            f"got '{details['cloudwan_bgp']}'"
        )


# =============================================================================
# Property 4: Verification ping targets match VTI peers (migrated)
# =============================================================================
# **Validates: Requirements 7.2, 7.4**


@settings(max_examples=100)
@given(router_name=all_router_st)
def test_property4_ping_targets_match_vti_peers(router_name):
    """
    Feature: stepfunctions-phase-reorder, Property 4: Verification ping
    targets match VTI peers.

    *For any* router in the topology, the Phase 4 get_ping_targets() function
    SHALL return the remote VTI addresses from the tunnel topology,
    cross-validated against the Phase 2 PHASE2_TUNNELS as the source of truth.

    **Validates: Requirements 7.2, 7.4**
    """
    targets = get_ping_targets(router_name)

    # Every router must have at least one ping target
    assert len(targets) > 0, (
        f"Router {router_name} must have at least one ping target"
    )

    # Derive expected targets from Phase 2 TUNNELS (source of truth)
    expected = []
    for tunnel in PHASE2_TUNNELS:
        if router_name == tunnel["router_a"]:
            expected.append(tunnel["vti_b"]["addr"].split("/")[0])
        elif router_name == tunnel["router_b"]:
            expected.append(tunnel["vti_a"]["addr"].split("/")[0])

    assert sorted(targets) == sorted(expected), (
        f"Router {router_name}: ping targets {targets} do not match "
        f"expected VTI peer addresses {expected}"
    )


# =============================================================================
# Property 5: Verification results persisted correctly to SSM
# =============================================================================
# **Validates: Requirements 5.1, 5.2, 5.4**


# Strategy for generating verification result dicts
verification_result_st = st.fixed_dictionaries({
    "phase": st.just("phase4"),
    "results": st.dictionaries(
        keys=st.sampled_from(ROUTERS),
        values=st.fixed_dictionaries({
            "status": st.sampled_from(["Success", "Failed"]),
            "details": st.fixed_dictionaries({
                "ipsec": st.sampled_from(["ok", "fail"]),
                "bgp": st.sampled_from(["ok", "fail"]),
                "interfaces": st.sampled_from(["ok", "fail"]),
                "cloudwan_bgp": st.sampled_from(["ok", "fail", "not_applicable"]),
            }),
        }),
        min_size=1,
        max_size=4,
    ),
    "success_count": st.integers(min_value=0, max_value=4),
    "fail_count": st.integers(min_value=0, max_value=4),
})


@settings(max_examples=100)
@given(result=verification_result_st)
def test_property5_verification_results_persisted_to_ssm(result):
    """
    Feature: stepfunctions-phase-reorder, Property 5: Verification results
    persisted correctly to SSM.

    *For any* verification result containing per-router results, the
    persist_results_to_ssm() function SHALL call SSM PutParameter with
    parameter name /sdwan/verification-results, type String, overwrite True,
    and a JSON value containing the phase identifier, per-router results
    with status and details, success_count, and fail_count.

    **Validates: Requirements 5.1, 5.2, 5.4**
    """
    mock_ssm = MagicMock()

    with patch("phase4_handler.boto3") as mock_boto3:
        mock_boto3.client.return_value = mock_ssm
        persist_results_to_ssm(result)

    # SSM client must have been created for "ssm"
    mock_boto3.client.assert_called_once_with("ssm")

    # put_parameter must have been called exactly once
    mock_ssm.put_parameter.assert_called_once()

    call_kwargs = mock_ssm.put_parameter.call_args
    # Support both positional kwargs and keyword kwargs
    kwargs = call_kwargs.kwargs if call_kwargs.kwargs else call_kwargs[1]

    # Parameter name
    assert kwargs["Name"] == "/sdwan/verification-results", (
        f"Parameter name must be /sdwan/verification-results, got {kwargs['Name']}"
    )

    # Type
    assert kwargs["Type"] == "String", (
        f"Parameter type must be String, got {kwargs['Type']}"
    )

    # Overwrite
    assert kwargs["Overwrite"] is True, (
        f"Overwrite must be True, got {kwargs['Overwrite']}"
    )

    # Value must be valid JSON matching the input result
    stored = json.loads(kwargs["Value"])
    assert stored["phase"] == result["phase"], "Stored phase must match input"
    assert stored["success_count"] == result["success_count"], (
        "Stored success_count must match input"
    )
    assert stored["fail_count"] == result["fail_count"], (
        "Stored fail_count must match input"
    )
    assert "results" in stored, "Stored value must contain results"

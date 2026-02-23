"""
Property tests for Phase3 Lambda ping target verification.
Feature: lambda-stepfunctions-orchestration

Validates: Requirements 4.6
"""

import sys
import os

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import phase3_handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase3_handler import get_ping_targets, TUNNELS, ROUTERS

# Also import Phase2 tunnel topology for cross-validation
from phase2_handler import TUNNELS as PHASE2_TUNNELS

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

router_name_st = st.sampled_from(ROUTERS)

# Expected ping targets derived from the tunnel topology
# For each router, the ping target is the remote VTI address
EXPECTED_PING_TARGETS = {
    "nv-sdwan": ["169.254.100.2"],
    "nv-branch1": ["169.254.100.1"],
    "fra-sdwan": ["169.254.100.14"],
    "fra-branch1": ["169.254.100.13"],
}


# =============================================================================
# Property 9: Verification ping targets match VTI peers
# =============================================================================
# **Validates: Requirements 4.6**


@settings(max_examples=100)
@given(router_name=router_name_st)
def test_property9_ping_targets_match_vti_peers(router_name):
    """
    Property 9: Verification ping targets match VTI peers.

    *For any* router, the Phase3 ping target SHALL be the remote VTI address
    from the tunnel topology (e.g., nv-sdwan pings 169.254.100.2, nv-branch1
    pings 169.254.100.1).

    **Validates: Requirements 4.6**
    """
    targets = get_ping_targets(router_name)

    # Every router must have at least one ping target
    assert len(targets) > 0, (
        f"Router {router_name} must have at least one ping target"
    )

    # Derive expected targets from Phase2 TUNNELS (the source of truth for VTI addresses)
    expected = []
    for tunnel in PHASE2_TUNNELS:
        if router_name == tunnel["router_a"]:
            # router_a pings router_b's VTI address (strip /30 mask)
            expected.append(tunnel["vti_b"]["addr"].split("/")[0])
        elif router_name == tunnel["router_b"]:
            # router_b pings router_a's VTI address (strip /30 mask)
            expected.append(tunnel["vti_a"]["addr"].split("/")[0])

    # Ping targets must exactly match the remote VTI addresses from the topology
    assert sorted(targets) == sorted(expected), (
        f"Router {router_name}: ping targets {targets} do not match "
        f"expected VTI peer addresses {expected}"
    )

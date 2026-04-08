"""
Property tests for Phase1 Lambda command builder.
Feature: lambda-stepfunctions-orchestration

Validates: Requirements 2.3, 2.4
"""

import sys
import os

from hypothesis import given, settings
from hypothesis import strategies as st

# Add lambda/ to path so we can import phase1_handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from phase1_handler import build_phase1_commands


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

APT_PACKAGES = ["python3-pip", "net-tools", "tmux", "curl", "unzip", "jq"]
SNAP_PACKAGES = ["lxd", "aws-cli"]

apt_package_st = st.sampled_from(APT_PACKAGES)
snap_package_st = st.sampled_from(SNAP_PACKAGES)
any_package_st = st.sampled_from(APT_PACKAGES + SNAP_PACKAGES)


# =============================================================================
# Property 2: Phase1 command payload contains all required packages
# =============================================================================
# **Validates: Requirements 2.3**


@settings(max_examples=100)
@given(pkg=any_package_st)
def test_property2_phase1_payload_contains_all_required_packages(pkg):
    """
    Property 2: Phase1 command payload contains all required packages.

    *For any* invocation of the Phase1 command builder, the generated shell
    script SHALL contain install commands for all required packages:
    python3-pip, net-tools, tmux, curl, unzip, jq, lxd (snap), and
    aws-cli (snap).

    **Validates: Requirements 2.3**
    """
    payload = build_phase1_commands()

    if pkg in APT_PACKAGES:
        assert "apt-get install" in payload and pkg in payload, (
            f"apt-get install command missing package: {pkg}"
        )
    else:
        assert f"snap install {pkg}" in payload, (
            f"snap install command missing package: {pkg}"
        )


# =============================================================================
# Property 3: Snap ordering in Phase1 payload
# =============================================================================
# **Validates: Requirements 2.4**


@settings(max_examples=100)
@given(snap_pkg=snap_package_st)
def test_property3_snap_wait_before_snap_install(snap_pkg):
    """
    Property 3: Snap ordering in Phase1 payload.

    *For any* invocation of the Phase1 command builder, the string
    "snap wait system seed.loaded" SHALL appear at a character position
    before any occurrence of "snap install" in the generated command.

    **Validates: Requirements 2.4**
    """
    payload = build_phase1_commands()

    wait_pos = payload.find("snap wait system seed.loaded")
    install_pos = payload.find(f"snap install {snap_pkg}")

    assert wait_pos != -1, "snap wait system seed.loaded not found in payload"
    assert install_pos != -1, f"snap install {snap_pkg} not found in payload"
    assert wait_pos < install_pos, (
        f"snap wait system seed.loaded (pos {wait_pos}) must appear before "
        f"snap install {snap_pkg} (pos {install_pos})"
    )

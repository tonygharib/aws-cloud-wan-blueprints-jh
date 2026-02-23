"""
Property tests for ssm_utils shared utility module.
Feature: lambda-stepfunctions-orchestration

Validates: Requirements 1.4, 2.9, 3.9, 4.8, 8.2, 8.3, 8.4
"""

import sys
import os
import time
from unittest.mock import MagicMock, patch

from hypothesis import given, settings, assume
from hypothesis import strategies as st

# Add lambda/ to path so we can import ssm_utils
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

from ssm_utils import (
    get_ssm_parameter_path,
    get_region_for_instance,
    send_and_wait,
    get_instance_configs,
    INSTANCE_REGIONS,
)

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

INSTANCE_NAMES = ["nv-sdwan", "nv-branch1", "fra-sdwan", "fra-branch1"]
PARAM_TYPES = ["instance-id", "outside-eip", "outside-private-ip"]

instance_name_st = st.sampled_from(INSTANCE_NAMES)
param_type_st = st.sampled_from(PARAM_TYPES)


# =============================================================================
# Property 1: SSM parameter path generation
# =============================================================================
# **Validates: Requirements 1.4**


@settings(max_examples=100)
@given(instance_name=instance_name_st, param_type=param_type_st)
def test_property1_ssm_parameter_path_generation(instance_name, param_type):
    """
    Property 1: SSM parameter path generation.

    *For any* instance name in {nv-sdwan, nv-branch1, fra-sdwan, fra-branch1}
    and any parameter type in {instance-id, outside-eip, outside-private-ip},
    the generated SSM parameter path SHALL equal
    /sdwan/{instance-name}/{parameter-type}.

    **Validates: Requirements 1.4**
    """
    path = get_ssm_parameter_path(instance_name, param_type)
    assert path == f"/sdwan/{instance_name}/{param_type}", (
        f"Expected /sdwan/{instance_name}/{param_type}, got {path}"
    )
    # Path must start with /sdwan/
    assert path.startswith("/sdwan/")
    # Path must have exactly 3 segments after stripping leading /
    parts = path.strip("/").split("/")
    assert len(parts) == 3
    assert parts[0] == "sdwan"
    assert parts[1] == instance_name
    assert parts[2] == param_type


# =============================================================================
# Property 4: Instance-to-region mapping consistency
# =============================================================================
# **Validates: Requirements 2.9, 3.9, 4.8**


@settings(max_examples=100)
@given(instance_name=instance_name_st)
def test_property4_instance_to_region_mapping(instance_name):
    """
    Property 4: Instance-to-region mapping consistency.

    *For any* instance name, the region used for SSM API calls SHALL be
    "us-east-1" for instances named nv-sdwan or nv-branch1, and
    "eu-central-1" for instances named fra-sdwan or fra-branch1.

    **Validates: Requirements 2.9, 3.9, 4.8**
    """
    region = get_region_for_instance(instance_name)

    if instance_name.startswith("nv-"):
        assert region == "us-east-1", (
            f"nv-* instance {instance_name} should map to us-east-1, got {region}"
        )
    elif instance_name.startswith("fra-"):
        assert region == "eu-central-1", (
            f"fra-* instance {instance_name} should map to eu-central-1, got {region}"
        )


# =============================================================================
# Property 10: send_and_wait returns structured results
# =============================================================================
# **Validates: Requirements 8.2, 8.4**

ssm_status_st = st.sampled_from(["Success", "Failed", "TimedOut"])


@settings(max_examples=100)
@given(
    instance_name=instance_name_st,
    status=ssm_status_st,
    stdout_text=st.text(min_size=0, max_size=50),
    stderr_text=st.text(min_size=0, max_size=50),
)
def test_property10_send_and_wait_structured_results(
    instance_name, status, stdout_text, stderr_text
):
    """
    Property 10: send_and_wait returns structured results.

    *For any* SSM command execution (success, failure, or timeout), the
    send_and_wait function SHALL return a dict containing status, command_id,
    and instance_id fields, and on failure SHALL additionally include stderr
    content.

    **Validates: Requirements 8.2, 8.4**
    """
    region = get_region_for_instance(instance_name)
    fake_instance_id = f"i-{instance_name.replace('-', '')}"
    fake_command_id = "cmd-abc123"

    mock_client = MagicMock()

    # Mock send_command response
    mock_client.send_command.return_value = {
        "Command": {"CommandId": fake_command_id}
    }

    # Build the invocation response based on desired status
    if status == "TimedOut":
        # Always return InProgress so the loop times out
        mock_client.get_command_invocation.return_value = {
            "Status": "InProgress",
            "StandardOutputContent": stdout_text,
            "StandardErrorContent": stderr_text,
        }
    else:
        mock_client.get_command_invocation.return_value = {
            "Status": status,
            "StandardOutputContent": stdout_text,
            "StandardErrorContent": stderr_text,
        }

    with patch("ssm_utils.boto3") as mock_boto3, \
         patch("ssm_utils.time.sleep"):
        mock_boto3.client.return_value = mock_client

        result = send_and_wait(
            fake_instance_id, region, ["echo hello"], timeout=30
        )

    # Structural assertions — must always hold
    assert "status" in result, "Result must contain 'status'"
    assert "command_id" in result, "Result must contain 'command_id'"
    assert "instance_id" in result, "Result must contain 'instance_id'"
    assert result["command_id"] == fake_command_id
    assert result["instance_id"] == fake_instance_id

    # On failure, stderr must be present
    if result["status"] == "Failed":
        assert "stderr" in result, "Failed result must contain 'stderr'"


# =============================================================================
# Property 11: SSM parameter parsing produces complete instance configs
# =============================================================================
# **Validates: Requirements 8.3**


def _build_ssm_params(instances):
    """Build fake SSM parameter responses for a set of instances."""
    params_by_region = {}
    for inst_name in instances:
        region = get_region_for_instance(inst_name)
        if region not in params_by_region:
            params_by_region[region] = []
        params_by_region[region].extend([
            {"Name": f"/sdwan/{inst_name}/instance-id", "Value": f"i-{inst_name}"},
            {"Name": f"/sdwan/{inst_name}/outside-eip", "Value": f"1.2.3.{INSTANCE_NAMES.index(inst_name)}"},
            {"Name": f"/sdwan/{inst_name}/outside-private-ip", "Value": f"10.0.0.{INSTANCE_NAMES.index(inst_name)}"},
        ])
    return params_by_region


# Strategy: non-empty subsets of instances
instance_subset_st = st.lists(
    instance_name_st, min_size=1, max_size=4, unique=True
)


@settings(max_examples=100)
@given(instances=instance_subset_st)
def test_property11_instance_configs_complete(instances):
    """
    Property 11: SSM parameter parsing produces complete instance configs.

    *For any* set of SSM parameters following the /sdwan/{instance-name}/{param-type}
    convention, the get_instance_configs function SHALL return a dict with an
    entry for each instance containing instance_id, outside_eip,
    outside_private_ip, and region fields.

    **Validates: Requirements 8.3**
    """
    params_by_region = _build_ssm_params(instances)

    def make_mock_client(region):
        mock_client = MagicMock()
        mock_paginator = MagicMock()
        mock_client.get_paginator.return_value = mock_paginator
        mock_paginator.paginate.return_value = [
            {"Parameters": params_by_region.get(region, [])}
        ]
        return mock_client

    region_clients = {}

    def mock_boto3_client(service, region_name=None):
        if region_name not in region_clients:
            region_clients[region_name] = make_mock_client(region_name)
        return region_clients[region_name]

    with patch("ssm_utils.boto3") as mock_boto3:
        mock_boto3.client.side_effect = mock_boto3_client
        configs = get_instance_configs()

    required_keys = {"instance_id", "outside_eip", "outside_private_ip", "region"}

    for inst_name in instances:
        assert inst_name in configs, f"Missing config for {inst_name}"
        for key in required_keys:
            assert key in configs[inst_name], (
                f"Config for {inst_name} missing key '{key}'"
            )
        # Region must match the instance-to-region mapping
        expected_region = get_region_for_instance(inst_name)
        assert configs[inst_name]["region"] == expected_region

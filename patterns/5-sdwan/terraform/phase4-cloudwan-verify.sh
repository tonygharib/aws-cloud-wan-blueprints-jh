#!/opt/homebrew/bin/bash
# phase4-cloudwan-verify.sh — Phase 4: Cloud WAN BGP Integration Verification
# Verifies Cloud WAN BGP sessions, cross-region route propagation, dummy interface,
# and existing VPN BGP session preservation on nv-sdwan and fra-sdwan routers.
# Targets only SDWAN routers (nv-sdwan in us-east-1, fra-sdwan in eu-central-1)

set -euo pipefail

# =============================================================================
# Configurable Variables
# =============================================================================
SSM_TIMEOUT=120

# =============================================================================
# Instance-to-Region Mapping (SDWAN routers only)
# =============================================================================
declare -A INSTANCE_REGIONS
INSTANCE_REGIONS["nv-sdwan"]="us-east-1"
INSTANCE_REGIONS["fra-sdwan"]="eu-central-1"

# Terraform output key names for instance IDs
declare -A TF_ID_KEYS
TF_ID_KEYS["nv-sdwan"]="nv_sdwan_instance_id"
TF_ID_KEYS["fra-sdwan"]="fra_sdwan_instance_id"

# Terraform output key names for Connect peer configurations
declare -A TF_PEER_CONFIG_KEYS
TF_PEER_CONFIG_KEYS["nv-sdwan"]="cloudwan_nv_sdwan_connect_peer_config"
TF_PEER_CONFIG_KEYS["fra-sdwan"]="cloudwan_fra_sdwan_connect_peer_config"

# Instance IDs (populated by get_terraform_outputs)
declare -A INSTANCE_IDS

# Connect peer addresses (populated by get_terraform_outputs)
declare -A CLOUDWAN_PEER_IPS    # Core network side IP (BGP neighbor)
declare -A APPLIANCE_IPS        # Appliance side IP (dum0 address)

# Existing VPN BGP neighbors (should remain established)
declare -A VPN_BGP_NEIGHBORS
VPN_BGP_NEIGHBORS["nv-sdwan"]="169.254.100.2"
VPN_BGP_NEIGHBORS["fra-sdwan"]="169.254.100.14"

# =============================================================================
# Helper Functions
# =============================================================================

get_terraform_outputs() {
  echo "Reading instance IDs and Connect peer configuration from terraform output..."
  local tf_json
  tf_json=$(terraform output -json)

  for name in "${!TF_ID_KEYS[@]}"; do
    local id_key="${TF_ID_KEYS[$name]}"
    INSTANCE_IDS["$name"]=$(echo "$tf_json" | jq -r ".${id_key}.value // empty")

    if [[ -z "${INSTANCE_IDS[$name]}" ]]; then
      echo "ERROR: Could not read $id_key from terraform output"
      exit 1
    fi
  done

  # Extract Connect peer BGP addresses from configuration output
  for name in "${!TF_PEER_CONFIG_KEYS[@]}"; do
    local config_key="${TF_PEER_CONFIG_KEYS[$name]}"
    local peer_config
    peer_config=$(echo "$tf_json" | jq -r ".${config_key}.value // empty")

    if [[ -z "$peer_config" ]]; then
      echo "ERROR: Could not read $config_key from terraform output"
      exit 1
    fi

    CLOUDWAN_PEER_IPS["$name"]=$(echo "$peer_config" | jq -r '.bgp_configurations[0].core_network_address // empty')
    APPLIANCE_IPS["$name"]=$(echo "$peer_config" | jq -r '.bgp_configurations[0].peer_address // empty')

    if [[ -z "${CLOUDWAN_PEER_IPS[$name]}" ]]; then
      echo "ERROR: Could not extract core_network_address for $name"
      exit 1
    fi
    if [[ -z "${APPLIANCE_IPS[$name]}" ]]; then
      echo "ERROR: Could not extract peer_address (appliance IP) for $name"
      exit 1
    fi
  done

  echo "Terraform outputs resolved:"
  for name in nv-sdwan fra-sdwan; do
    echo "  $name: ID=${INSTANCE_IDS[$name]} Region=${INSTANCE_REGIONS[$name]}"
    echo "         CloudWAN Peer=${CLOUDWAN_PEER_IPS[$name]} Appliance=${APPLIANCE_IPS[$name]}"
  done
}

run_vyos_command() {
  local instance_id="$1"
  local region="$2"
  local vyos_cmd="$3"
  local timeout="${4:-$SSM_TIMEOUT}"

  local ssm_cmd="lxc exec router -- /opt/vyatta/bin/vyatta-op-cmd-wrapper ${vyos_cmd}"

  local command_id
  command_id=$(aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"$ssm_cmd\"]}" \
    --timeout-seconds "$timeout" \
    --query "Command.CommandId" \
    --output text 2>/dev/null)

  if [[ -z "$command_id" ]] || [[ "$command_id" == "None" ]]; then
    echo "  ERROR: Failed to send SSM command"
    return 1
  fi

  local elapsed=0
  local interval=10
  while [[ $elapsed -lt $timeout ]]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))

    local status
    status=$(aws ssm get-command-invocation \
      --region "$region" \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --query "Status" \
      --output text 2>/dev/null || echo "Pending")

    case "$status" in
      Success)
        aws ssm get-command-invocation \
          --region "$region" \
          --command-id "$command_id" \
          --instance-id "$instance_id" \
          --query "StandardOutputContent" \
          --output text 2>/dev/null || true
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        echo "  Command status: $status"
        aws ssm get-command-invocation \
          --region "$region" \
          --command-id "$command_id" \
          --instance-id "$instance_id" \
          --query "StandardErrorContent" \
          --output text 2>/dev/null || true
        return 1
        ;;
      *)
        ;;
    esac
  done

  echo "  TIMEOUT: Command did not complete within ${timeout}s"
  return 1
}

run_ping_test() {
  local instance_id="$1"
  local region="$2"
  local target_ip="$3"
  local timeout="${4:-$SSM_TIMEOUT}"

  local ssm_cmd="lxc exec router -- ping -c 3 -W 2 ${target_ip}"

  local command_id
  command_id=$(aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"$ssm_cmd\"]}" \
    --timeout-seconds "$timeout" \
    --query "Command.CommandId" \
    --output text 2>/dev/null)

  if [[ -z "$command_id" ]] || [[ "$command_id" == "None" ]]; then
    echo "    FAIL: Could not send ping command"
    return 1
  fi

  local elapsed=0
  local interval=10
  while [[ $elapsed -lt $timeout ]]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))

    local status
    status=$(aws ssm get-command-invocation \
      --region "$region" \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --query "Status" \
      --output text 2>/dev/null || echo "Pending")

    case "$status" in
      Success)
        echo "    OK: ping ${target_ip} — reachable"
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        echo "    FAIL: ping ${target_ip} — unreachable"
        return 1
        ;;
      *)
        ;;
    esac
  done

  echo "    FAIL: ping ${target_ip} — timed out"
  return 1
}

# =============================================================================
# Per-Instance Verification
# =============================================================================

verify_instance() {
  local name="$1"
  local instance_id="${INSTANCE_IDS[$name]}"
  local region="${INSTANCE_REGIONS[$name]}"
  local cloudwan_peer="${CLOUDWAN_PEER_IPS[$name]}"
  local appliance_ip="${APPLIANCE_IPS[$name]}"

  echo ""
  echo "========================================="
  echo "  Verifying: $name ($instance_id)"
  echo "  Region:    $region"
  echo "  CloudWAN Peer: $cloudwan_peer"
  echo "  Appliance IP:  $appliance_ip"
  echo "========================================="

  # 1. BGP Summary — check Cloud WAN neighbor status (Req 9.1)
  echo ""
  echo "--- BGP Summary ---"
  if ! run_vyos_command "$instance_id" "$region" "show ip bgp summary"; then
    echo "  WARNING: Could not retrieve BGP summary"
  fi

  # 2. BGP routes — check cross-region loopback routes (Req 9.2)
  echo ""
  echo "--- BGP Routes ---"
  if ! run_vyos_command "$instance_id" "$region" "show ip route bgp"; then
    echo "  WARNING: Could not retrieve BGP routes"
  fi

  # 3. Existing VPN BGP sessions — verify still established (Req 9.3)
  echo ""
  echo "--- Existing VPN BGP Neighbor ---"
  local vpn_neighbor="${VPN_BGP_NEIGHBORS[$name]}"
  if [[ -n "$vpn_neighbor" ]]; then
    if ! run_vyos_command "$instance_id" "$region" "show ip bgp neighbors ${vpn_neighbor}"; then
      echo "  WARNING: Could not retrieve VPN BGP neighbor details for $vpn_neighbor"
    fi
  else
    echo "  No VPN BGP neighbor configured for $name"
  fi

  # 4. Dummy interface status (Req 9.4 — reachability check via interface)
  echo ""
  echo "--- Dummy Interface (dum0) ---"
  if ! run_vyos_command "$instance_id" "$region" "show interfaces dummy dum0"; then
    echo "  WARNING: Could not retrieve dummy interface status"
  fi

  # 5. Ping Cloud WAN peer IP (Req 9.4)
  echo ""
  echo "--- Ping Cloud WAN Peer ---"
  run_ping_test "$instance_id" "$region" "$cloudwan_peer" || true

  # 6. Cloud WAN BGP neighbor detail
  echo ""
  echo "--- Cloud WAN BGP Neighbor Detail ---"
  if ! run_vyos_command "$instance_id" "$region" "show ip bgp neighbors ${cloudwan_peer}"; then
    echo "  WARNING: Could not retrieve Cloud WAN BGP neighbor details"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================="
  echo "Phase 4: Cloud WAN BGP Verification"
  echo "========================================="
  echo ""

  get_terraform_outputs
  echo ""

  local instance_order=(nv-sdwan fra-sdwan)

  for name in "${instance_order[@]}"; do
    verify_instance "$name"
  done

  echo ""
  echo "========================================="
  echo "Phase 4: Verification Complete"
  echo "========================================="
  echo ""
  echo "Expected cross-region routes:"
  echo "  nv-sdwan  should see: 10.255.11.1 (fra-branch1), 10.255.10.1 (fra-sdwan) via Cloud WAN"
  echo "  fra-sdwan should see: 10.255.1.1 (nv-branch1), 10.255.0.1 (nv-sdwan) via Cloud WAN"
  echo ""
  echo "Check BGP summary output above for 'Estab' state on Cloud WAN peer."
  echo "Check BGP routes for cross-region loopback prefixes."
}

main "$@"

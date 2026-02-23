#!/opt/homebrew/bin/bash
# phase3-verify.sh — Phase 3: Verification via SSM Run Command
# Verifies IPsec tunnel status, BGP sessions, interfaces, and connectivity
# Targets all 5 SD-WAN Ubuntu instances across us-east-1 and eu-central-1

set -euo pipefail

# =============================================================================
# Configurable Variables
# =============================================================================
SSM_TIMEOUT=120

# =============================================================================
# Instance-to-Region Mapping
# =============================================================================
declare -A INSTANCE_REGIONS
INSTANCE_REGIONS["nv-branch1"]="us-east-1"
INSTANCE_REGIONS["nv-branch2"]="us-east-1"
INSTANCE_REGIONS["nv-sdwan"]="us-east-1"
INSTANCE_REGIONS["fra-branch1"]="eu-central-1"
INSTANCE_REGIONS["fra-sdwan"]="eu-central-1"

# Terraform output key names for instance IDs
declare -A TF_OUTPUT_KEYS
TF_OUTPUT_KEYS["nv-branch1"]="nv_branch1_instance_id"
TF_OUTPUT_KEYS["nv-branch2"]="nv_branch2_instance_id"
TF_OUTPUT_KEYS["nv-sdwan"]="nv_sdwan_instance_id"
TF_OUTPUT_KEYS["fra-branch1"]="fra_branch1_instance_id"
TF_OUTPUT_KEYS["fra-sdwan"]="fra_sdwan_instance_id"

# Instance IDs (populated by get_instance_ids)
declare -A INSTANCE_IDS

# =============================================================================
# VPN Tunnel Topology (for ping targets)
# Each entry: router_a|router_b|vti_a_addr|vti_b_addr
# =============================================================================
TUNNELS=(
  "nv-sdwan|nv-branch1|169.254.100.1|169.254.100.2"
  "fra-sdwan|fra-branch1|169.254.100.13|169.254.100.14"
)

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --nv-branch1 ID    Instance ID for nv-branch1
  --nv-branch2 ID    Instance ID for nv-branch2
  --nv-sdwan ID      Instance ID for nv-sdwan
  --fra-branch1 ID   Instance ID for fra-branch1
  --fra-sdwan ID     Instance ID for fra-sdwan
  -h, --help         Show this help message

If no instance IDs are provided, reads from 'terraform output -json'.
EOF
  exit 0
}

get_instance_ids() {
  # Parse CLI arguments first
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --nv-branch1)  INSTANCE_IDS["nv-branch1"]="$2"; shift 2 ;;
      --nv-branch2)  INSTANCE_IDS["nv-branch2"]="$2"; shift 2 ;;
      --nv-sdwan)    INSTANCE_IDS["nv-sdwan"]="$2"; shift 2 ;;
      --fra-branch1) INSTANCE_IDS["fra-branch1"]="$2"; shift 2 ;;
      --fra-sdwan)   INSTANCE_IDS["fra-sdwan"]="$2"; shift 2 ;;
      -h|--help)     usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done

  # Fill missing IDs from terraform output
  local need_tf=false
  for name in "${!TF_OUTPUT_KEYS[@]}"; do
    if [[ -z "${INSTANCE_IDS[$name]:-}" ]]; then
      need_tf=true
      break
    fi
  done

  if $need_tf; then
    echo "Reading instance IDs from terraform output..."
    local tf_json
    tf_json=$(terraform output -json)

    for name in "${!TF_OUTPUT_KEYS[@]}"; do
      if [[ -z "${INSTANCE_IDS[$name]:-}" ]]; then
        local key="${TF_OUTPUT_KEYS[$name]}"
        local id
        id=$(echo "$tf_json" | jq -r ".${key}.value // empty")
        if [[ -z "$id" ]]; then
          echo "ERROR: Could not read $key from terraform output"
          exit 1
        fi
        INSTANCE_IDS["$name"]="$id"
      fi
    done
  fi

  echo "Instance IDs resolved:"
  for name in nv-branch1 nv-branch2 nv-sdwan fra-branch1 fra-sdwan; do
    echo "  $name: ${INSTANCE_IDS[$name]} (${INSTANCE_REGIONS[$name]})"
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

  # Poll for completion
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
        # Print stdout
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

get_ping_targets() {
  # For a given router name, return the VTI peer addresses it should ping
  local router_name="$1"
  local targets=()

  for tunnel in "${TUNNELS[@]}"; do
    IFS='|' read -r router_a router_b vti_a_addr vti_b_addr <<< "$tunnel"

    if [[ "$router_name" == "$router_a" ]]; then
      targets+=("$vti_b_addr")
    elif [[ "$router_name" == "$router_b" ]]; then
      targets+=("$vti_a_addr")
    fi
  done

  echo "${targets[@]}"
}

verify_instance() {
  local name="$1"
  local instance_id="${INSTANCE_IDS[$name]}"
  local region="${INSTANCE_REGIONS[$name]}"

  echo ""
  echo "========================================="
  echo "  Verifying: $name ($instance_id)"
  echo "  Region:    $region"
  echo "========================================="

  # IPsec SA status
  echo ""
  echo "--- IPsec SA Status ---"
  if ! run_vyos_command "$instance_id" "$region" "show vpn ipsec sa"; then
    echo "  WARNING: Could not retrieve IPsec SA status"
  fi

  # BGP summary
  echo ""
  echo "--- BGP Summary ---"
  if ! run_vyos_command "$instance_id" "$region" "show ip bgp summary"; then
    echo "  WARNING: Could not retrieve BGP summary"
  fi

  # Interface status
  echo ""
  echo "--- Interfaces ---"
  if ! run_vyos_command "$instance_id" "$region" "show interfaces"; then
    echo "  WARNING: Could not retrieve interface status"
  fi

  # Ping tests across VTI tunnels
  echo ""
  echo "--- Ping Tests ---"
  local targets
  targets=$(get_ping_targets "$name")

  if [[ -z "$targets" ]]; then
    echo "  No VTI ping targets for $name"
  else
    for target in $targets; do
      run_ping_test "$instance_id" "$region" "$target" || true
    done
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================="
  echo "Phase 3: Verification via SSM Run Command"
  echo "========================================="
  echo ""

  get_instance_ids "$@"

  local instance_order=(nv-sdwan nv-branch1 fra-sdwan fra-branch1)

  for name in "${instance_order[@]}"; do
    verify_instance "$name"
  done

  echo ""
  echo "========================================="
  echo "Phase 3: Verification Complete"
  echo "========================================="
}

main "$@"

#!/opt/homebrew/bin/bash
# phase4-cloudwan-bgp-config.sh — Phase 4: Cloud WAN BGP Configuration via SSM Run Command
# Pushes tunnel-less BGP peering configuration to SDWAN VyOS routers for Cloud WAN Connect peers
# Targets nv-sdwan (us-east-1) and fra-sdwan (eu-central-1) only
# Additive-only: does NOT modify or delete existing VPN/BGP configuration

set -euo pipefail

# =============================================================================
# Configurable Variables
# =============================================================================
SDWAN_BGP_ASN=65001
SSM_TIMEOUT=300

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

# Private subnet gateways (first IP in each private subnet)
declare -A PRIVATE_SUBNET_GW
PRIVATE_SUBNET_GW["nv-sdwan"]="10.201.1.1"
PRIVATE_SUBNET_GW["fra-sdwan"]="10.200.1.1"

# Terraform output key names for Connect peer configurations
declare -A TF_PEER_CONFIG_KEYS
TF_PEER_CONFIG_KEYS["nv-sdwan"]="cloudwan_nv_sdwan_connect_peer_config"
TF_PEER_CONFIG_KEYS["fra-sdwan"]="cloudwan_fra_sdwan_connect_peer_config"

# Instance IDs (populated by get_terraform_outputs)
declare -A INSTANCE_IDS

# Connect peer addresses (populated by get_terraform_outputs)
declare -A CLOUDWAN_PEER_IP1    # First core network peer IP (BGP neighbor)
declare -A CLOUDWAN_PEER_IP2    # Second core network peer IP (BGP neighbor, redundancy)
declare -A CLOUDWAN_ASNS        # Core network ASN per region (may differ per edge)

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

    # Extract both core_network_address entries (Cloud WAN provides 2 peers for redundancy)
    # and the core_network_asn (may differ per edge location)
    CLOUDWAN_PEER_IP1["$name"]=$(echo "$peer_config" | jq -r '.[0].bgp_configurations[0].core_network_address // empty')
    CLOUDWAN_PEER_IP2["$name"]=$(echo "$peer_config" | jq -r '.[0].bgp_configurations[1].core_network_address // empty')
    CLOUDWAN_ASNS["$name"]=$(echo "$peer_config" | jq -r '.[0].bgp_configurations[0].core_network_asn // empty')

    if [[ -z "${CLOUDWAN_PEER_IP1[$name]}" ]]; then
      echo "ERROR: Could not extract core_network_address for $name"
      exit 1
    fi
    if [[ -z "${CLOUDWAN_ASNS[$name]}" ]]; then
      echo "ERROR: Could not extract core_network_asn for $name"
      exit 1
    fi
  done

  echo "Terraform outputs resolved:"
  for name in nv-sdwan fra-sdwan; do
    echo "  $name: ID=${INSTANCE_IDS[$name]} Region=${INSTANCE_REGIONS[$name]}"
    echo "         CloudWAN Peer1=${CLOUDWAN_PEER_IP1[$name]} Peer2=${CLOUDWAN_PEER_IP2[$name]:-none} ASN=${CLOUDWAN_ASNS[$name]} GW=${PRIVATE_SUBNET_GW[$name]}"
  done
}

send_and_wait() {
  local instance_id="$1"
  local region="$2"
  local commands="$3"
  local timeout="${4:-$SSM_TIMEOUT}"

  local tmpfile
  tmpfile=$(mktemp)
  python3 -c "
import json, sys
script = sys.stdin.read()
params = {'commands': [script]}
json.dump(params, sys.stdout)
" <<< "$commands" > "$tmpfile"

  local command_id
  command_id=$(aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "file://$tmpfile" \
    --timeout-seconds "$timeout" \
    --query "Command.CommandId" \
    --output text 2>&1)

  local send_rc=$?
  rm -f "$tmpfile"

  if [[ $send_rc -ne 0 ]] || [[ -z "$command_id" ]] || [[ "$command_id" == "None" ]]; then
    echo "  ERROR: Failed to send SSM command to $instance_id"
    echo "  $command_id"
    return 1
  fi

  echo "  SSM Command ID: $command_id"

  local elapsed=0
  local interval=15
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
        echo "  SSM command completed successfully"
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        echo "  SSM command status: $status"
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

  echo "  TIMEOUT: SSM command $command_id did not complete within ${timeout}s"
  return 1
}

check_router_running() {
  local instance_id="$1"
  local region="$2"

  echo "  Checking if router container is running..."
  local tmpfile
  tmpfile=$(mktemp)
  cat > "$tmpfile" <<'JSONEOF'
{"commands":["lxc info router 2>/dev/null | grep -q 'Status: RUNNING'"]}
JSONEOF

  local command_id
  command_id=$(aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "file://$tmpfile" \
    --timeout-seconds 30 \
    --query "Command.CommandId" \
    --output text 2>/dev/null)

  rm -f "$tmpfile"

  if [[ -z "$command_id" ]] || [[ "$command_id" == "None" ]]; then
    return 1
  fi

  sleep 10
  local status
  status=$(aws ssm get-command-invocation \
    --region "$region" \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --query "Status" \
    --output text 2>/dev/null || echo "Failed")

  [[ "$status" == "Success" ]]
}

# =============================================================================
# Cloud WAN BGP vbash Script Generation
# =============================================================================

build_cloudwan_bgp_script() {
  local router_name="$1"
  local peer_ip1="${CLOUDWAN_PEER_IP1[$router_name]}"
  local peer_ip2="${CLOUDWAN_PEER_IP2[$router_name]}"
  local cloudwan_asn="${CLOUDWAN_ASNS[$router_name]}"
  local private_subnet_gw="${PRIVATE_SUBNET_GW[$router_name]}"

  # For NO_ENCAP, BGP runs directly over VPC fabric using the ENI private IP
  # No dummy interface needed — update-source uses the eth1 (internal ENI) address
  # We get the local IP from the VyOS interface dynamically

  cat <<VBASH
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure

# Static routes to Cloud WAN peer IPs via private subnet gateway
set protocols static route ${peer_ip1}/32 next-hop ${private_subnet_gw}
VBASH

  # Add second peer static route if available
  if [[ -n "$peer_ip2" ]]; then
    cat <<VBASH
set protocols static route ${peer_ip2}/32 next-hop ${private_subnet_gw}
VBASH
  fi

  cat <<VBASH

# BGP neighbor 1 for Cloud WAN
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip1} remote-as ${cloudwan_asn}
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip1} ebgp-multihop 4
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip1} address-family ipv4-unicast
VBASH

  # Add second BGP neighbor if available
  if [[ -n "$peer_ip2" ]]; then
    cat <<VBASH

# BGP neighbor 2 for Cloud WAN (redundancy)
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip2} remote-as ${cloudwan_asn}
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip2} ebgp-multihop 4
set protocols bgp ${SDWAN_BGP_ASN} neighbor ${peer_ip2} address-family ipv4-unicast
VBASH
  fi

  cat <<VBASH

commit
save
exit
VBASH
}

# =============================================================================
# Push Config to Router via SSM
# =============================================================================

push_config() {
  local name="$1"
  local instance_id="${INSTANCE_IDS[$name]}"
  local region="${INSTANCE_REGIONS[$name]}"

  # Generate the vbash script for this router
  local bgp_script
  bgp_script=$(build_cloudwan_bgp_script "$name")

  # Build SSM command: write script to file, push to container, execute
  local ssm_cmd
  ssm_cmd=$(cat <<SSMEOF
#!/bin/bash
set -e

# Write Cloud WAN BGP vbash script
cat > /tmp/vyos-cloudwan-bgp.sh <<'BGPEOF'
${bgp_script}
BGPEOF

# Push and execute in VyOS container
lxc file push /tmp/vyos-cloudwan-bgp.sh router/tmp/vyos-cloudwan-bgp.sh
lxc exec router -- chmod +x /tmp/vyos-cloudwan-bgp.sh
lxc exec router -- /tmp/vyos-cloudwan-bgp.sh
SSMEOF
)

  send_and_wait "$instance_id" "$region" "$ssm_cmd"
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================="
  echo "Phase 4: Cloud WAN BGP Configuration via SSM"
  echo "========================================="
  echo ""

  get_terraform_outputs
  echo ""

  local success_count=0
  local fail_count=0
  local instance_order=(nv-sdwan fra-sdwan)

  for name in "${instance_order[@]}"; do
    local instance_id="${INSTANCE_IDS[$name]}"
    local region="${INSTANCE_REGIONS[$name]}"

    echo "-----------------------------------------"
    echo "Processing: $name ($instance_id) in $region"
    echo "-----------------------------------------"

    # Verify router container is running
    if ! check_router_running "$instance_id" "$region"; then
      echo "  FAILED: $name — router container not running, skipping"
      fail_count=$((fail_count + 1))
      echo ""
      continue
    fi

    # Push Cloud WAN BGP configuration
    if push_config "$name"; then
      echo "  SUCCESS: $name"
      success_count=$((success_count + 1))
    else
      echo "  FAILED: $name"
      fail_count=$((fail_count + 1))
    fi

    echo ""
  done

  echo "========================================="
  echo "Phase 4 Complete"
  echo "  Success: $success_count / ${#instance_order[@]}"
  echo "  Failed:  $fail_count / ${#instance_order[@]}"
  echo "========================================="

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"

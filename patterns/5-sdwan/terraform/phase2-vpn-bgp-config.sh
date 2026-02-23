#!/opt/homebrew/bin/bash
# phase2-vpn-bgp-config.sh — Phase 2: VPN/BGP Configuration via SSM Run Command
# Pushes IPsec VPN tunnels and BGP peering configuration to each VyOS router
# Targets all 5 SD-WAN Ubuntu instances across us-east-1 and eu-central-1

set -euo pipefail

# =============================================================================
# Configurable Variables
# =============================================================================
VPN_PSK="aws123"
SDWAN_BGP_ASN=65001
BRANCH_BGP_ASN=65002
SSM_TIMEOUT=300

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
declare -A TF_ID_KEYS
TF_ID_KEYS["nv-branch1"]="nv_branch1_instance_id"
TF_ID_KEYS["nv-branch2"]="nv_branch2_instance_id"
TF_ID_KEYS["nv-sdwan"]="nv_sdwan_instance_id"
TF_ID_KEYS["fra-branch1"]="fra_branch1_instance_id"
TF_ID_KEYS["fra-sdwan"]="fra_sdwan_instance_id"

# Terraform output key names for Outside EIPs
declare -A TF_EIP_KEYS
TF_EIP_KEYS["nv-branch1"]="nv_branch1_outside_eip"
TF_EIP_KEYS["nv-branch2"]="nv_branch2_outside_eip"
TF_EIP_KEYS["nv-sdwan"]="nv_sdwan_outside_eip"
TF_EIP_KEYS["fra-branch1"]="fra_branch1_outside_eip"
TF_EIP_KEYS["fra-sdwan"]="fra_sdwan_outside_eip"

# Instance IDs and EIPs (populated by get_terraform_outputs)
declare -A INSTANCE_IDS
declare -A INSTANCE_EIPS
declare -A INSTANCE_PRIVATE_IPS

# Terraform output key names for Outside ENI Private IPs
declare -A TF_PRIVATE_IP_KEYS
TF_PRIVATE_IP_KEYS["nv-branch1"]="nv_branch1_outside_private_ip"
TF_PRIVATE_IP_KEYS["nv-branch2"]="nv_branch2_outside_private_ip"
TF_PRIVATE_IP_KEYS["nv-sdwan"]="nv_sdwan_outside_private_ip"
TF_PRIVATE_IP_KEYS["fra-branch1"]="fra_branch1_outside_private_ip"
TF_PRIVATE_IP_KEYS["fra-sdwan"]="fra_sdwan_outside_private_ip"

# =============================================================================
# Instance Configuration Map: loopback, ASN, role
# =============================================================================
declare -A INSTANCE_LOOPBACK
INSTANCE_LOOPBACK["nv-sdwan"]="10.255.0.1"
INSTANCE_LOOPBACK["nv-branch1"]="10.255.1.1"
INSTANCE_LOOPBACK["nv-branch2"]="10.255.2.1"
INSTANCE_LOOPBACK["fra-sdwan"]="10.255.10.1"
INSTANCE_LOOPBACK["fra-branch1"]="10.255.11.1"

declare -A INSTANCE_ASN
INSTANCE_ASN["nv-sdwan"]="$SDWAN_BGP_ASN"
INSTANCE_ASN["nv-branch1"]="$BRANCH_BGP_ASN"
INSTANCE_ASN["nv-branch2"]="$BRANCH_BGP_ASN"
INSTANCE_ASN["fra-sdwan"]="$SDWAN_BGP_ASN"
INSTANCE_ASN["fra-branch1"]="$BRANCH_BGP_ASN"

# shellcheck disable=SC2034
declare -A INSTANCE_ROLE
INSTANCE_ROLE["nv-sdwan"]="sdwan"
INSTANCE_ROLE["nv-branch1"]="branch"
INSTANCE_ROLE["nv-branch2"]="branch"
INSTANCE_ROLE["fra-sdwan"]="sdwan"
INSTANCE_ROLE["fra-branch1"]="branch"

# =============================================================================
# VPN Tunnel Topology
# Each entry: router_a|router_b|vti_a_addr|vti_b_addr|vti_a_name|vti_b_name
# =============================================================================
TUNNELS=(
  "nv-sdwan|nv-branch1|169.254.100.1/30|169.254.100.2/30|vti0|vti0"
  "fra-sdwan|fra-branch1|169.254.100.13/30|169.254.100.14/30|vti0|vti0"
)

# =============================================================================
# Helper Functions
# =============================================================================

get_terraform_outputs() {
  echo "Reading instance IDs, EIPs, and private IPs from terraform output..."
  local tf_json
  tf_json=$(terraform output -json)

  for name in "${!TF_ID_KEYS[@]}"; do
    local id_key="${TF_ID_KEYS[$name]}"
    local eip_key="${TF_EIP_KEYS[$name]}"
    local pip_key="${TF_PRIVATE_IP_KEYS[$name]}"

    INSTANCE_IDS["$name"]=$(echo "$tf_json" | jq -r ".${id_key}.value // empty")
    INSTANCE_EIPS["$name"]=$(echo "$tf_json" | jq -r ".${eip_key}.value // empty")
    INSTANCE_PRIVATE_IPS["$name"]=$(echo "$tf_json" | jq -r ".${pip_key}.value // empty")

    if [[ -z "${INSTANCE_IDS[$name]}" ]]; then
      echo "ERROR: Could not read $id_key from terraform output"
      exit 1
    fi
    if [[ -z "${INSTANCE_EIPS[$name]}" ]]; then
      echo "ERROR: Could not read $eip_key from terraform output"
      exit 1
    fi
    if [[ -z "${INSTANCE_PRIVATE_IPS[$name]}" ]]; then
      echo "ERROR: Could not read $pip_key from terraform output"
      exit 1
    fi
  done

  echo "Instance IDs, EIPs, and Private IPs resolved:"
  for name in nv-branch1 nv-branch2 nv-sdwan fra-branch1 fra-sdwan; do
    echo "  $name: ID=${INSTANCE_IDS[$name]} EIP=${INSTANCE_EIPS[$name]} PrivIP=${INSTANCE_PRIVATE_IPS[$name]} (${INSTANCE_REGIONS[$name]})"
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
# Per-Router VPN/BGP vbash Script Generation
# =============================================================================

build_vpn_bgp_script() {
  local router_name="$1"
  local loopback="${INSTANCE_LOOPBACK[$router_name]}"
  local asn="${INSTANCE_ASN[$router_name]}"
  local local_private_ip="${INSTANCE_PRIVATE_IPS[$router_name]}"

  # Start the vbash script
  local script="#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure

# Loopback
set interfaces loopback lo address ${loopback}/32
"

  # Collect VTI interfaces, IPsec peers, and BGP neighbors for this router
  local vti_configs=""
  local ipsec_peers=""
  local bgp_neighbors=""

  for tunnel in "${TUNNELS[@]}"; do
    IFS='|' read -r router_a router_b vti_a_addr vti_b_addr vti_a_name vti_b_name <<< "$tunnel"

    local my_vti="" my_vti_addr="" peer_name="" peer_vti_addr=""

    if [[ "$router_name" == "$router_a" ]]; then
      my_vti="$vti_a_name"
      my_vti_addr="$vti_a_addr"
      peer_name="$router_b"
      # Extract peer VTI IP without /30 for BGP neighbor
      peer_vti_addr="${vti_b_addr%/*}"
    elif [[ "$router_name" == "$router_b" ]]; then
      my_vti="$vti_b_name"
      my_vti_addr="$vti_b_addr"
      peer_name="$router_a"
      peer_vti_addr="${vti_a_addr%/*}"
    else
      continue
    fi

    local peer_eip="${INSTANCE_EIPS[$peer_name]}"
    local peer_private_ip="${INSTANCE_PRIVATE_IPS[$peer_name]}"
    local peer_asn="${INSTANCE_ASN[$peer_name]}"
    local my_vti_ip="${my_vti_addr%/*}"
    local local_eip="${INSTANCE_EIPS[$router_name]}"

    # VTI interface
    vti_configs+="
# VTI to ${peer_name}
set interfaces vti ${my_vti} address ${my_vti_addr}
"

    # IPsec peer — use EIP as peer address (transport), but match on private IP identity
    ipsec_peers+="
# IPsec peer: ${peer_name}
set vpn ipsec site-to-site peer ${peer_eip} authentication mode pre-shared-secret
set vpn ipsec site-to-site peer ${peer_eip} authentication pre-shared-secret '${VPN_PSK}'
set vpn ipsec site-to-site peer ${peer_eip} authentication remote-id ${peer_private_ip}
set vpn ipsec site-to-site peer ${peer_eip} connection-type initiate
set vpn ipsec site-to-site peer ${peer_eip} ike-group IKE-GROUP
set vpn ipsec site-to-site peer ${peer_eip} local-address ${local_private_ip}
set vpn ipsec site-to-site peer ${peer_eip} vti bind ${my_vti}
set vpn ipsec site-to-site peer ${peer_eip} vti esp-group ESP-GROUP
"

    # BGP neighbor
    bgp_neighbors+="
# BGP neighbor: ${peer_name} via ${my_vti}
set protocols bgp ${asn} neighbor ${peer_vti_addr} ebgp-multihop 2
set protocols bgp ${asn} neighbor ${peer_vti_addr} remote-as ${peer_asn}
set protocols bgp ${asn} neighbor ${peer_vti_addr} update-source ${my_vti_ip}
"
  done

  # Assemble VTI configs
  script+="${vti_configs}"

  # IPsec global settings
  script+="
# IPsec global settings
set vpn ipsec interface eth0
set vpn ipsec esp-group ESP-GROUP compression disable
set vpn ipsec esp-group ESP-GROUP lifetime 3600
set vpn ipsec esp-group ESP-GROUP mode tunnel
set vpn ipsec esp-group ESP-GROUP pfs dh-group14
set vpn ipsec esp-group ESP-GROUP proposal 1 encryption aes256
set vpn ipsec esp-group ESP-GROUP proposal 1 hash sha256
set vpn ipsec ike-group IKE-GROUP key-exchange ikev2
set vpn ipsec ike-group IKE-GROUP lifetime 28800
set vpn ipsec ike-group IKE-GROUP proposal 1 dh-group 14
set vpn ipsec ike-group IKE-GROUP proposal 1 encryption aes256
set vpn ipsec ike-group IKE-GROUP proposal 1 hash sha256
"

  # IPsec peers
  script+="${ipsec_peers}"

  # BGP configuration
  script+="
# BGP configuration
${bgp_neighbors}
set protocols bgp ${asn} network ${loopback}/32
set protocols bgp ${asn} parameters router-id ${loopback}

commit
save
exit
"

  echo "$script"
}

# =============================================================================
# Push Config to Router via SSM
# =============================================================================

push_config() {
  local name="$1"
  local instance_id="${INSTANCE_IDS[$name]}"
  local region="${INSTANCE_REGIONS[$name]}"

  # Generate the vbash script for this router
  local vpn_script
  vpn_script=$(build_vpn_bgp_script "$name")

  # Build SSM command: write script to file, push to container, execute
  local ssm_cmd
  ssm_cmd=$(cat <<SSMEOF
#!/bin/bash
set -e

# Write VPN/BGP vbash script
cat > /tmp/vyos-vpn.sh <<'VPNEOF'
${vpn_script}
VPNEOF

# Push and execute in VyOS container
lxc file push /tmp/vyos-vpn.sh router/tmp/vyos-vpn.sh
lxc exec router -- chmod +x /tmp/vyos-vpn.sh
lxc exec router -- /tmp/vyos-vpn.sh
SSMEOF
)

  send_and_wait "$instance_id" "$region" "$ssm_cmd"
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================="
  echo "Phase 2: VPN/BGP Configuration via SSM"
  echo "========================================="
  echo ""

  get_terraform_outputs
  echo ""

  local success_count=0
  local fail_count=0
  local instance_order=(nv-sdwan nv-branch1 fra-sdwan fra-branch1)

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

    # Push VPN/BGP configuration
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
  echo "Phase 2 Complete"
  echo "  Success: $success_count / ${#instance_order[@]}"
  echo "  Failed:  $fail_count / ${#instance_order[@]}"
  echo "========================================="

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"

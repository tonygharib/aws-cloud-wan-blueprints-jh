#!/opt/homebrew/bin/bash
# phase1-base-setup.sh — Phase 1: Base Setup via SSM Run Command
# Installs packages, initializes LXD, deploys VyOS container, applies base DHCP config
# Targets all 5 SD-WAN Ubuntu instances across us-east-1 and eu-central-1

set -euo pipefail

# =============================================================================
# Configurable Variables (used in build_phase1_commands via interpolation)
# =============================================================================
# shellcheck disable=SC2034
VYOS_S3_BUCKET="fra-vyos-bucket"
# shellcheck disable=SC2034
VYOS_S3_REGION="us-east-1"
# shellcheck disable=SC2034
VYOS_S3_KEY="vyos_dxgl-1.3.3-bc64a3a-5_lxd_amd64.tar.gz"
# shellcheck disable=SC2034
UBUNTU_PASSWORD="aws123"
SSM_TIMEOUT=600

# =============================================================================
# Instance-to-Region Mapping
# =============================================================================
declare -A INSTANCE_REGIONS
INSTANCE_REGIONS["nv-branch1"]="us-east-1"
INSTANCE_REGIONS["nv-branch2"]="us-east-1"
INSTANCE_REGIONS["nv-sdwan"]="us-east-1"
INSTANCE_REGIONS["fra-branch1"]="eu-central-1"
INSTANCE_REGIONS["fra-sdwan"]="eu-central-1"

# Terraform output key names for each instance
declare -A TF_OUTPUT_KEYS
TF_OUTPUT_KEYS["nv-branch1"]="nv_branch1_instance_id"
TF_OUTPUT_KEYS["nv-branch2"]="nv_branch2_instance_id"
TF_OUTPUT_KEYS["nv-sdwan"]="nv_sdwan_instance_id"
TF_OUTPUT_KEYS["fra-branch1"]="fra_branch1_instance_id"
TF_OUTPUT_KEYS["fra-sdwan"]="fra_sdwan_instance_id"

# Instance IDs (populated by get_instance_ids)
declare -A INSTANCE_IDS

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

wait_for_ssm() {
  local instance_id="$1"
  local region="$2"
  local timeout="${3:-120}"
  local elapsed=0
  local interval=10

  echo "  Waiting for SSM registration of $instance_id in $region..."
  while [[ $elapsed -lt $timeout ]]; do
    local status
    status=$(aws ssm describe-instance-information \
      --region "$region" \
      --filters "Key=InstanceIds,Values=$instance_id" \
      --query "InstanceInformationList[0].PingStatus" \
      --output text 2>/dev/null || echo "None")

    if [[ "$status" == "Online" ]]; then
      echo "  Instance $instance_id is registered with SSM"
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "  TIMEOUT: Instance $instance_id not registered with SSM after ${timeout}s"
  return 1
}

send_and_wait() {
  local instance_id="$1"
  local region="$2"
  local commands="$3"
  local timeout="${4:-$SSM_TIMEOUT}"

  # Write commands to a temp file as proper JSON for SSM
  local tmpfile
  tmpfile=$(mktemp)
  # Convert the script into a JSON-safe string array with one element
  python3 -c "
import json, sys
script = sys.stdin.read()
params = {'commands': [script]}
json.dump(params, sys.stdout)
" <<< "$commands" > "$tmpfile"

  # Send SSM command
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

  # Poll for completion
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
        # Print stderr output for debugging
        aws ssm get-command-invocation \
          --region "$region" \
          --command-id "$command_id" \
          --instance-id "$instance_id" \
          --query "StandardErrorContent" \
          --output text 2>/dev/null || true
        return 1
        ;;
      *)
        # InProgress, Pending, Delayed — keep waiting
        ;;
    esac
  done

  echo "  TIMEOUT: SSM command $command_id did not complete within ${timeout}s"
  return 1
}


# =============================================================================
# Phase1 SSM Command Payload
# =============================================================================

build_phase1_commands() {
  # Returns the shell command string to execute on each instance via SSM
  cat <<SSMEOF
#!/bin/bash
set -e

apt-get update -y
apt-get install -y python3-pip net-tools tmux curl unzip jq

# Wait for snapd to be ready before any snap operations
snap wait system seed.loaded
snap refresh --hold=forever
snap install lxd
snap install aws-cli --classic

# Set ubuntu password
echo "ubuntu:${UBUNTU_PASSWORD}" | chpasswd

# LXD init preseed
cat > /tmp/lxd.yaml <<'EOF'
config:
  images.auto_update_cached: false
storage_pools:
- name: default
  driver: dir
profiles:
- devices:
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF
cat /tmp/lxd.yaml | lxd init --preseed || true

# Download VyOS image from S3
aws --region ${VYOS_S3_REGION} s3 cp s3://${VYOS_S3_BUCKET}/${VYOS_S3_KEY} /tmp/vyos.tar.gz
lxc image import /tmp/vyos.tar.gz --alias vyos 2>/dev/null || true

# Router container config
cat > /tmp/router.yaml <<'EOF'
architecture: x86_64
config:
  limits.cpu: '1'
  limits.memory: 2048MiB
devices:
  eth0:
    nictype: physical
    parent: ens6
    type: nic
  eth1:
    nictype: physical
    parent: ens7
    type: nic
EOF

# Idempotency: remove existing container if present
lxc stop router --force 2>/dev/null || true
lxc delete router 2>/dev/null || true

cat /tmp/router.yaml | lxc init vyos router

# Base config.boot
cat > /tmp/config.boot <<'EOF'
interfaces {
    ethernet eth0 {
        address dhcp
        description OUTSIDE
    }
    ethernet eth1 {
        address dhcp
        description INSIDE
    }
    loopback lo {
    }
}
system {
    config-management {
        commit-revisions 100
    }
    host-name vyos
    login {
        user vyos {
            authentication {
                plaintext-password "aws123"
            }
        }
    }
    syslog {
        global {
            facility all {
                level info
            }
        }
    }
}
EOF

lxc file push /tmp/config.boot router/opt/vyatta/etc/config/config.boot
lxc start router
sleep 30

# Phase 1 VyOS script - DHCP with route distances
cat > /tmp/vyos-phase1.sh <<'EOF'
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth0 description 'OUTSIDE'
set interfaces ethernet eth0 address dhcp
set interfaces ethernet eth0 dhcp-options default-route-distance 10
set interfaces ethernet eth1 description 'INSIDE'
set interfaces ethernet eth1 address dhcp
set interfaces ethernet eth1 dhcp-options no-default-route
commit
save
exit
EOF

lxc file push /tmp/vyos-phase1.sh router/tmp/vyos-phase1.sh
lxc exec router -- chmod +x /tmp/vyos-phase1.sh
lxc exec router -- /tmp/vyos-phase1.sh
SSMEOF
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================="
  echo "Phase 1: Base Setup via SSM Run Command"
  echo "========================================="
  echo ""

  get_instance_ids "$@"
  echo ""

  local success_count=0
  local fail_count=0
  local instance_order=(nv-branch1 nv-branch2 nv-sdwan fra-branch1 fra-sdwan)

  # Build the command payload once
  local commands
  commands=$(build_phase1_commands)

  for name in "${instance_order[@]}"; do
    local instance_id="${INSTANCE_IDS[$name]}"
    local region="${INSTANCE_REGIONS[$name]}"

    echo "-----------------------------------------"
    echo "Processing: $name ($instance_id) in $region"
    echo "-----------------------------------------"

    # Check SSM registration
    if ! wait_for_ssm "$instance_id" "$region"; then
      echo "  FAILED: $name — not registered with SSM, skipping"
      fail_count=$((fail_count + 1))
      echo ""
      continue
    fi

    # Send Phase1 commands
    if send_and_wait "$instance_id" "$region" "$commands"; then
      echo "  SUCCESS: $name"
      success_count=$((success_count + 1))
    else
      echo "  FAILED: $name"
      fail_count=$((fail_count + 1))
    fi

    echo ""
  done

  echo "========================================="
  echo "Phase 1 Complete"
  echo "  Success: $success_count / ${#instance_order[@]}"
  echo "  Failed:  $fail_count / ${#instance_order[@]}"
  echo "========================================="

  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
}

main "$@"

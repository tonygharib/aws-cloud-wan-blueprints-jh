# Implementation Plan: SSM-Based VyOS Configuration

## Overview

Replace user_data.sh with three phased SSM Run Command bash scripts for configuring 5 SD-WAN Ubuntu instances. Modify Terraform to remove user_data and add instance ID outputs. Scripts are flat bash, targeting instances across us-east-1 and eu-central-1.

## Tasks

- [x] 1. Remove user_data from Terraform instance definitions and add instance ID outputs
  - [x] 1.1 Remove user_data block from all 3 instance resources in instances-virginia.tf (nv-branch1, nv-branch2, nv-sdwan)
    - Remove the `user_data = templatefile(...)` argument from `aws_instance.nv_branch1_sdwan_instance`, `aws_instance.nv_branch2_sdwan_instance`, and `aws_instance.nv_sdwan_sdwan_instance`
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 1.2 Remove user_data block from all 2 instance resources in instances-frankfurt.tf (fra-branch1, fra-sdwan)
    - Remove the `user_data = templatefile(...)` argument from `aws_instance.fra_branch1_sdwan_instance` and `aws_instance.fra_sdwan_sdwan_instance`
    - _Requirements: 1.4, 1.5_
  - [x] 1.3 Add instance ID outputs to outputs.tf
    - Add outputs: `nv_branch1_instance_id`, `nv_branch2_instance_id`, `nv_sdwan_instance_id`, `fra_branch1_instance_id`, `fra_sdwan_instance_id`
    - Each output references the corresponding `aws_instance.*.id`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 2. Checkpoint - Validate Terraform changes
  - Run `terraform validate` to ensure HCL is valid after removing user_data and adding outputs. Ensure all tests pass, ask the user if questions arise.

- [x] 3. Create phase1-base-setup.sh
  - [x] 3.1 Create phase1-base-setup.sh with configurable variables, instance ID resolution, and SSM helper functions
    - Define configurable variables at top: VYOS_S3_BUCKET, VYOS_S3_REGION, VYOS_S3_KEY, UBUNTU_PASSWORD, SSM_TIMEOUT
    - Implement `get_instance_ids()` to read from terraform output JSON or accept CLI parameters
    - Implement `wait_for_ssm()` to poll `aws ssm describe-instance-information` until instance is registered
    - Implement `send_and_wait()` to send SSM command and poll `aws ssm get-command-invocation` for completion
    - Map instances to regions: nv-* → us-east-1, fra-* → eu-central-1
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.5, 7.1, 7.2_
  - [x] 3.2 Build the Phase1 SSM command payload
    - Construct the shell command string that runs on each instance via SSM:
      - apt-get update and install python3-pip, net-tools, tmux, curl, unzip, jq
      - snap wait system seed.loaded, snap refresh --hold=forever, snap install lxd, snap install aws-cli --classic
      - Set ubuntu password via chpasswd
      - Create /tmp/lxd.yaml preseed and run lxd init --preseed
      - Download VyOS from S3 and import with alias "vyos"
      - Create /tmp/router.yaml with eth0→ens6, eth1→ens7 mapping
      - Idempotency: lxc stop/delete router before lxc init
      - Push base config.boot with DHCP on eth0/eth1, vyos user with password
      - Start router, sleep 30, push and execute Phase1 VyOS script (DHCP with route distances 10/210)
    - _Requirements: 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 6.1, 6.2_
  - [x] 3.3 Implement main loop with error handling
    - Loop over all 5 instances, call send_and_wait() with correct region
    - Report success/failure per instance, continue on failure
    - Report timeout and continue on timeout
    - _Requirements: 3.14, 6.3, 6.4_
  - [ ] 3.4 Write property tests for Phase1 command payload
    - **Property 1: Phase1 command payload contains all required packages**
    - **Property 2: Phase1 snap ordering is correct**
    - **Validates: Requirements 3.5, 3.6**

- [x] 4. Create phase2-vpn-bgp-config.sh
  - [x] 4.1 Create phase2-vpn-bgp-config.sh with configurable variables, terraform output reading, and topology data
    - Define configurable variables: VPN_PSK, SDWAN_BGP_ASN, BRANCH_BGP_ASN, SSM_TIMEOUT
    - Implement terraform output reading for instance IDs and Outside EIPs
    - Define tunnel topology array and instance config map (region, EIP, loopback, ASN, role)
    - Define VTI addressing per tunnel as specified in design
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 4.2 Implement per-router VPN/BGP vbash script generation
    - For each router, generate a vbash script that:
      - Sets loopback interface with unique /32 address
      - Configures VTI interfaces for each tunnel the router participates in
      - Configures IPsec ESP-GROUP and IKE-GROUP
      - Configures site-to-site peers with correct local/remote EIPs and PSK
      - Configures BGP with correct ASN, neighbors on VTI addresses, network advertisements
    - Handle hub routers (nv-sdwan, fra-sdwan) having multiple tunnels/VTIs/peers
    - Push config via SSM: `lxc exec router -- /tmp/vyos-vpn.sh`
    - Verify router container is running before pushing config
    - _Requirements: 4.4, 4.5, 4.6, 4.7, 4.8, 6.6_
  - [x] 4.3 Implement main loop with multi-region support and error handling
    - Loop over all 5 instances with correct region per instance
    - Report success/failure per instance
    - _Requirements: 4.9, 4.10_
  - [ ]* 4.4 Write property tests for Phase2 configuration generation
    - **Property 3: Phase2 IPsec config uses correct tunnel endpoints**
    - **Property 4: VTI addresses form valid /30 pairs**
    - **Property 5: BGP ASN matches router role**
    - **Property 6: All loopback addresses are unique**
    - **Property 7: Instance-to-region mapping is consistent**
    - **Validates: Requirements 4.4, 4.5, 4.6, 4.7, 7.1, 7.2, 7.3, 7.4, 7.5**

- [ ] 5. Checkpoint - Validate Phase1 and Phase2 scripts
  - Run `shellcheck phase1-base-setup.sh phase2-vpn-bgp-config.sh` to verify bash syntax. Ensure all tests pass, ask the user if questions arise.

- [x] 6. Create phase3-verify.sh
  - [x] 6.1 Create phase3-verify.sh with instance ID resolution and VyOS command execution
    - Implement terraform output reading for instance IDs
    - Implement `run_vyos_command()` to execute VyOS show commands via SSM + lxc exec
    - Map instances to regions for correct SSM targeting
    - _Requirements: 5.1, 5.2, 5.8_
  - [x] 6.2 Implement verification checks per instance
    - Run `show vpn ipsec sa` on each router
    - Run `show ip bgp summary` on each router
    - Run `show interfaces` on each router
    - Run ping tests to VTI peer addresses for each tunnel
    - Format output with per-instance headers and readable summaries
    - _Requirements: 5.3, 5.4, 5.5, 5.6, 5.7, 5.9_
  - [ ]* 6.3 Write property test for verification ping targets
    - **Property 8: Verification ping targets match VTI peer addresses**
    - **Validates: Requirements 5.6**

- [ ] 7. Final checkpoint - Validate all scripts and Terraform
  - Run `shellcheck phase1-base-setup.sh phase2-vpn-bgp-config.sh phase3-verify.sh` and `terraform validate`. Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- All scripts are flat bash with no external frameworks
- Scripts read from `terraform output -json` for instance IDs and EIPs
- Property tests validate the topology data structures and command generation logic

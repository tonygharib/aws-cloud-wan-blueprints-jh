# Implementation Plan: Cloud WAN SD-WAN BGP Integration (Tunnel-less)

## Overview

This plan implements AWS Cloud WAN with tunnel-less Connect attachments for BGP peering with the existing SDWAN VyOS routers. Terraform handles all Cloud WAN infrastructure, and a new Phase 4 bash script pushes VyOS BGP configuration via SSM. The implementation builds incrementally: variables first, then Cloud WAN core resources, then attachments, then VyOS configuration, then verification.

## Tasks

- [x] 1. Add Cloud WAN Terraform variables
  - [x] 1.1 Add Cloud WAN variables to variables.tf
    - Add `cloudwan_asn` (default 64512), `cloudwan_connect_cidr_nv` (default "169.254.200.0/29"), `cloudwan_connect_cidr_fra` (default "169.254.201.0/29"), `cloudwan_segment_name` (default "sdwan")
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [x] 2. Create Cloud WAN core infrastructure in cloudwan.tf
  - [x] 2.1 Create cloudwan.tf with Global Network, Core Network, and Core Network Policy
    - Define `aws_networkmanager_global_network.main` with name tag
    - Define `aws_networkmanager_core_network.main` referencing the global network
    - Define the core network policy document with edge locations (us-east-1, eu-central-1), sdwan segment, ASN 64512, and attachment policy for segment tag matching
    - Define `aws_networkmanager_core_network_policy_attachment.main`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [x] 2.2 Add VPC Attachments for nv-sdwan and fra-sdwan
    - Define `aws_networkmanager_vpc_attachment.nv_sdwan` attaching nv-sdwan-vpc private subnet with segment tag
    - Define `aws_networkmanager_vpc_attachment.fra_sdwan` attaching fra-sdwan-vpc private subnet with segment tag
    - Add depends_on for core network policy attachment
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 2.3 Add Connect Attachments (NO_ENCAP) and Connect Peers
    - Define `aws_networkmanager_connect_attachment.nv_sdwan` with protocol NO_ENCAP, referencing nv-sdwan VPC attachment
    - Define `aws_networkmanager_connect_attachment.fra_sdwan` with protocol NO_ENCAP, referencing fra-sdwan VPC attachment
    - Define `aws_networkmanager_connect_peer.nv_sdwan` with peer_address from nv-sdwan internal ENI, inside_cidr from variable, peer_asn 65001
    - Define `aws_networkmanager_connect_peer.fra_sdwan` with peer_address from fra-sdwan internal ENI, inside_cidr from variable, peer_asn 65001
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Update security groups and add Terraform outputs
  - [x] 3.1 Add BGP security group rules to SDWAN private security groups
    - Add TCP 179 and all-traffic ingress from Cloud WAN inside CIDR to `nv_sdwan_private_sg` in instances-virginia.tf
    - Add TCP 179 and all-traffic ingress from Cloud WAN inside CIDR to `fra_sdwan_private_sg` in instances-frankfurt.tf
    - Preserve all existing security group rules
    - _Requirements: 4.1, 4.2, 4.3_

  - [x] 3.2 Add Cloud WAN outputs to outputs.tf
    - Add outputs for core network ID, ARN, VPC attachment IDs, Connect attachment IDs, Connect peer configurations, and Cloud WAN ASN
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 3.8_

- [x] 4. Checkpoint - Validate Terraform configuration
  - Run `terraform validate` and `terraform plan` to verify all Cloud WAN resources, security group updates, and outputs are correct. Ask the user if questions arise.

- [-] 5. Create Phase 4 Cloud WAN BGP configuration script
  - [x] 5.1 Create phase4-cloudwan-bgp-config.sh
    - Implement bash script following the same pattern as phase2-vpn-bgp-config.sh
    - Read instance IDs and Connect peer configuration from terraform output
    - Implement `build_cloudwan_bgp_script()` that generates vbash with: dummy interface (dum0) for inside address, static route to Cloud WAN peer via private subnet gateway, BGP neighbor with ASN 64512, update-source, and ebgp-multihop
    - Implement `push_config()` using SSM send-command with lxc file push and lxc exec
    - Handle both us-east-1 (nv-sdwan) and eu-central-1 (fra-sdwan) regions
    - Include error handling: report failures per instance and continue
    - Script must be additive-only (no deletion of existing VPN/BGP config)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_

  - [x] 5.2 Write property tests for vbash script generation (tests/test_phase4_properties.py)
    - **Property 3: VyOS tunnel-less connectivity setup**
    - **Property 4: VyOS BGP neighbor configuration correctness**
    - **Property 5: Existing BGP configuration preservation**
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.7**

- [x] 6. Create Phase 4 verification script
  - [x] 6.1 Create phase4-cloudwan-verify.sh
    - Implement bash script that verifies Cloud WAN BGP integration on nv-sdwan and fra-sdwan
    - Check BGP session status with Cloud WAN peer (show ip bgp summary)
    - Check routing table for cross-region loopback routes (show ip route bgp)
    - Verify existing VPN BGP sessions still established
    - Check dummy interface status (show interfaces dummy dum0)
    - Ping Cloud WAN peer IP for reachability
    - Handle both regions, format readable per-instance output
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [x] 7. Checkpoint - Validate scripts and run property tests
  - Run `shellcheck phase4-cloudwan-bgp-config.sh phase4-cloudwan-verify.sh` for bash linting. Run property tests if implemented. Ensure all tests pass, ask the user if questions arise.

- [x] 8. Add internal ENI private IP outputs for SDWAN instances
  - [x] 8.1 Add SDWAN internal ENI private IP outputs to outputs.tf
    - Add `nv_sdwan_internal_private_ip` output from `aws_network_interface.nv_sdwan_sdwan_internal.private_ip`
    - Add `fra_sdwan_internal_private_ip` output from `aws_network_interface.fra_sdwan_sdwan_internal.private_ip`
    - These are needed by the phase4 script and the Connect Peer peer_address
    - _Requirements: 3.4, 3.5, 6.2_

- [x] 9. Final checkpoint - Full validation
  - Run `terraform validate`, `terraform plan`, and all tests. Verify the plan shows all expected Cloud WAN resources, security group updates, and outputs. Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- The existing VPN/BGP configuration (phase2) is not modified by any task
- Cloud WAN resources can take 5-15 minutes to provision — `terraform apply` will be slow
- Property tests validate the vbash script generation logic using Python Hypothesis

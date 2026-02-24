# Implementation Plan: VyOS VPN and BGP Configuration

## Overview

This implementation plan extends the existing SD-WAN infrastructure to add IPsec VPN and BGP connectivity between nv_branch1 and nv_sdwan routers. The work involves creating VyOS configuration templates, modifying the user_data script, adding Terraform variables, and updating security groups.

## Tasks

- [x] 1. Add Terraform variables for VPN and BGP configuration
  - Add `vpn_psk` variable with sensitive flag in variables.tf
  - Add `sdwan_bgp_asn` variable with default 65001
  - Add `branch1_bgp_asn` variable with default 65002
  - Add `vpn_tunnel_cidr` variable with default "169.254.100.0/30"
  - Add `random_password` resource for PSK generation fallback
  - Add `local.vpn_psk` to resolve PSK from variable or generated value
  - _Requirements: 5.1, 5.2, 5.3, 5.5_

- [x] 2. Create VyOS configuration template for nv_sdwan router
  - [x] 2.1 Create templates/vyos_config_nv_sdwan.tpl with complete VyOS config.boot syntax
    - Configure eth0 and eth1 interfaces with DHCP
    - Configure loopback lo with 10.255.0.1/32
    - Configure vti0 with 169.254.100.1/30
    - Configure IPsec IKE group with IKEv2, AES-256, SHA-256
    - Configure IPsec ESP group with AES-256, SHA-256
    - Configure IPsec site-to-site peer with PSK authentication
    - Configure BGP ASN 65001 with neighbor 169.254.100.2
    - Set router-id to loopback IP
    - _Requirements: 1.1, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.3, 3.7, 4.4, 7.1, 7.2, 7.3_

- [x] 3. Create VyOS configuration template for nv_branch1 router
  - [x] 3.1 Create templates/vyos_config_nv_branch1.tpl with complete VyOS config.boot syntax
    - Configure eth0 and eth1 interfaces with DHCP
    - Configure loopback lo with 10.255.1.1/32
    - Configure vti0 with 169.254.100.2/30
    - Configure IPsec IKE group with IKEv2, AES-256, SHA-256
    - Configure IPsec ESP group with AES-256, SHA-256
    - Configure IPsec site-to-site peer with PSK authentication
    - Configure BGP ASN 65002 with neighbor 169.254.100.1
    - Add network statement for 10.255.1.1/32 advertisement
    - Set router-id to loopback IP
    - _Requirements: 1.1, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.3, 3.4, 3.7, 4.1, 4.2, 4.3, 7.1, 7.2, 7.3_

- [x] 4. Modify user_data.sh template to accept VyOS configuration
  - [x] 4.1 Add vyos_config variable to the template
    - Add variable placeholder for rendered VyOS configuration
    - Modify config.boot creation to use the vyos_config variable instead of hardcoded default
    - Ensure the heredoc properly handles the multi-line VyOS config
    - _Requirements: 1.4, 8.3_

- [x] 5. Update security groups for ESP protocol
  - [x] 5.1 Add ESP ingress rule to nv_branch1 public security group
    - Add ingress rule for protocol 50 (ESP) from 0.0.0.0/0
    - Verify existing IKE and NAT-T rules remain in place
    - _Requirements: 6.1, 6.2_
  
  - [x] 5.2 Add ESP ingress rule to nv_sdwan public security group
    - Add ingress rule for protocol 50 (ESP) from 0.0.0.0/0
    - Verify existing IKE and NAT-T rules remain in place
    - _Requirements: 6.1, 6.2_

- [x] 6. Update instance definitions to use VyOS config templates
  - [x] 6.1 Update nv_sdwan instance user_data templatefile call
    - Render vyos_config_nv_sdwan.tpl with local_eip, remote_eip, psk, ASNs
    - Pass rendered VyOS config to user_data.sh template
    - _Requirements: 1.2, 5.4_
  
  - [x] 6.2 Update nv_branch1 instance user_data templatefile call
    - Render vyos_config_nv_branch1.tpl with local_eip, remote_eip, psk, ASNs
    - Pass rendered VyOS config to user_data.sh template
    - _Requirements: 1.2, 5.4_

- [x] 7. Checkpoint - Validate Terraform configuration
  - Run `terraform validate` to check syntax
  - Run `terraform plan` to verify resource changes
  - Verify rendered user_data contains VyOS configuration with correct EIPs
  - Verify security groups show ESP ingress rules
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Create outputs for VPN verification
  - [x] 8.1 Add outputs for VPN endpoint information
    - Output nv_sdwan Outside EIP
    - Output nv_branch1 Outside EIP
    - Output VPN tunnel subnet
    - Output BGP ASNs for reference
    - _Requirements: 1.2_

- [x] 9. Final checkpoint - Review and documentation
  - Verify all template files are in templates/ directory
  - Verify naming convention follows vyos_config_{router_name}.tpl pattern
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 8.1, 8.2_

## Notes

- The VPN uses link-local addressing (169.254.100.0/30) for the tunnel interfaces to avoid conflicts with VPC CIDR ranges
- BGP peers over the VTI interfaces, not the public EIPs, so the session is encrypted
- The PSK is marked sensitive in Terraform to prevent it from appearing in logs
- If var.vpn_psk is not set, a random 32-character PSK is generated automatically
- The VyOS configuration is pushed at container creation time, so changes require container recreation


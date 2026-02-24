# Implementation Plan: SD-WAN Ubuntu Instances

## Overview

Deploy Ubuntu 22.04 LTS EC2 instances with VyOS LXD containers across all 5 VPCs in the existing multi-region SD-WAN workshop. Implementation follows the existing Terraform project structure, adding second public subnets, multi-ENI instances, security groups, IAM, and cloud-init bootstrapping.

## Tasks

- [x] 1. Extend locals and variables for instance infrastructure
  - [x] 1.1 Add second public subnet CIDRs to locals.tf
    - Add `public_subnet_2` field to each VPC block in `locals.frankfurt` and `locals.virginia`
    - Use `.2.0/24` offset: fra-branch1 → 10.10.2.0/24, fra-sdwan → 10.200.2.0/24, nv-branch1 → 10.20.2.0/24, nv-branch2 → 10.30.2.0/24, nv-sdwan → 10.201.2.0/24
    - _Requirements: 1.3, 9.4_

  - [x] 1.2 Add new variables to variables.tf
    - Add `sdwan_instance_type` (default: "c5.large"), `vyos_s3_bucket` (default: "fra-vyos-bucket"), `vyos_s3_region` (default: "us-east-1")
    - _Requirements: 6.1, 6.3, 9.3_

- [x] 2. Add second public subnet to all VPC modules
  - [x] 2.1 Update Frankfurt VPC modules in vpc-frankfurt.tf
    - Add second public subnet CIDR to `public_subnets` list for both `fra_branch1_vpc` and `fra_sdwan_vpc` modules
    - Add second public subnet name to `public_subnet_names` list
    - Ensure public subnet tags include `Type = "public"`
    - _Requirements: 1.1, 1.2, 1.4, 1.5_

  - [x] 2.2 Update Virginia VPC modules in vpc-virginia.tf
    - Add second public subnet CIDR to `public_subnets` list for `nv_branch1_vpc`, `nv_branch2_vpc`, and `nv_sdwan_vpc` modules
    - Add second public subnet name to `public_subnet_names` list
    - Ensure public subnet tags include `Type = "public"`
    - _Requirements: 1.1, 1.2, 1.4, 1.5_

- [x] 3. Checkpoint - Validate subnet changes
  - Run `terraform validate` and `terraform plan` to confirm second public subnets are created correctly in all 5 VPCs with no CIDR conflicts. Ask the user if questions arise.

- [x] 4. Create shared instance resources (IAM and AMI)
  - [x] 4.1 Create instances-common.tf with IAM role and instance profile
    - Create `aws_iam_role` with EC2 trust policy
    - Attach `AmazonSSMManagedInstanceCore` managed policy
    - Create inline policy for `s3:GetObject` on `arn:aws:s3:::${var.vyos_s3_bucket}/*`
    - Create `aws_iam_instance_profile` referencing the role
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x] 4.2 Add AMI data sources to instances-common.tf
    - Add `data "aws_ami"` for Frankfurt (provider aws.frankfurt) filtering Ubuntu 22.04 LTS from Canonical (owner 099720109477)
    - Add `data "aws_ami"` for Virginia (provider aws.virginia) with same filters
    - _Requirements: 2.3_

- [x] 5. Create user data template
  - [x] 5.1 Create templates/user_data.sh
    - Write bash cloud-init script with `#!/bin/bash` header
    - Include system package installation (apt update, python3-pip, net-tools, tmux, snap aws-cli, snap lxd, snap refresh hold)
    - Include LXD preseed config creation at /tmp/lxd.yaml and `lxd init --preseed`
    - Include VyOS image download from S3 using `${vyos_s3_bucket}` and `${vyos_s3_region}` template variables
    - Include router.yaml creation with ens6→eth0 and ens7→eth1 physical NIC passthrough, 1 CPU, 2048MiB memory
    - Include VyOS config.boot.default with eth0 OUTSIDE DHCP, eth1 INSIDE DHCP, hostname vyos, user vyos with no password
    - Include container init, config push, and start commands
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 6.2_

- [x] 6. Deploy Frankfurt instances
  - [x] 6.1 Create instances-frankfurt.tf with security groups for Frankfurt VPCs
    - Create public SG per VPC: ingress UDP 500, UDP 4500 from 0.0.0.0/0; TCP 443 from VPC CIDR; all egress
    - Create private SG per VPC: ingress all from VPC CIDR; ingress all from 10.0.0.0/8; all egress
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8_

  - [x] 6.2 Add EC2 instances for fra-branch1-vpc and fra-sdwan-vpc
    - Create `aws_instance` with c5.large, Ubuntu AMI, primary subnet (first public), public SG, IAM profile, source_dest_check=false, user_data via templatefile
    - Create `aws_network_interface` for SDWAN Outside (second public subnet, public SG, source_dest_check=false)
    - Create `aws_network_interface` for SDWAN Internal (private subnet, private SG, source_dest_check=false)
    - Create `aws_network_interface_attachment` for device_index 1 (outside) and device_index 2 (internal)
    - Create 2 `aws_eip` per instance: one for primary ENI (instance association), one for outside ENI (network_interface association)
    - Apply naming convention: `{vpc-name}-sdwan-instance`, `{vpc-name}-sdwan-outside`, `{vpc-name}-sdwan-internal`, etc.
    - _Requirements: 2.1, 2.2, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 8.1, 8.2, 8.3, 8.4_

- [x] 7. Deploy Virginia instances
  - [x] 7.1 Create instances-virginia.tf with security groups for Virginia VPCs
    - Create public SG per VPC: same rules as Frankfurt
    - Create private SG per VPC: same rules as Frankfurt
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8_

  - [x] 7.2 Add EC2 instances for nv-branch1-vpc, nv-branch2-vpc, and nv-sdwan-vpc
    - Same pattern as Frankfurt instances but using Virginia provider, Virginia AMI, and Virginia VPC module outputs
    - _Requirements: 2.1, 2.2, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 8.1, 8.2, 8.3, 8.4_

- [x] 8. Checkpoint - Full validation
  - Run `terraform validate` and `terraform plan` to confirm all 5 instances, 10 additional ENIs, 10 EIPs, 10 security groups, and IAM resources are planned correctly. Ensure all tests pass, ask the user if questions arise.

- [ ]* 9. Write Terraform tests
  - [ ]* 9.1 Write test for subnet topology (Property 1)
    - Create `tests/sdwan_instances.tftest.hcl`
    - Validate each VPC has 2 public subnets and 1 private subnet with non-overlapping CIDRs
    - **Property 1: Subnet Topology**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.5**

  - [ ]* 9.2 Write test for instance count and type (Property 2)
    - Validate exactly 5 instances of type c5.large
    - **Property 2: Instance Count and Type**
    - **Validates: Requirements 2.1, 2.2**

  - [ ]* 9.3 Write test for ENI topology (Property 3)
    - Validate each instance has 3 ENIs at correct device indices and subnets with source_dest_check disabled
    - **Property 3: ENI Topology**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 2.5, 3.7**

  - [ ]* 9.4 Write test for EIP assignment (Property 4)
    - Validate 2 EIPs per instance on public ENIs, 0 on private ENI
    - **Property 4: EIP Assignment**
    - **Validates: Requirements 3.5, 3.6**

  - [ ]* 9.5 Write test for security group rules (Properties 5, 6)
    - Validate public SG rules (UDP 500, 4500, TCP 443) and private SG rules (VPC CIDR, 10.0.0.0/8)
    - **Property 5: Public Security Group Rules**
    - **Property 6: Private Security Group Rules**
    - **Validates: Requirements 4.1-4.8**

  - [ ]* 9.6 Write test for IAM profile sharing (Property 7)
    - Validate all instances reference the same IAM instance profile
    - **Property 7: IAM Profile Shared Across Instances**
    - **Validates: Requirements 5.4, 5.5**

  - [ ]* 9.7 Write test for resource naming convention (Property 8)
    - Validate all resources follow the `{vpc-name}-sdwan-{role}` naming pattern
    - **Property 8: Resource Naming Convention**
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4**

- [x] 10. Final checkpoint
  - Ensure `terraform validate` passes, `terraform plan` shows expected resources, and all tests pass. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation via `terraform plan`
- The user data template is the most complex piece — validate by inspecting the rendered script in the plan output
- Security groups are created per-VPC (not shared) because each references its own VPC CIDR

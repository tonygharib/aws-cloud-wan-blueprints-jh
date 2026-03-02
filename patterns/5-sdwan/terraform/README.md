# SD-WAN Cloud WAN Workshop — Terraform

Deploy a multi-region SD-WAN overlay network on AWS with Cloud WAN backbone using Terraform. This project provisions Ubuntu EC2 instances running VyOS routers inside LXD containers, establishes IPsec VPN tunnels with BGP peering, integrates AWS Cloud WAN with tunnel-less Connect attachments for cross-region route propagation, and orchestrates the entire configuration lifecycle through AWS Step Functions.

## Architecture

```
┌──────────────────────── us-east-1 ────────────────────────┐   ┌───────────────────── eu-central-1 ─────────────────────┐
│                                                            │   │                                                        │
│  ┌─────────────┐    IPsec/BGP    ┌─────────────┐          │   │  ┌─────────────┐    IPsec/BGP    ┌───────────┐         │
│  │  nv-sdwan   │◄──────────────►│ nv-branch1  │          │   │  │  fra-sdwan  │◄──────────────►│fra-branch1│         │
│  │  ASN 65001  │  VTI 100.1/2   │  ASN 65002  │          │   │  │  ASN 65001  │  VTI 100.13/14 │ ASN 65002 │         │
│  │  VPC 10.201 │                 │  VPC 10.20  │          │   │  │  VPC 10.200 │                │ VPC 10.10 │         │
│  └──────┬──────┘                 └─────────────┘          │   │  └──────┬──────┘                └───────────┘         │
│         │ BGP (tunnel-less, NO_ENCAP)                      │   │         │ BGP (tunnel-less, NO_ENCAP)                  │
│         │                                                  │   │         │                                              │
│  ┌──────┴──────────────────────────────────────────────────┴───┴─────────┴──────┐                                       │
│  │                    AWS Cloud WAN Core Network                                │                                       │
│  │              Segment: sdwan | Inside CIDR: 10.100.0.0/16                     │                                       │
│  └──────────────────────────────────────────────────────────────────────────────┘                                       │
│                                                            │   │                                                        │
│  ┌─────────────┐                                           │   └────────────────────────────────────────────────────────┘
│  │ nv-branch2  │                                           │
│  │  VPC 10.30  │                                           │
│  └─────────────┘                                           │
└────────────────────────────────────────────────────────────┘

Each instance: Ubuntu 22.04 (c5.large) → LXD → VyOS container
3 ENIs per instance: Management | Outside (WAN) | Inside (LAN)
```

## What It Does

1. **Provisions VPC infrastructure** across 2 AWS regions (5 VPCs, each with public/private subnets, NAT gateways, and internet gateways)
2. **Deploys Ubuntu EC2 instances** with 3 network interfaces each, Elastic IPs, and security groups for VPN traffic
3. **Creates AWS Cloud WAN** global network, core network with policy, VPC attachments, tunnel-less Connect attachments, and Connect peers
4. **Bootstraps VyOS routers** inside LXD containers via cloud-init user data
5. **Configures IPsec VPN tunnels** (IKEv2, AES-256, SHA-256) and **eBGP peering** between SD-WAN and branch routers
6. **Configures Cloud WAN BGP** — tunnel-less eBGP sessions between SDWAN routers and Cloud WAN Connect peers for cross-region route propagation
7. **Verifies connectivity** — IPsec SA status, BGP sessions (VPN and Cloud WAN), interface state, VTI ping tests, and persists results to SSM Parameter Store at `/sdwan/verification-results`
8. **Orchestrates everything** via AWS Step Functions + Lambda — no local scripts needed after `terraform apply`

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- AWS CLI configured with credentials for 2 regions (`us-east-1` and `eu-central-1`)
- An S3 bucket containing the VyOS LXD image (default: `fra-vyos-bucket` in `us-east-1`)


## Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Review the plan
terraform plan

# 3. Deploy infrastructure (Cloud WAN resources can take 10-15 minutes)
terraform apply

# 4. Start the SD-WAN configuration orchestration
#    The command is printed as a Terraform output after apply:
terraform output -raw start_orchestration_command | bash
```

After `terraform apply` completes, the `start_orchestration_command` output provides the exact AWS CLI command to trigger the Step Functions state machine. You can also copy it from the Terraform output and run it manually.

The state machine runs 4 phases automatically:

| Phase | Lambda | What It Does | Wait After |
|-------|--------|-------------|------------|
| Phase 1 | `sdwan-phase1` | Installs packages, initializes LXD, deploys VyOS container, applies DHCP config | 60s |
| Phase 2 | `sdwan-phase2` | Pushes IPsec tunnel and BGP peering configuration to each VyOS router | 90s |
| Phase 3 | `sdwan-phase3` | Cloud WAN BGP configuration — configures tunnel-less BGP neighbors on SDWAN routers | 30s |
| Phase 4 | `sdwan-phase4` | Verification: IPsec, BGP, Cloud WAN BGP, connectivity — checks all sessions and persists results to SSM | — |

## Project Structure

```
.
├── main.tf                    # Terraform version and provider requirements
├── providers.tf               # AWS provider config (default + frankfurt + virginia)
├── variables.tf               # Input variables
├── locals.tf                  # Local values (CIDRs, VPN PSK, tags)
├── outputs.tf                 # Instance IDs, EIPs, Cloud WAN config, orchestration command
│
├── vpc-frankfurt.tf           # Frankfurt VPCs (fra-branch1, fra-sdwan)
├── vpc-virginia.tf            # Virginia VPCs (nv-branch1, nv-branch2, nv-sdwan)
├── instances-common.tf        # Shared IAM role and instance profile
├── instances-frankfurt.tf     # Frankfurt EC2 instances, ENIs, EIPs, SGs
├── instances-virginia.tf      # Virginia EC2 instances, ENIs, EIPs, SGs
│
├── cloudwan.tf                # Cloud WAN: global network, core network, policy,
│                              #   VPC attachments, Connect attachments, Connect peers,
│                              #   VPC route table entries
├── ssm-parameters.tf          # SSM Parameter Store for Lambda runtime config
├── lambda.tf                  # Lambda functions (Phase 1-4) + IAM role
├── stepfunctions.tf           # Step Functions state machine + IAM role
│
├── lambda/                    # Lambda function source code
│   ├── ssm_utils.py           # Shared SSM utilities (parameter reads, command execution)
│   ├── phase1_handler.py      # Phase 1: base setup (packages, LXD, VyOS)
│   ├── phase2_handler.py      # Phase 2: VPN/BGP configuration
│   ├── phase3_handler.py      # Phase 3: Cloud WAN BGP configuration
│   └── phase4_handler.py      # Phase 4: verification
```

## Configuration

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `sdwan_instance_type` | `c5.large` | EC2 instance type for SD-WAN hosts |
| `vyos_s3_bucket` | `fra-vyos-bucket` | S3 bucket with VyOS LXD image |
| `vyos_s3_key` | `vyos_dxgl-1.3.3-bc64a3a-5_lxd_amd64.tar.gz` | VyOS image filename in S3 |
| `vpn_psk` | auto-generated | IPsec pre-shared key (32 chars if not set) |
| `sdwan_bgp_asn` | `65001` | BGP ASN for SD-WAN routers |
| `branch1_bgp_asn` | `65002` | BGP ASN for branch routers |
| `cloudwan_asn` | `64512` | BGP ASN for Cloud WAN core network |
| `cloudwan_connect_cidr_nv` | `10.100.0.0/24` | Cloud WAN inside CIDR for us-east-1 edge |
| `cloudwan_connect_cidr_fra` | `10.100.1.0/24` | Cloud WAN inside CIDR for eu-central-1 edge |
| `cloudwan_segment_name` | `sdwan` | Cloud WAN segment name |

### VPN Topology (Intra-Region)

| Tunnel | VTI A | VTI B | Encryption |
|--------|-------|-------|------------|
| nv-sdwan ↔ nv-branch1 | 169.254.100.1/30 | 169.254.100.2/30 | AES-256 / SHA-256 / IKEv2 |
| fra-sdwan ↔ fra-branch1 | 169.254.100.13/30 | 169.254.100.14/30 | AES-256 / SHA-256 / IKEv2 |

### Cloud WAN BGP (Cross-Region, Tunnel-less)

| Router | Cloud WAN Peer IPs | Remote ASN | Transport |
|--------|--------------------|------------|-----------|
| nv-sdwan | Auto-assigned from 10.100.0.0/24 | 64512 | NO_ENCAP (VPC fabric) |
| fra-sdwan | Auto-assigned from 10.100.1.0/24 | 64513 | NO_ENCAP (VPC fabric) |

Cloud WAN assigns 2 BGP peer IPs per Connect peer for redundancy. The actual IPs are stored in SSM Parameter Store and read by the Phase 3 Lambda at runtime.

### Network CIDRs

| VPC | Region | CIDR |
|-----|--------|------|
| nv-branch1 | us-east-1 | 10.20.0.0/20 |
| nv-branch2 | us-east-1 | 10.30.0.0/20 |
| nv-sdwan | us-east-1 | 10.201.0.0/16 |
| fra-branch1 | eu-central-1 | 10.10.0.0/20 |
| fra-sdwan | eu-central-1 | 10.200.0.0/16 |
| Cloud WAN inside | Global | 10.100.0.0/16 |

## Cleanup

```bash
terraform destroy
```

Note: Cloud WAN resources can take 5-15 minutes to delete.

## License

This project is provided as-is for workshop and educational purposes.

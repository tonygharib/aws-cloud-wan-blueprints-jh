# SD-WAN Cloud WAN Workshop — Terraform

Deploy a multi-region SD-WAN overlay network on AWS with Cloud WAN backbone using Terraform. This project provisions Ubuntu EC2 instances running VyOS routers inside LXD containers, establishes IPsec VPN tunnels with BGP peering, integrates AWS Cloud WAN with tunnel-less Connect attachments for cross-region route propagation, enforces multi-segment traffic isolation via BGP community tagging, and orchestrates the entire configuration lifecycle through AWS Step Functions.

## Architecture

```
┌──────────────────────── us-east-1 ────────────────────────┐   ┌───────────────────── eu-central-1 ─────────────────────┐
│                                                            │   │                                                        │
│  ┌─────────────┐    IPsec/BGP    ┌─────────────┐          │   │  ┌─────────────┐    IPsec/BGP    ┌───────────┐         │
│  │  nv-sdwan   │◄──────────────►│ nv-branch1  │          │   │  │  fra-sdwan  │◄──────────────►│fra-branch1│         │
│  │  ASN 64501  │  VTI 100.1/2   │  ASN 64503  │          │   │  │  ASN 64502  │  VTI 100.13/14 │ ASN 64505 │         │
│  │  VPC 10.201 │                 │  VPC 10.20  │          │   │  │  VPC 10.200 │                │ VPC 10.10 │         │
│  │  route-map  │                 │dum0 Prod    │          │   │  │  route-map  │                │dum0 Prod  │         │
│  │  CLOUDWAN-  │                 │dum1 Dev     │          │   │  │  CLOUDWAN-  │                │dum1 Dev   │         │
│  │  OUT        │                 │             │          │   │  │  OUT        │                │           │         │
│  └──────┬──────┘                 └─────────────┘          │   │  └──────┬──────┘                └───────────┘         │
│         │ BGP (tunnel-less, NO_ENCAP)                      │   │         │ BGP (tunnel-less, NO_ENCAP)                  │
│         │ community tagging: *:100 Prod, *:200 Dev         │   │         │ community tagging: *:100 Prod, *:200 Dev     │
│  ┌──────┴──────────────────────────────────────────────────┴───┴─────────┴──────┐                                       │
│  │                    AWS Cloud WAN Core Network (v2025.11)                      │                                       │
│  │         Segments: sdwan | Prod | Dev    Inside CIDR: 10.100.0.0/16           │                                       │
│  │         Routing policies: community-based filtering per segment               │                                       │
│  └──────────────────────────────────────────────────────────────────────────────┘                                       │
│                                                            │   │                                                        │
│  ┌─────────────┐                                           │   └────────────────────────────────────────────────────────┘
│  │ nv-branch2  │                                           │
│  │  ASN 64504  │                                           │
│  │  VPC 10.30  │                                           │
│  └─────────────┘                                           │
└────────────────────────────────────────────────────────────┘

Each instance: Ubuntu 22.04 (c5.large) → LXD → VyOS container
3 ENIs per instance: Management | Outside (WAN) | Inside (LAN)
```

## What It Does

1. **Provisions VPC infrastructure** across 2 AWS regions (5 VPCs, each with public/private subnets, NAT gateways, and internet gateways) using the `terraform-aws-modules/vpc/aws` module
2. **Deploys Ubuntu EC2 instances** with 3 network interfaces each, Elastic IPs, and security groups for VPN traffic
3. **Creates AWS Cloud WAN** global network, core network with external JSON policy (`cloudwan_policy.json`), VPC attachments, tunnel-less Connect attachments, and Connect peers
4. **Stores runtime config in SSM Parameter Store** — instance IDs, EIPs, private IPs, and Cloud WAN peer addresses under `/sdwan/` for Lambda consumption
5. **Bootstraps VyOS routers** inside LXD containers with correct file permissions for the vyos user
6. **Configures IPsec VPN tunnels** (IKEv2, AES-256, SHA-256) and **eBGP peering** between SD-WAN and branch routers, with dummy interfaces on branches for Prod/Dev segment traffic
7. **Configures Cloud WAN BGP** — tunnel-less eBGP sessions between SDWAN routers and Cloud WAN Connect peers, with route-maps (`CLOUDWAN-OUT`) for BGP community tagging (Prod=`*:100`, Dev=`*:200`)
8. **Enforces segment isolation** — Cloud WAN routing policies (v2025.11) match BGP communities and filter routes into Prod and Dev segments via `segment-actions` share rules
9. **Verifies connectivity** — IPsec SA status, BGP sessions (VPN and Cloud WAN), interface state, VTI ping tests, and persists results to SSM Parameter Store at `/sdwan/verification-results`
10. **Orchestrates everything** via AWS Step Functions + Lambda — no local scripts needed after `terraform apply`

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
| Phase 1 | `sdwan-phase1` | Installs packages, initializes LXD, deploys VyOS container, applies DHCP config, fixes VyOS config file permissions (`chown vyos:vyattacfg`) | 60s |
| Phase 2 | `sdwan-phase2` | Pushes IPsec tunnel and BGP peering config; creates dummy interfaces (dum0/dum1) on branch routers for Prod/Dev segment prefixes | 90s |
| Phase 3 | `sdwan-phase3` | Cloud WAN BGP config — tunnel-less BGP neighbors on SDWAN routers, prefix-lists, route-map `CLOUDWAN-OUT` with community tagging | 30s |
| Phase 4 | `sdwan-phase4` | Verification: IPsec, BGP, Cloud WAN BGP, connectivity — checks all sessions and persists results to SSM | — |

## Project Structure

```
.
├── main.tf                    # Terraform version, provider requirements, multi-region config
├── variables.tf               # Input variables (ASNs, dummy addresses, communities, etc.)
├── locals.tf                  # Local values (VPC CIDRs, VPN PSK, tags)
├── outputs.tf                 # Instance IDs, EIPs, Cloud WAN config, orchestration command
│
├── vpc.tf                     # All 5 VPCs across both regions (terraform-aws-modules/vpc/aws)
├── instances.tf               # IAM roles, AMI data sources, security groups, EC2 instances,
│                              #   ENIs (mgmt/outside/inside), EIPs — all regions
├── cloudwan.tf                # Cloud WAN: global network, core network, policy attachment
│                              #   (references cloudwan_policy.json), VPC attachments,
│                              #   Connect attachments, Connect peers, VPC route table entries
├── cloudwan_policy.json       # Cloud WAN core network policy (v2025.11) with segments
│                              #   (sdwan, Prod, Dev), segment-actions, routing policies,
│                              #   and community-based route filtering
├── ssm-parameters.tf          # SSM Parameter Store for Lambda runtime config
│                              #   (instance IDs, EIPs, private IPs, Cloud WAN peer IPs/ASNs)
├── orchestration.tf           # Lambda functions (Phase 1-4), IAM roles, Step Functions
│                              #   state machine, CloudWatch log group
│
└── lambda/                    # Lambda function source code (Python 3.12)
    ├── ssm_utils.py           # Shared SSM utilities (parameter reads, command execution)
    ├── phase1_handler.py      # Phase 1: base setup (packages, LXD, VyOS, permissions fix)
    ├── phase2_handler.py      # Phase 2: VPN/BGP config + dummy interfaces on branches
    ├── phase3_handler.py      # Phase 3: Cloud WAN BGP config + route-maps + community tagging
    ├── phase4_handler.py      # Phase 4: verification (IPsec, BGP, Cloud WAN BGP, ping)
    └── phase4_cloudwan_bgp.py # Cloud WAN BGP vbash script generation
```

## Configuration

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `sdwan_instance_type` | `c5.large` | EC2 instance type for SD-WAN hosts |
| `vyos_s3_bucket` | `fra-vyos-bucket` | S3 bucket with VyOS LXD image |
| `vyos_s3_key` | `vyos_dxgl-1.3.3-...tar.gz` | VyOS image filename in S3 |
| `vpn_psk` | auto-generated | IPsec pre-shared key (32 chars if not set) |
| `nv_sdwan_bgp_asn` | `64501` | BGP ASN for nv-sdwan |
| `fra_sdwan_bgp_asn` | `64502` | BGP ASN for fra-sdwan |
| `nv_branch1_bgp_asn` | `64503` | BGP ASN for nv-branch1 |
| `nv_branch2_bgp_asn` | `64504` | BGP ASN for nv-branch2 |
| `fra_branch1_bgp_asn` | `64505` | BGP ASN for fra-branch1 |
| `nv_branch1_prod_dummy` | `10.250.1.1/32` | nv-branch1 dum0 (Prod) address |
| `nv_branch1_dev_dummy` | `10.250.1.2/32` | nv-branch1 dum1 (Dev) address |
| `fra_branch1_prod_dummy` | `10.250.2.1/32` | fra-branch1 dum0 (Prod) address |
| `fra_branch1_dev_dummy` | `10.250.2.2/32` | fra-branch1 dum1 (Dev) address |
| `bgp_community_prod` | `100` | Community value suffix for Prod routes |
| `bgp_community_dev` | `200` | Community value suffix for Dev routes |
| `cloudwan_connect_cidr_nv` | `10.100.0.0/24` | Cloud WAN inside CIDR for us-east-1 |
| `cloudwan_connect_cidr_fra` | `10.100.1.0/24` | Cloud WAN inside CIDR for eu-central-1 |
| `cloudwan_segment_name` | `sdwan` | Cloud WAN segment name for SDWAN attachments |
| `phase1_wait_seconds` | `60` | Wait time after Phase 1 before Phase 2 |
| `phase2_wait_seconds` | `90` | Wait time after Phase 2 before Phase 3 |

### BGP ASN Assignment

Each router has a unique ASN in the 64501–64505 range, deliberately below the Cloud WAN allocation window (64512–65534) to avoid conflicts:

| Router | ASN | Role |
|--------|-----|------|
| nv-sdwan | 64501 | SDWAN hub (us-east-1) |
| fra-sdwan | 64502 | SDWAN hub (eu-central-1) |
| nv-branch1 | 64503 | Branch (us-east-1) |
| nv-branch2 | 64504 | Branch (us-east-1) |
| fra-branch1 | 64505 | Branch (eu-central-1) |

### VPN Topology (Intra-Region)

| Tunnel | VTI A | VTI B | Encryption |
|--------|-------|-------|------------|
| nv-sdwan ↔ nv-branch1 | 169.254.100.1/30 | 169.254.100.2/30 | AES-256 / SHA-256 / IKEv2 |
| fra-sdwan ↔ fra-branch1 | 169.254.100.13/30 | 169.254.100.14/30 | AES-256 / SHA-256 / IKEv2 |

### Cloud WAN BGP (Cross-Region, Tunnel-less)

| Router | Cloud WAN Peer IPs | Remote ASN | Transport |
|--------|--------------------|------------|-----------|
| nv-sdwan (64501) | Auto-assigned from 10.100.0.0/24 | 64512 | NO_ENCAP (VPC fabric) |
| fra-sdwan (64502) | Auto-assigned from 10.100.1.0/24 | 64513 | NO_ENCAP (VPC fabric) |

Cloud WAN assigns 2 BGP peer IPs per Connect peer for redundancy. The actual IPs are stored in SSM Parameter Store and read by the Phase 3 Lambda at runtime.

### BGP Segmentation

Cloud WAN policy (v2025.11) defines three segments with routing policies for community-based filtering:

| Segment | Purpose | Community Match | Routing Policy |
|---------|---------|-----------------|----------------|
| sdwan | SD-WAN hub connectivity | — (default) | — |
| Prod | Production traffic | `64501:100`, `64502:100` | `filterProdRoutes` |
| Dev | Development traffic | `64501:200`, `64502:200` | `filterDevRoutes` |

Route flow: Branch dummy interfaces → eBGP to SDWAN hub → route-map `CLOUDWAN-OUT` (community tagging) → Cloud WAN sdwan segment → `segment-actions` share with routing policy → Prod/Dev segments.

### Dummy Interfaces (Branch Routers)

| Router | Interface | Address | Segment |
|--------|-----------|---------|---------|
| nv-branch1 | dum0 | 10.250.1.1/32 | Prod |
| nv-branch1 | dum1 | 10.250.1.2/32 | Dev |
| fra-branch1 | dum0 | 10.250.2.1/32 | Prod |
| fra-branch1 | dum1 | 10.250.2.2/32 | Dev |

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

Note: Cloud WAN resources can take 5–15 minutes to delete.

## License

This project is provided as-is for workshop and educational purposes.

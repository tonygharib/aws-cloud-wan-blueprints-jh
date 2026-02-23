# SD-WAN Cloud WAN Workshop — Terraform

Deploy a multi-region SD-WAN overlay network on AWS using Terraform. This project provisions Ubuntu EC2 instances running VyOS routers inside LXD containers, establishes IPsec VPN tunnels with BGP peering, and orchestrates the entire configuration lifecycle through AWS Step Functions.

## Architecture

```
┌─────────────────── us-east-1 ───────────────────┐   ┌──────────────── eu-central-1 ────────────────┐
│                                                   │   │                                               │
│  ┌─────────────┐    IPsec/BGP    ┌─────────────┐ │   │  ┌─────────────┐    IPsec/BGP  ┌───────────┐ │
│  │  nv-sdwan   │◄──────────────►│ nv-branch1  │ │   │  │  fra-sdwan  │◄────────────►│fra-branch1│ │
│  │  ASN 65001  │  VTI 100.1/2   │  ASN 65002  │ │   │  │  ASN 65001  │ VTI 100.13/14│ ASN 65002 │ │
│  │  VPC 10.201 │                 │  VPC 10.20  │ │   │  │  VPC 10.200 │              │ VPC 10.10 │ │
│  └─────────────┘                 └─────────────┘ │   │  └─────────────┘              └───────────┘ │
│                                                   │   │                                               │
│  ┌─────────────┐                                  │   └───────────────────────────────────────────────┘
│  │ nv-branch2  │                                  │
│  │  VPC 10.30  │                                  │
│  └─────────────┘                                  │
└───────────────────────────────────────────────────┘

Each instance: Ubuntu 22.04 (c5.large) → LXD → VyOS container
3 ENIs per instance: Management | Outside (WAN) | Inside (LAN)
```

## What It Does

1. **Provisions VPC infrastructure** across 2 AWS regions (5 VPCs, each with public/private subnets, NAT gateways, and internet gateways)
2. **Deploys Ubuntu EC2 instances** with 3 network interfaces each, Elastic IPs, and security groups for VPN traffic (IKE/NAT-T/ESP)
3. **Bootstraps VyOS routers** inside LXD containers via cloud-init user data
4. **Configures IPsec VPN tunnels** (IKEv2, AES-256, SHA-256) and **eBGP peering** between SD-WAN and branch routers
5. **Verifies connectivity** — IPsec SA status, BGP sessions, interface state, and VTI ping tests
6. **Orchestrates everything** via AWS Step Functions + Lambda, so no local machine is needed after `terraform apply`

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- AWS CLI configured with credentials for 2 regions (`us-east-1` and `eu-central-1`)
- An S3 bucket containing the VyOS LXD image (default: `fra-vyos-bucket` in `us-east-1`)
- Python 3.12+ (for running tests locally)

## Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Review the plan
terraform plan

# 3. Deploy infrastructure
terraform apply

# 4. Run the SD-WAN configuration orchestration
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw sdwan_state_machine_arn 2>/dev/null || echo "check AWS console") \
  --region us-east-1
```

The Step Functions state machine runs 3 phases automatically:

| Phase | What It Does | Wait After |
|-------|-------------|------------|
| Phase 1 — Base Setup | Installs packages, initializes LXD, deploys VyOS container, applies DHCP config | 60s |
| Phase 2 — VPN/BGP Config | Pushes IPsec tunnel and BGP peering configuration to each VyOS router | 90s |
| Phase 3 — Verification | Checks IPsec SA, BGP summary, interfaces, and runs VTI ping tests | — |

### Running Phases Manually (Bash Scripts)

You can also run the configuration phases from your local machine using the bash scripts:

```bash
./phase1-base-setup.sh
./phase2-vpn-bgp-config.sh
./phase3-verify.sh
```

These scripts read instance IDs from `terraform output` and use SSM Run Command to configure the instances.

## Project Structure

```
.
├── main.tf                    # Terraform version and provider requirements
├── providers.tf               # AWS provider config (frankfurt + virginia)
├── variables.tf               # Input variables
├── locals.tf                  # Local values (CIDRs, VPN PSK, tags)
├── outputs.tf                 # Instance IDs, EIPs, VPN config outputs
│
├── vpc-frankfurt.tf           # Frankfurt VPCs (fra-branch1, fra-sdwan)
├── vpc-virginia.tf            # Virginia VPCs (nv-branch1, nv-branch2, nv-sdwan)
├── instances-frankfurt.tf     # Frankfurt EC2 instances, ENIs, EIPs, SGs
├── instances-virginia.tf      # Virginia EC2 instances, ENIs, EIPs, SGs
│
├── ssm-parameters.tf          # SSM Parameter Store for Lambda runtime config
├── lambda.tf                  # Lambda functions + IAM role
├── stepfunctions.tf           # Step Functions state machine + IAM role
│
├── lambda/                    # Lambda function source code
│   ├── ssm_utils.py           # Shared SSM utilities (parameter reads, command execution)
│   ├── phase1_handler.py      # Phase 1: base setup
│   ├── phase2_handler.py      # Phase 2: VPN/BGP configuration
│   └── phase3_handler.py      # Phase 3: verification
│
├── templates/
│   └── user_data.sh           # Cloud-init bootstrap script
│
├── phase1-base-setup.sh       # Local bash script — Phase 1
├── phase2-vpn-bgp-config.sh   # Local bash script — Phase 2
├── phase3-verify.sh           # Local bash script — Phase 3
│
└── tests/                     # Property-based tests (Hypothesis)
    ├── test_phase1_properties.py
    ├── test_phase2_properties.py
    ├── test_phase3_properties.py
    └── test_ssm_utils_properties.py
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
| `phase1_wait_seconds` | `60` | Wait between Phase 1 and Phase 2 |
| `phase2_wait_seconds` | `90` | Wait between Phase 2 and Phase 3 |

### VPN Topology

Tunnels are intra-region only:

| Tunnel | VTI A | VTI B | Encryption |
|--------|-------|-------|------------|
| nv-sdwan ↔ nv-branch1 | 169.254.100.1/30 | 169.254.100.2/30 | AES-256 / SHA-256 / IKEv2 |
| fra-sdwan ↔ fra-branch1 | 169.254.100.13/30 | 169.254.100.14/30 | AES-256 / SHA-256 / IKEv2 |

### Network CIDRs

| VPC | Region | CIDR |
|-----|--------|------|
| nv-branch1 | us-east-1 | 10.20.0.0/20 |
| nv-branch2 | us-east-1 | 10.30.0.0/20 |
| nv-sdwan | us-east-1 | 10.201.0.0/16 |
| fra-branch1 | eu-central-1 | 10.10.0.0/20 |
| fra-sdwan | eu-central-1 | 10.200.0.0/16 |

## Testing

Tests use [Hypothesis](https://hypothesis.readthedocs.io/) for property-based testing of the Lambda configuration logic.

```bash
pip install hypothesis pytest

pytest tests/ -v
```

Tests validate:
- Phase 1 command payloads contain all required packages and correct snap ordering
- Phase 2 IPsec address fields, encryption algorithms, tunnel topology, and BGP ASN consistency
- Phase 3 ping targets match VTI peer addresses from the tunnel topology
- SSM utility functions produce correct parameter paths and region mappings

## Cleanup

```bash
terraform destroy
```

## License

This project is provided as-is for workshop and educational purposes.

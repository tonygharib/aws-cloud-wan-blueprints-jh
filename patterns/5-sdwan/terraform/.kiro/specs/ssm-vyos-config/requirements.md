# Requirements Document

## Introduction

This feature replaces the unreliable cloud-init user_data.sh bootstrap mechanism with a phased SSM Run Command approach for configuring 5 SD-WAN Ubuntu 22.04 EC2 instances across two AWS regions (Frankfurt: fra-branch1, fra-sdwan; Virginia: nv-branch1, nv-branch2, nv-sdwan). Each instance hosts a VyOS LXC container with 3 ENIs (management, outside, internal). The new approach decouples instance provisioning from configuration by removing user_data from Terraform instance definitions and instead executing configuration via local bash scripts that invoke AWS SSM Run Command after Terraform completes infrastructure deployment. Configuration is split into three phases: base setup (LXD + VyOS container), VPN/BGP configuration, and verification.

## Glossary

- **SSM_Run_Command**: AWS Systems Manager Run Command — a service that executes shell commands on managed EC2 instances remotely without SSH access.
- **Phase1_Script**: A local bash script (phase1-base-setup.sh) that uses SSM Run Command to install packages, initialize LXD, deploy the VyOS LXC container, and apply base DHCP configuration on all 5 instances.
- **Phase2_Script**: A local bash script (phase2-vpn-bgp-config.sh) that uses SSM Run Command to push IPsec VPN and BGP configuration to each VyOS router via lxc exec.
- **Phase3_Script**: A local bash script (phase3-verify.sh) that uses SSM Run Command to verify IPsec tunnel status, BGP peering, interface status, and connectivity across all instances.
- **Instance_ID**: The EC2 instance identifier used by SSM to target a specific instance for command execution.
- **VyOS_Container**: The LXC container named "router" running VyOS inside each Ubuntu instance, with eth0 mapped to ens6 (outside ENI) and eth1 mapped to ens7 (internal ENI).
- **Base_Config**: The initial VyOS config.boot with DHCP on eth0 and eth1, hostname, and vyos user credentials.
- **Phase1_VyOS_Script**: A vbash script pushed into the VyOS container that sets DHCP with route distances (eth0 distance 10, eth1 distance 210).
- **VPN_Config**: IPsec IKEv2 site-to-site VPN configuration using pre-shared keys and VTI interfaces between VyOS routers.
- **BGP_Config**: eBGP peering configuration over VTI interfaces using private ASNs (65001 for sdwan routers, 65002 for branch routers).
- **Outside_EIP**: The Elastic IP on the outside ENI of each instance, used as the VPN tunnel endpoint address.
- **Terraform_Output**: Values exported by Terraform (instance IDs, EIPs) consumed by the SSM configuration scripts.

## Requirements

### Requirement 1: Remove user_data from Terraform Instance Definitions

**User Story:** As a DevOps engineer, I want user_data removed from all 5 EC2 instance definitions, so that instances deploy as bare Ubuntu hosts without unreliable cloud-init bootstrap scripts.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL remove the user_data argument from the aws_instance resource for nv-branch1 in instances-virginia.tf.
2. THE Terraform_Configuration SHALL remove the user_data argument from the aws_instance resource for nv-branch2 in instances-virginia.tf.
3. THE Terraform_Configuration SHALL remove the user_data argument from the aws_instance resource for nv-sdwan in instances-virginia.tf.
4. THE Terraform_Configuration SHALL remove the user_data argument from the aws_instance resource for fra-branch1 in instances-frankfurt.tf.
5. THE Terraform_Configuration SHALL remove the user_data argument from the aws_instance resource for fra-sdwan in instances-frankfurt.tf.
6. WHEN Terraform applies the updated configuration, THE Ubuntu_Instance SHALL launch with no user_data script attached.

### Requirement 2: Terraform Instance ID Outputs

**User Story:** As a DevOps engineer, I want Terraform to output the EC2 instance IDs for all 5 instances, so that the SSM configuration scripts can target the correct instances.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL define an output named "nv_branch1_instance_id" containing the instance ID of the nv-branch1 Ubuntu_Instance.
2. THE Terraform_Configuration SHALL define an output named "nv_branch2_instance_id" containing the instance ID of the nv-branch2 Ubuntu_Instance.
3. THE Terraform_Configuration SHALL define an output named "nv_sdwan_instance_id" containing the instance ID of the nv-sdwan Ubuntu_Instance.
4. THE Terraform_Configuration SHALL define an output named "fra_branch1_instance_id" containing the instance ID of the fra-branch1 Ubuntu_Instance.
5. THE Terraform_Configuration SHALL define an output named "fra_sdwan_instance_id" containing the instance ID of the fra-sdwan Ubuntu_Instance.

### Requirement 3: Phase 1 Base Setup Script

**User Story:** As a network engineer, I want a local bash script that configures all 5 instances via SSM Run Command with LXD, VyOS container, and base DHCP configuration, so that I can reliably set up the SD-WAN appliances after Terraform deploys the infrastructure.

#### Acceptance Criteria

1. THE Phase1_Script SHALL be a bash script named "phase1-base-setup.sh" located in the project root directory.
2. THE Phase1_Script SHALL define configurable variables at the top of the script for: VyOS S3 bucket name, S3 region, S3 object key, and ubuntu user password.
3. THE Phase1_Script SHALL accept instance IDs as command-line parameters or read them from terraform output.
4. THE Phase1_Script SHALL handle instances in both us-east-1 and eu-central-1 regions by issuing separate SSM send-command calls per region.
5. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL run apt-get update and install python3-pip, net-tools, tmux, curl, unzip, and jq on the target instance.
6. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL run "snap wait system seed.loaded" before installing lxd and aws-cli via snap.
7. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL set the ubuntu user password to the configured password value.
8. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL initialize LXD with a preseed configuration using a directory-backed storage pool named "default".
9. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL download the VyOS LXD image from the configured S3 bucket and import it with the alias "vyos".
10. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL create an LXC container named "router" with eth0 mapped to ens6 and eth1 mapped to ens7, with 1 CPU and 2048MiB memory limits.
11. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL push a base config.boot to the router container with DHCP on eth0 and eth1, and a vyos user with the configured password.
12. WHEN the Phase1_Script executes an SSM command, THE SSM_Run_Command SHALL start the router container, wait 30 seconds, then push and execute a Phase1_VyOS_Script that sets DHCP with route distances (eth0 distance 10, eth1 distance 210).
13. THE Phase1_Script SHALL be independently rerunnable without causing errors on already-configured instances.
14. THE Phase1_Script SHALL wait for each SSM command to complete and report success or failure for each instance.

### Requirement 4: Phase 2 VPN and BGP Configuration Script

**User Story:** As a network engineer, I want a local bash script that pushes VPN and BGP configuration to each VyOS router via SSM, so that IPsec tunnels and BGP peering are established between all SD-WAN sites.

#### Acceptance Criteria

1. THE Phase2_Script SHALL be a bash script named "phase2-vpn-bgp-config.sh" located in the project root directory.
2. THE Phase2_Script SHALL read Outside_EIP addresses from terraform output or accept them as command-line parameters.
3. THE Phase2_Script SHALL read instance IDs from terraform output or accept them as command-line parameters.
4. THE Phase2_Script SHALL configure IPsec IKEv2 VPN tunnels between sites using Outside_EIPs as tunnel endpoints and "aws123" as the pre-shared key.
5. THE Phase2_Script SHALL configure VTI interfaces on each router with /30 point-to-point subnets from the 169.254.x.x range for tunnel addressing.
6. THE Phase2_Script SHALL configure eBGP peering over VTI interfaces using ASN 65001 for sdwan routers and ASN 65002 for branch routers.
7. THE Phase2_Script SHALL configure loopback interfaces on each router with unique /32 addresses for BGP router-id and route advertisement.
8. THE Phase2_Script SHALL push VPN and BGP configuration to each VyOS router by executing vbash configuration scripts via "lxc exec router" through SSM Run Command.
9. THE Phase2_Script SHALL handle instances in both us-east-1 and eu-central-1 regions.
10. THE Phase2_Script SHALL be independently rerunnable without causing errors on already-configured routers.

### Requirement 5: Phase 3 Verification Script

**User Story:** As a network engineer, I want a local bash script that verifies the deployment status of all VPN tunnels, BGP sessions, and interfaces across all 5 instances, so that I can confirm the SD-WAN overlay is operational.

#### Acceptance Criteria

1. THE Phase3_Script SHALL be a bash script named "phase3-verify.sh" located in the project root directory.
2. THE Phase3_Script SHALL read instance IDs from terraform output or accept them as command-line parameters.
3. WHEN the Phase3_Script executes, THE SSM_Run_Command SHALL run "show vpn ipsec sa" on each VyOS router to check IPsec tunnel status.
4. WHEN the Phase3_Script executes, THE SSM_Run_Command SHALL run "show ip bgp summary" on each VyOS router to check BGP neighbor status.
5. WHEN the Phase3_Script executes, THE SSM_Run_Command SHALL run "show interfaces" on each VyOS router to check interface status.
6. WHEN the Phase3_Script executes, THE SSM_Run_Command SHALL run ping tests across VTI tunnel interfaces to verify end-to-end connectivity.
7. THE Phase3_Script SHALL format verification output in a readable, per-instance summary format.
8. THE Phase3_Script SHALL handle instances in both us-east-1 and eu-central-1 regions.
9. THE Phase3_Script SHALL be independently rerunnable at any time for status checking.

### Requirement 6: Script Idempotency and Error Handling

**User Story:** As a DevOps engineer, I want all SSM configuration scripts to be safely rerunnable and provide clear error reporting, so that I can retry failed configurations without side effects.

#### Acceptance Criteria

1. WHEN the Phase1_Script encounters an already-initialized LXD installation, THE SSM_Run_Command SHALL skip LXD initialization without error.
2. WHEN the Phase1_Script encounters an existing "router" LXC container, THE SSM_Run_Command SHALL stop and delete the existing container before recreating it.
3. WHEN an SSM command fails on an instance, THE Script SHALL report the failure with the instance name and continue processing remaining instances.
4. WHEN an SSM command times out, THE Script SHALL report the timeout and continue processing remaining instances.
5. THE Phase1_Script SHALL verify that each target instance is registered with SSM before attempting to send commands.
6. THE Phase2_Script SHALL verify that the VyOS router container is running on each instance before pushing VPN/BGP configuration.

### Requirement 7: Multi-Region SSM Command Execution

**User Story:** As a DevOps engineer, I want the scripts to correctly handle SSM commands across both us-east-1 and eu-central-1 regions, so that all 5 instances are configured regardless of their region.

#### Acceptance Criteria

1. THE Phase1_Script SHALL issue SSM send-command calls with --region us-east-1 for nv-branch1, nv-branch2, and nv-sdwan instances.
2. THE Phase1_Script SHALL issue SSM send-command calls with --region eu-central-1 for fra-branch1 and fra-sdwan instances.
3. THE Phase2_Script SHALL issue SSM send-command calls with the correct --region flag matching each instance's deployment region.
4. THE Phase3_Script SHALL issue SSM send-command calls with the correct --region flag matching each instance's deployment region.
5. WHEN waiting for SSM command completion, THE Script SHALL use the correct region when calling ssm get-command-invocation.

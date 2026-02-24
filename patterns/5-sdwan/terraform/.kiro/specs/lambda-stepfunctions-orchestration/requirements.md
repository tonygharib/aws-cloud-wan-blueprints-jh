# Requirements Document

## Introduction

This feature replaces the local bash scripts (phase1-base-setup.sh, phase2-vpn-bgp-config.sh, phase3-verify.sh) with AWS Lambda functions orchestrated by a Step Functions state machine, all deployed via Terraform. Currently, an operator must run these scripts from a local workstation to configure 4 SD-WAN Ubuntu 22.04 EC2 instances (nv-sdwan, nv-branch1 in us-east-1; fra-sdwan, fra-branch1 in eu-central-1) via SSM Run Command. The new approach moves this orchestration into AWS so no local machine is required. Terraform populates SSM Parameter Store with instance IDs, EIPs, and private IPs, and the Lambda functions read these parameters at runtime. The VPN topology is intra-region only: nv-sdwan↔nv-branch1 and fra-sdwan↔fra-branch1.

## Glossary

- **Phase1_Lambda**: An AWS Lambda function (Python 3.12, boto3) that replicates the base setup logic from phase1-base-setup.sh — installing packages, initializing LXD, deploying the VyOS LXC container, and applying base DHCP configuration on target instances via SSM Run Command.
- **Phase2_Lambda**: An AWS Lambda function (Python 3.12, boto3) that replicates the VPN/BGP configuration logic from phase2-vpn-bgp-config.sh — pushing IPsec VPN and BGP configuration to each VyOS router via SSM Run Command and lxc exec.
- **Phase3_Lambda**: An AWS Lambda function (Python 3.12, boto3) that replicates the verification logic from phase3-verify.sh — checking IPsec SA status, BGP summary, interfaces, and VTI ping tests via SSM Run Command.
- **State_Machine**: An AWS Step Functions state machine that orchestrates the sequential execution of Phase1_Lambda, Phase2_Lambda, and Phase3_Lambda with wait states, error handling, and retry logic.
- **SSM_Parameter**: An AWS Systems Manager Parameter Store parameter populated by Terraform with infrastructure values (instance IDs, EIPs, private IPs) consumed by the Lambda functions at runtime.
- **Lambda_Execution_Role**: An IAM role assumed by the Lambda functions granting permissions for SSM operations and Parameter Store reads.
- **VPN_Topology**: The intra-region IPsec tunnel topology: nv-sdwan↔nv-branch1 (us-east-1) and fra-sdwan↔fra-branch1 (eu-central-1). No cross-region tunnels.
- **VTI**: Virtual Tunnel Interface — a routable interface in VyOS that terminates an IPsec tunnel.
- **Outside_Private_IP**: The private IP address of the outside ENI on each instance, used as the IPsec local-address.
- **Outside_EIP**: The Elastic IP associated with the outside ENI, used as the IPsec peer address.

## Requirements

### Requirement 1: SSM Parameter Store Population via Terraform

**User Story:** As a DevOps engineer, I want Terraform to populate SSM Parameter Store with instance IDs, EIPs, and private IPs, so that Lambda functions can read infrastructure values at runtime without hardcoding.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create SSM_Parameter resources for each of the 4 instances (nv-sdwan, nv-branch1, fra-sdwan, fra-branch1) containing the EC2 instance ID.
2. THE Terraform_Configuration SHALL create SSM_Parameter resources for each of the 4 instances containing the outside ENI Elastic IP address.
3. THE Terraform_Configuration SHALL create SSM_Parameter resources for each of the 4 instances containing the outside ENI private IP address.
4. THE SSM_Parameter names SHALL follow a hierarchical path convention: `/sdwan/{instance-name}/{parameter-type}` (e.g., `/sdwan/nv-sdwan/instance-id`, `/sdwan/nv-sdwan/outside-eip`, `/sdwan/nv-sdwan/outside-private-ip`).
5. THE Terraform_Configuration SHALL create SSM_Parameter resources in the correct region for each instance (us-east-1 for nv-* instances, eu-central-1 for fra-* instances).
6. THE SSM_Parameter values SHALL reference the existing Terraform resource attributes from instances-virginia.tf, instances-frankfurt.tf, and outputs.tf.

### Requirement 2: Phase 1 Lambda Function — Base Setup

**User Story:** As a network engineer, I want a Lambda function that installs packages, initializes LXD, deploys the VyOS container, and applies base DHCP configuration on all 4 instances via SSM, so that base setup runs in AWS without a local machine.

#### Acceptance Criteria

1. THE Phase1_Lambda SHALL be a Python 3.12 Lambda function that uses boto3 to call ssm:SendCommand with the AWS-RunShellScript document.
2. THE Phase1_Lambda SHALL read instance IDs from SSM_Parameter Store at runtime for all 4 instances.
3. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL install packages (python3-pip, net-tools, tmux, curl, unzip, jq), install LXD and aws-cli via snap, and set the ubuntu user password.
4. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL run "snap wait system seed.loaded" before any snap install commands.
5. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL initialize LXD with a preseed configuration using a directory-backed storage pool named "default".
6. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL download the VyOS LXD image from the configured S3 bucket and import it with the alias "vyos".
7. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL create an LXC container named "router" with eth0 mapped to ens6 and eth1 mapped to ens7, with 1 CPU and 2048MiB memory limits.
8. WHEN the Phase1_Lambda sends an SSM command, THE command payload SHALL push a base config.boot to the router container and start it, then push and execute a VyOS script that sets eth0 DHCP with default-route-distance 10 and eth1 DHCP with no-default-route.
9. THE Phase1_Lambda SHALL issue SSM commands with the correct region (us-east-1 for nv-* instances, eu-central-1 for fra-* instances).
10. THE Phase1_Lambda SHALL poll ssm:GetCommandInvocation for each command until completion or timeout, and return a structured result indicating success or failure per instance.
11. THE Phase1_Lambda SHALL handle idempotency by stopping and deleting any existing "router" container before recreating it.

### Requirement 3: Phase 2 Lambda Function — VPN/BGP Configuration

**User Story:** As a network engineer, I want a Lambda function that pushes IPsec VPN and BGP configuration to each VyOS router via SSM, so that VPN tunnels and BGP peering are established without a local machine.

#### Acceptance Criteria

1. THE Phase2_Lambda SHALL be a Python 3.12 Lambda function that uses boto3 to call ssm:SendCommand.
2. THE Phase2_Lambda SHALL read instance IDs, outside EIPs, and outside private IPs from SSM_Parameter Store at runtime.
3. THE Phase2_Lambda SHALL configure IPsec IKEv2 VPN tunnels using the outside private IP as local-address, the peer's outside EIP as the peer address, and the peer's outside private IP as the authentication remote-id.
4. THE Phase2_Lambda SHALL use aes256 (not aes256gcm128) for both IKE and ESP proposal encryption.
5. THE Phase2_Lambda SHALL configure VTI interfaces with /30 point-to-point subnets: nv-sdwan↔nv-branch1 using 169.254.100.1/30 and 169.254.100.2/30, fra-sdwan↔fra-branch1 using 169.254.100.13/30 and 169.254.100.14/30.
6. THE Phase2_Lambda SHALL configure eBGP peering over VTI interfaces using ASN 65001 for sdwan routers and ASN 65002 for branch routers, with ebgp-multihop 2.
7. THE Phase2_Lambda SHALL configure loopback interfaces: nv-sdwan 10.255.0.1/32, nv-branch1 10.255.1.1/32, fra-sdwan 10.255.10.1/32, fra-branch1 10.255.11.1/32.
8. THE Phase2_Lambda SHALL push configuration to each VyOS router by generating a vbash script and executing it via "lxc exec router" through SSM Run Command.
9. THE Phase2_Lambda SHALL issue SSM commands with the correct region for each instance.
10. THE Phase2_Lambda SHALL poll for SSM command completion and return a structured result per instance.
11. THE Phase2_Lambda SHALL enforce intra-region-only VPN topology: nv-sdwan↔nv-branch1 and fra-sdwan↔fra-branch1 with no cross-region tunnels.

### Requirement 4: Phase 3 Lambda Function — Verification

**User Story:** As a network engineer, I want a Lambda function that verifies IPsec tunnel status, BGP sessions, interfaces, and VTI connectivity across all 4 instances, so that I can confirm the SD-WAN overlay is operational without a local machine.

#### Acceptance Criteria

1. THE Phase3_Lambda SHALL be a Python 3.12 Lambda function that uses boto3 to call ssm:SendCommand.
2. THE Phase3_Lambda SHALL read instance IDs from SSM_Parameter Store at runtime.
3. WHEN the Phase3_Lambda executes, THE Lambda SHALL run "show vpn ipsec sa" on each VyOS router via SSM to check IPsec tunnel status.
4. WHEN the Phase3_Lambda executes, THE Lambda SHALL run "show ip bgp summary" on each VyOS router via SSM to check BGP neighbor status.
5. WHEN the Phase3_Lambda executes, THE Lambda SHALL run "show interfaces" on each VyOS router via SSM to check interface status.
6. WHEN the Phase3_Lambda executes, THE Lambda SHALL run ping tests across VTI tunnel interfaces to verify end-to-end connectivity (nv-sdwan pings 169.254.100.2, nv-branch1 pings 169.254.100.1, fra-sdwan pings 169.254.100.14, fra-branch1 pings 169.254.100.13).
7. THE Phase3_Lambda SHALL return a structured JSON result with per-instance verification status including IPsec, BGP, interfaces, and ping results.
8. THE Phase3_Lambda SHALL issue SSM commands with the correct region for each instance.

### Requirement 5: Step Functions State Machine

**User Story:** As a DevOps engineer, I want a Step Functions state machine that orchestrates Phase1 → Phase2 → Phase3 sequentially with error handling and retry logic, so that the entire SD-WAN configuration workflow runs as a single managed execution.

#### Acceptance Criteria

1. THE State_Machine SHALL execute Phase1_Lambda, then Phase2_Lambda, then Phase3_Lambda in strict sequential order.
2. THE State_Machine SHALL include a wait state between Phase1 and Phase2 to allow VyOS containers to fully initialize (configurable wait duration, default 60 seconds).
3. THE State_Machine SHALL include a wait state between Phase2 and Phase3 to allow VPN tunnels and BGP sessions to establish (configurable wait duration, default 90 seconds).
4. THE State_Machine SHALL configure retry logic on each Lambda invocation with exponential backoff (max 2 retries, backoff rate 2.0) for transient errors (Lambda.ServiceException, Lambda.AWSLambdaException, Lambda.SdkClientException).
5. IF a Lambda invocation fails after all retries, THEN THE State_Machine SHALL transition to a failure state that captures the error details and the phase that failed.
6. THE State_Machine SHALL pass the output of each phase as input to the next phase, enabling Phase2 to receive Phase1 results and Phase3 to receive Phase2 results.
7. THE State_Machine SHALL be triggerable manually via the AWS Console, AWS CLI (aws stepfunctions start-execution), or programmatically.

### Requirement 6: IAM Roles and Permissions

**User Story:** As a DevOps engineer, I want properly scoped IAM roles for the Lambda functions and Step Functions state machine, so that each component has the minimum permissions required.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create a Lambda_Execution_Role with permissions for ssm:SendCommand, ssm:GetCommandInvocation, ssm:DescribeInstanceInformation, and ssm:GetParameter.
2. THE Lambda_Execution_Role SHALL include permissions for logs:CreateLogGroup, logs:CreateLogStream, and logs:PutLogEvents for CloudWatch logging.
3. THE Lambda_Execution_Role SHALL scope ssm:SendCommand to the AWS-RunShellScript document and to the specific EC2 instance ARNs.
4. THE Lambda_Execution_Role SHALL scope ssm:GetParameter to the /sdwan/* parameter path.
5. THE Terraform_Configuration SHALL create a Step Functions execution role with permissions to invoke the 3 Lambda functions.
6. THE Step_Functions_Role SHALL include permissions for logs:* scoped to the state machine's log group for execution logging.

### Requirement 7: Terraform Deployment of Lambda and Step Functions

**User Story:** As a DevOps engineer, I want Terraform to deploy the Lambda functions, Step Functions state machine, and all supporting resources, so that the entire orchestration infrastructure is managed as code.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create aws_lambda_function resources for Phase1_Lambda, Phase2_Lambda, and Phase3_Lambda with Python 3.12 runtime.
2. THE Terraform_Configuration SHALL package the Lambda function code from a local source directory (e.g., lambda/) using a data "archive_file" resource.
3. THE Terraform_Configuration SHALL create an aws_sfn_state_machine resource with the state machine definition in Amazon States Language (ASL).
4. THE Terraform_Configuration SHALL set Lambda timeout to 900 seconds (15 minutes) for Phase1_Lambda and 600 seconds (10 minutes) for Phase2_Lambda and Phase3_Lambda.
5. THE Terraform_Configuration SHALL set Lambda memory to 256 MB for all 3 functions.
6. THE Terraform_Configuration SHALL configure environment variables on each Lambda for the SSM parameter path prefix (e.g., /sdwan/).
7. THE Terraform_Configuration SHALL organize Lambda-related resources in a dedicated Terraform file (e.g., lambda.tf) and Step Functions resources in another file (e.g., stepfunctions.tf).

### Requirement 8: Lambda Shared Utilities

**User Story:** As a developer, I want shared utility functions for SSM command execution and parameter retrieval, so that common logic is not duplicated across the 3 Lambda functions.

#### Acceptance Criteria

1. THE Lambda code SHALL include a shared utility module (e.g., ssm_utils.py) containing functions for sending SSM commands and polling for completion.
2. THE ssm_utils module SHALL provide a function that sends an SSM command to a specific instance in a specific region and polls GetCommandInvocation until the command completes or times out.
3. THE ssm_utils module SHALL provide a function that reads SSM parameters by path prefix and returns a dictionary of instance configurations (instance IDs, EIPs, private IPs).
4. THE ssm_utils module SHALL handle SSM command failures by returning structured error information including the command ID, instance ID, status, and error output.
5. THE ssm_utils module SHALL use configurable timeouts for SSM command polling (default 600 seconds for Phase1, 300 seconds for Phase2/Phase3).


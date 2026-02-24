# Implementation Plan: Lambda + Step Functions Orchestration

## Overview

Replace local bash scripts with AWS Lambda functions orchestrated by Step Functions, deployed via Terraform. Implementation follows a bottom-up approach: shared utilities first, then each Lambda phase, then Terraform infrastructure, then wiring everything together.

## Tasks

- [x] 1. Create shared SSM utility module
  - [x] 1.1 Create `lambda/ssm_utils.py` with `get_instance_configs()` and `send_and_wait()` functions
    - `get_instance_configs(param_prefix, regions)`: creates regional boto3 SSM clients, calls GetParametersByPath, returns dict keyed by instance name with instance_id, outside_eip, outside_private_ip, region
    - `send_and_wait(instance_id, region, commands, timeout)`: sends SSM RunShellScript command, polls GetCommandInvocation every 15s, returns structured result dict with status, command_id, instance_id, stdout, stderr
    - Include helper `get_ssm_parameter_path(instance_name, param_type)` returning `/sdwan/{instance-name}/{param-type}`
    - Include helper `get_region_for_instance(instance_name)` returning correct region
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [x] 1.2 Write property tests for ssm_utils
    - **Property 1: SSM parameter path generation**
    - **Property 4: Instance-to-region mapping consistency**
    - **Property 10: send_and_wait returns structured results**
    - **Property 11: SSM parameter parsing produces complete instance configs**
    - **Validates: Requirements 1.4, 2.9, 3.9, 4.8, 8.2, 8.3, 8.4**

- [x] 2. Create Phase 1 Lambda function
  - [x] 2.1 Create `lambda/phase1_handler.py` with handler function
    - Implement `build_phase1_commands()` that generates the shell script payload matching existing phase1-base-setup.sh logic
    - Handler calls `get_instance_configs()`, then `send_and_wait()` for each instance with the Phase1 payload
    - Command payload: apt packages, snap wait + install lxd/aws-cli, ubuntu password, LXD preseed, VyOS S3 download, container creation (eth0→ens6, eth1→ens7), base config.boot, Phase1 VyOS script (eth0 DHCP distance 10, eth1 no-default-route)
    - Idempotency: stop/delete existing router container before recreating
    - Returns structured result with per-instance status
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11_

  - [x] 2.2 Write property tests for Phase1 command builder
    - **Property 2: Phase1 command payload contains all required packages**
    - **Property 3: Snap ordering in Phase1 payload**
    - **Validates: Requirements 2.3, 2.4**

- [x] 3. Create Phase 2 Lambda function
  - [x] 3.1 Create `lambda/phase2_handler.py` with handler function
    - Define TUNNELS and ROUTER_CONFIG data structures matching the design
    - Implement `build_vpn_bgp_script(router_name, instance_configs)` that generates per-router vbash script
    - IPsec: local-address = own private IP, peer = peer EIP, remote-id = peer private IP, encryption aes256, hash sha256, ikev2, dh-group 14
    - BGP: ASN 65001 (sdwan) / 65002 (branch), ebgp-multihop 2, loopback as router-id
    - VTI: nv-sdwan↔nv-branch1 (169.254.100.1/30, 169.254.100.2/30), fra-sdwan↔fra-branch1 (169.254.100.13/30, 169.254.100.14/30)
    - Wrap vbash in SSM command: write to file, lxc file push, lxc exec
    - Handler iterates over routers, calls send_and_wait for each
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11_

  - [x] 3.2 Write property tests for Phase2 VPN/BGP script builder
    - **Property 5: IPsec address field correctness**
    - **Property 6: IPsec encryption algorithm**
    - **Property 7: Tunnel topology validity**
    - **Property 8: Per-router configuration consistency**
    - **Validates: Requirements 3.3, 3.4, 3.5, 3.6, 3.7, 3.11**

- [x] 4. Create Phase 3 Lambda function
  - [x] 4.1 Create `lambda/phase3_handler.py` with handler function
    - Define PING_TARGETS mapping per router
    - Implement verification: run show vpn ipsec sa, show ip bgp summary, show interfaces via lxc exec through SSM
    - Run ping tests to VTI peer addresses per router
    - Return structured JSON with per-instance verification results
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8_

  - [x] 4.2 Write property test for Phase3 ping targets
    - **Property 9: Verification ping targets match VTI peers**
    - **Validates: Requirements 4.6**

- [x] 5. Checkpoint - Ensure all Lambda code and tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Create Terraform SSM parameters
  - [x] 6.1 Create `ssm-parameters.tf` with SSM Parameter Store resources
    - Create 12 SSM parameters (3 per instance × 4 instances) using correct provider per region
    - Parameter paths: `/sdwan/{instance-name}/instance-id`, `/sdwan/{instance-name}/outside-eip`, `/sdwan/{instance-name}/outside-private-ip`
    - Reference existing Terraform resource attributes from instances-virginia.tf and instances-frankfurt.tf
    - us-east-1 params use aws.virginia provider, eu-central-1 params use aws.frankfurt provider
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 7. Create Terraform Lambda and IAM resources
  - [x] 7.1 Create `lambda.tf` with Lambda functions and IAM role
    - Create archive_file data source to package lambda/ directory
    - Create Lambda execution IAM role with trust policy for lambda.amazonaws.com
    - Attach inline policy: ssm:SendCommand (scoped to AWS-RunShellScript + EC2 instances), ssm:GetCommandInvocation, ssm:DescribeInstanceInformation, ssm:GetParameter (/sdwan/*), ssm:GetParametersByPath, CloudWatch logs
    - Create 3 aws_lambda_function resources: sdwan-phase1 (timeout 900s), sdwan-phase2 (timeout 600s), sdwan-phase3 (timeout 600s)
    - All functions: Python 3.12 runtime, 256 MB memory, environment variable SSM_PARAM_PREFIX=/sdwan/
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 7.1, 7.2, 7.4, 7.5, 7.6_

- [x] 8. Create Terraform Step Functions resources
  - [x] 8.1 Create `stepfunctions.tf` with state machine and IAM role
    - Create Step Functions execution IAM role with trust policy for states.amazonaws.com
    - Attach inline policy: lambda:InvokeFunction for the 3 Lambda ARNs, CloudWatch logs permissions
    - Create aws_sfn_state_machine with ASL definition: Phase1 → Wait(60s) → Phase2 → Wait(90s) → Phase3
    - Each Task state: retry on Lambda.ServiceException/AWSLambdaException/SdkClientException (max 2, backoff 2.0), catch all errors → FailureState
    - ResultPath accumulates phase results ($.phase1_result, $.phase2_result, $.phase3_result)
    - Use variables for wait durations (var.phase1_wait_seconds, var.phase2_wait_seconds)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 6.5, 6.6_

- [x] 9. Add Terraform variables and organize files
  - [x] 9.1 Add new variables to `variables.tf`
    - Add lambda_source_dir (default "lambda"), phase1_wait_seconds (default 60), phase2_wait_seconds (default 90)
    - _Requirements: 7.7_

- [x] 10. Final checkpoint - Validate Terraform and all tests
  - Run `terraform validate` to verify HCL syntax
  - Ensure all Lambda property tests and unit tests pass
  - Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Lambda functions are deployed to us-east-1 but create regional boto3 clients for cross-region SSM calls
- The state machine is triggered manually via AWS Console or CLI after terraform apply
- Property tests validate universal correctness properties of configuration generation

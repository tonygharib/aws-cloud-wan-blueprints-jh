# Requirements Document

## Introduction

This feature deploys Ubuntu 22.04 LTS EC2 instances into each of the 5 existing VPCs across the Frankfurt and Virginia regions. Each instance acts as an SD-WAN appliance host, running an LXD container with a VyOS router inside. The instances require 3 ENIs (2 public, 1 private), security groups for VPN and management access, an IAM instance profile for S3 and SSM access, and cloud-init user data that bootstraps LXD and deploys the VyOS container.

## Glossary

- **Ubuntu_Instance**: An EC2 instance running Ubuntu 22.04 LTS (c5.large) deployed in a VPC to host the VyOS SD-WAN router container.
- **ENI**: Elastic Network Interface — a virtual network card attached to an EC2 instance. Each Ubuntu_Instance requires 3 ENIs.
- **EIP**: Elastic IP — a static public IPv4 address associated with a public ENI.
- **SDWAN_Mgmt_ENI**: The first public ENI (device index 0, primary interface) placed in the first public subnet with an associated Elastic IP. Used for management access to the Ubuntu host.
- **SDWAN_Outside_ENI**: The second public ENI (device index 1) placed in the Second_Public_Subnet with an associated Elastic IP. Passed through to the VyOS container as eth0 (OUTSIDE interface).
- **SDWAN_Internal_ENI**: The private ENI (device index 2) placed in the private subnet with no public IP. Passed through to the VyOS container as eth1 (INSIDE interface).
- **Public_Security_Group**: A security group applied to SDWAN_Mgmt_ENI and SDWAN_Outside_ENI allowing VPN traffic between SD-WAN appliances and AWS management services (SSM).
- **Private_Security_Group**: A security group applied to SDWAN_Internal_ENI allowing all local VPC traffic and EC2 Instance Connect endpoint connectivity.
- **User_Data_Script**: A cloud-init bash script that bootstraps the Ubuntu_Instance with LXD, downloads the VyOS image from S3, and deploys the VyOS router container.
- **VyOS_Container**: An LXC container running VyOS router software inside the Ubuntu_Instance, with the two Public_ENIs passed through as physical NICs.
- **IAM_Instance_Profile**: An IAM instance profile granting the Ubuntu_Instance permissions for S3 read access (VyOS image download) and SSM managed instance capabilities.
- **Second_Public_Subnet**: An additional public subnet added to each VPC to host the second Public_ENI, ensuring network isolation between the two public interfaces.
- **VyOS_S3_Bucket**: The S3 bucket storing the VyOS LXD image, parameterized per deployment to allow different bucket names per region or environment.

## Requirements

### Requirement 1: Second Public Subnet

**User Story:** As a network engineer, I want a second public subnet in each VPC, so that each Ubuntu_Instance can have two Public_ENIs on separate subnets for proper SD-WAN dual-WAN connectivity.

#### Acceptance Criteria

1. WHEN Terraform applies the VPC configuration, THE VPC_Module SHALL create a second public subnet in each of the 5 VPCs alongside the existing public and private subnets.
2. THE Second_Public_Subnet SHALL reside in the same availability zone as the existing public subnet within each VPC.
3. THE Second_Public_Subnet SHALL have a unique CIDR block that does not overlap with existing subnets in the VPC.
4. THE Second_Public_Subnet SHALL be associated with a route table that has a default route to the VPC internet gateway.
5. WHEN the Second_Public_Subnet is created, THE VPC_Module SHALL tag the subnet with a "Type" tag set to "public".

### Requirement 2: Ubuntu Instance Deployment

**User Story:** As a network engineer, I want an Ubuntu 22.04 LTS EC2 instance deployed in each of the 5 VPCs, so that each VPC has an SD-WAN appliance host.

#### Acceptance Criteria

1. WHEN Terraform applies the instance configuration, THE Terraform_Configuration SHALL deploy exactly one Ubuntu_Instance in each of the 5 VPCs (fra-branch1-vpc, fra-sdwan-vpc, nv-branch1-vpc, nv-branch2-vpc, nv-sdwan-vpc).
2. THE Ubuntu_Instance SHALL use the c5.large instance type.
3. THE Ubuntu_Instance SHALL use the latest Ubuntu 22.04 LTS AMI available in the respective region.
4. THE Ubuntu_Instance SHALL be launched in the same availability zone as the VPC subnets.
5. THE Ubuntu_Instance SHALL have source/destination checking disabled on all attached ENIs to allow routing of traffic through the VyOS container.

### Requirement 3: ENI Configuration

**User Story:** As a network engineer, I want each Ubuntu_Instance to have 3 ENIs (SDWAN_Mgmt_ENI, SDWAN_Outside_ENI, SDWAN_Internal_ENI), so that the VyOS container can operate with dual WAN interfaces and a LAN interface while the host retains a management interface.

#### Acceptance Criteria

1. THE Ubuntu_Instance SHALL have exactly 3 ENIs attached: SDWAN_Mgmt_ENI, SDWAN_Outside_ENI, and SDWAN_Internal_ENI.
2. THE SDWAN_Mgmt_ENI SHALL be the primary network interface (device index 0) placed in the first public subnet.
3. THE SDWAN_Outside_ENI SHALL be an additional network interface (device index 1) placed in the Second_Public_Subnet.
4. THE SDWAN_Internal_ENI SHALL be an additional network interface (device index 2) placed in the private subnet.
5. WHEN the SDWAN_Mgmt_ENI or SDWAN_Outside_ENI is created, THE Terraform_Configuration SHALL allocate and associate an Elastic IP with that ENI.
6. THE SDWAN_Internal_ENI SHALL have no Elastic IP or public IP address associated with the SDWAN_Internal_ENI.
7. THE Ubuntu_Instance SHALL have source/destination checking disabled on all 3 ENIs.

### Requirement 4: Security Groups

**User Story:** As a network engineer, I want separate security groups for public and private interfaces, so that VPN traffic and management access are properly controlled.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create one Public_Security_Group per VPC applied to both SDWAN_Mgmt_ENI and SDWAN_Outside_ENI.
2. THE Public_Security_Group SHALL allow inbound UDP port 500 (IKE) and UDP port 4500 (NAT-T) from 0.0.0.0/0 for VPN connectivity.
3. THE Public_Security_Group SHALL allow inbound HTTPS (TCP 443) from the VPC CIDR for SSM agent connectivity.
4. THE Public_Security_Group SHALL allow all outbound traffic.
5. THE Terraform_Configuration SHALL create one Private_Security_Group per VPC applied to the SDWAN_Internal_ENI.
6. THE Private_Security_Group SHALL allow all inbound traffic from the VPC CIDR block.
7. THE Private_Security_Group SHALL allow all inbound traffic from the RFC1918 range 10.0.0.0/8 for cross-VPC connectivity.
8. THE Private_Security_Group SHALL allow all outbound traffic.

### Requirement 5: IAM Instance Profile

**User Story:** As a network engineer, I want an IAM instance profile attached to each Ubuntu_Instance, so that the instance can download the VyOS image from S3 and be managed via SSM.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create an IAM role with an EC2 trust policy allowing EC2 instances to assume the role.
2. THE IAM_Instance_Profile SHALL include the AmazonSSMManagedInstanceCore managed policy for SSM access.
3. THE IAM_Instance_Profile SHALL include a policy granting s3:GetObject permission on the VyOS_S3_Bucket.
4. THE Ubuntu_Instance SHALL have the IAM_Instance_Profile attached at launch.
5. THE IAM_Instance_Profile SHALL be reusable across all 5 Ubuntu_Instances.

### Requirement 6: VyOS S3 Bucket Parameterization

**User Story:** As a network engineer, I want the VyOS S3 bucket name to be configurable via a Terraform variable, so that different environments or regions can use different buckets.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL define a variable for the VyOS_S3_Bucket name with a default value of "fra-vyos-bucket".
2. THE User_Data_Script SHALL reference the VyOS_S3_Bucket variable when constructing the S3 download command.
3. THE Terraform_Configuration SHALL define a variable for the S3 region used in the aws s3 cp command with a default value of "us-east-1".

### Requirement 7: User Data Bootstrap

**User Story:** As a network engineer, I want each Ubuntu_Instance to be automatically bootstrapped with LXD and a VyOS router container, so that the SD-WAN appliance is operational after instance launch without manual intervention.

#### Acceptance Criteria

1. WHEN the Ubuntu_Instance launches, THE User_Data_Script SHALL execute as a bash cloud-init script with root privileges.
2. THE User_Data_Script SHALL install the following packages in order: python3-pip, net-tools, tmux, and aws-cli (via snap).
3. THE User_Data_Script SHALL install LXD via snap and hold snap auto-refresh permanently.
4. THE User_Data_Script SHALL create an LXD preseed configuration file at /tmp/lxd.yaml with a directory-backed storage pool named "default".
5. THE User_Data_Script SHALL initialize LXD using the preseed configuration file.
6. THE User_Data_Script SHALL download the VyOS LXD image from the VyOS_S3_Bucket to /tmp/vyos.tar.gz and import the VyOS LXD image with the alias "vyos".
7. THE User_Data_Script SHALL create a router profile at /tmp/router.yaml that maps eth0 to ens6 (SDWAN_Outside_ENI) and eth1 to ens7 (SDWAN_Internal_ENI) as physical NIC passthrough devices, with 1 CPU and 2048MiB memory limits.
8. THE User_Data_Script SHALL initialize an LXC container named "router" from the "vyos" image using the router profile.
9. THE User_Data_Script SHALL create a VyOS config.boot.default file with eth0 (OUTSIDE, DHCP) and eth1 (INSIDE, DHCP) interfaces, hostname "vyos", and a "vyos" user with no password authentication.
10. THE User_Data_Script SHALL push the config.boot.default file to the router container at /opt/vyatta/etc/config/config.boot and start the router container.

### Requirement 8: Instance Tagging and Naming

**User Story:** As a network engineer, I want each Ubuntu_Instance and its associated resources to be clearly named and tagged, so that resources are identifiable in the AWS console.

#### Acceptance Criteria

1. THE Ubuntu_Instance SHALL be tagged with a Name tag following the pattern "{vpc-name}-sdwan-instance" (e.g., "fra-branch1-vpc-sdwan-instance").
2. THE ENIs SHALL be tagged with Name tags indicating their function (e.g., "{vpc-name}-sdwan-mgmt", "{vpc-name}-sdwan-outside", "{vpc-name}-sdwan-internal").
3. THE Elastic_IPs SHALL be tagged with Name tags following the pattern "{vpc-name}-eip-{index}".
4. THE Security_Groups SHALL be tagged with Name tags following the pattern "{vpc-name}-public-sg" and "{vpc-name}-private-sg".

### Requirement 9: Terraform Code Organization

**User Story:** As a DevOps engineer, I want the Ubuntu instance Terraform code to be organized in dedicated files, so that the codebase remains maintainable and follows the existing project structure.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL define instance-related resources in region-specific files following the existing naming convention (e.g., instances-frankfurt.tf, instances-virginia.tf).
2. THE Terraform_Configuration SHALL define shared resources (IAM role, security group rules) in a dedicated file (e.g., instances-common.tf).
3. THE Terraform_Configuration SHALL add new variables to the existing variables.tf file.
4. THE Terraform_Configuration SHALL add new local values to the existing locals.tf file.

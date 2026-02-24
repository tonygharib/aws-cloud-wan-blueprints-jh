# Requirements Document

## Introduction

This feature extends the existing multi-region SD-WAN workshop by integrating AWS Cloud WAN with BGP peering to the SDWAN VyOS routers. Cloud WAN provides a global backbone connecting the two SDWAN VPCs (nv-sdwan-vpc in us-east-1 and fra-sdwan-vpc in eu-central-1) via a managed core network. Tunnel-less Connect attachments enable direct BGP sessions between the VyOS SDWAN routers and Cloud WAN over the VPC fabric without GRE encapsulation, allowing branch loopback routes learned via the existing intra-region VPN/BGP sessions to propagate across regions through the Cloud WAN backbone. The existing VPN tunnels and BGP sessions between SDWAN and branch routers remain intact.

## Glossary

- **Cloud_WAN_Global_Network**: An AWS Network Manager global network resource that serves as the top-level container for the Cloud WAN core network.
- **Core_Network**: The AWS Cloud WAN core network resource that defines the multi-region backbone topology, segments, and attachment policies.
- **Core_Network_Policy**: A JSON policy document attached to the Core_Network that defines edge locations, segments, segment actions, and attachment policies governing how VPCs and connect attachments are associated.
- **Segment**: A logical isolation domain within the Core_Network (e.g., "sdwan") that groups attachments and controls route propagation between them.
- **VPC_Attachment**: A Cloud WAN attachment that connects a VPC's private subnet to the Core_Network, enabling traffic flow between the VPC and the Cloud WAN backbone.
- **Connect_Attachment**: A Cloud WAN attachment layered on top of a VPC_Attachment that enables BGP peering with network appliances inside the VPC. Uses tunnel-less (no GRE) protocol so BGP runs directly over the VPC fabric.
- **Connect_Peer**: A peer configuration within a Connect_Attachment that defines the BGP session parameters (inside CIDR, peer ASN, peer IP) for a specific appliance. In tunnel-less mode, no GRE tunnel is created.
- **Inside_CIDR**: A /29 CIDR block assigned to a Connect_Peer that provides the IP addresses used for BGP peering between Cloud WAN and the VyOS router. Cloud WAN assigns addresses from this block to both the core network side and the appliance side.
- **Core_Network_ASN**: The BGP ASN assigned to the Cloud WAN Core_Network (default 64512), used as the remote-as when configuring BGP on the VyOS routers.
- **SDWAN_Router**: A VyOS router running inside an LXC container on the SDWAN Ubuntu instance (nv-sdwan or fra-sdwan), with ASN 65001.
- **Branch_Router**: A VyOS router running inside an LXC container on a branch Ubuntu instance (nv-branch1, nv-branch2, fra-branch1), with ASN 65002.
- **Private_ENI_IP**: The private IP address of the SDWAN instance's internal ENI (eth2 on the host, eth1 inside VyOS), located in the SDWAN VPC private subnet.
- **SSM_Run_Command**: AWS Systems Manager Run Command used to push VyOS configuration scripts to the LXC containers on the SDWAN instances.

## Requirements

### Requirement 1: Cloud WAN Global Network and Core Network

**User Story:** As a network architect, I want an AWS Cloud WAN global network and core network spanning us-east-1 and eu-central-1, so that I have a managed backbone for inter-region connectivity between SDWAN sites.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create an aws_networkmanager_global_network resource with a descriptive name tag.
2. THE Terraform_Configuration SHALL create an aws_networkmanager_core_network resource associated with the Global_Network.
3. THE Core_Network_Policy SHALL define two edge locations: us-east-1 and eu-central-1.
4. THE Core_Network_Policy SHALL define a segment named "sdwan" that is associated with both edge locations.
5. THE Core_Network_Policy SHALL set the Core_Network_ASN to 64512.
6. THE Core_Network_Policy SHALL include an attachment policy that associates VPC and Connect attachments tagged with segment "sdwan" to the sdwan segment.
7. WHEN Terraform applies the configuration, THE Core_Network SHALL reach an AVAILABLE state in both regions before VPC attachments are created.

### Requirement 2: SDWAN VPC Attachments to Cloud WAN

**User Story:** As a network architect, I want the SDWAN VPCs attached to Cloud WAN via their private subnets, so that Cloud WAN can route traffic to and from the SDWAN appliances.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create a VPC_Attachment for nv-sdwan-vpc in us-east-1, attaching the private subnet (10.201.1.0/24) to the Core_Network.
2. THE Terraform_Configuration SHALL create a VPC_Attachment for fra-sdwan-vpc in eu-central-1, attaching the private subnet (10.200.1.0/24) to the Core_Network.
3. THE VPC_Attachment resources SHALL include a tag with key "segment" and value "sdwan" to match the Core_Network_Policy attachment rules.
4. THE Terraform_Configuration SHALL add appropriate dependencies to ensure the Core_Network_Policy is applied before VPC_Attachments are created.
5. WHEN VPC_Attachments are created, THE SDWAN_VPC route tables for the private subnets SHALL be updated to route Cloud WAN destination CIDRs via the attachment.

### Requirement 3: Connect Attachments and Connect Peers (Tunnel-less)

**User Story:** As a network architect, I want Cloud WAN Connect attachments using tunnel-less protocol with Connect peers configured for each SDWAN VPC, so that BGP sessions can be established directly between Cloud WAN and the VyOS SDWAN routers without GRE tunnels.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create a Connect_Attachment for nv-sdwan-vpc, referencing the nv-sdwan VPC_Attachment as the transport attachment, with protocol set to "NO_ENCAP" (tunnel-less).
2. THE Terraform_Configuration SHALL create a Connect_Attachment for fra-sdwan-vpc, referencing the fra-sdwan VPC_Attachment as the transport attachment, with protocol set to "NO_ENCAP" (tunnel-less).
3. THE Connect_Attachment resources SHALL include a tag with key "segment" and value "sdwan" to match the Core_Network_Policy.
4. THE Terraform_Configuration SHALL create a Connect_Peer for the nv-sdwan Connect_Attachment with the nv-sdwan Private_ENI_IP as the peer address and a unique Inside_CIDR block (e.g., 169.254.200.0/29).
5. THE Terraform_Configuration SHALL create a Connect_Peer for the fra-sdwan Connect_Attachment with the fra-sdwan Private_ENI_IP as the peer address and a unique Inside_CIDR block (e.g., 169.254.201.0/29).
6. THE Connect_Peer resources SHALL specify the SDWAN_Router BGP ASN (65001) as the peer ASN.
7. THE Connect_Peer resources SHALL NOT configure a GRE tunnel or any encapsulation parameters, relying on direct VPC fabric connectivity.
8. THE Terraform_Configuration SHALL output the Connect_Peer inside addresses and the Core_Network BGP peer addresses for use in VyOS configuration.

### Requirement 4: SDWAN VPC Security Group Updates for BGP

**User Story:** As a network engineer, I want the SDWAN VPC private security groups updated to allow BGP traffic from Cloud WAN, so that the Connect peer BGP sessions can establish over the VPC fabric.

#### Acceptance Criteria

1. THE Private_Security_Group for nv-sdwan-vpc SHALL allow inbound TCP port 179 (BGP) from the Inside_CIDR ranges.
2. THE Private_Security_Group for fra-sdwan-vpc SHALL allow inbound TCP port 179 (BGP) from the Inside_CIDR ranges.
3. THE existing security group rules for VPC-internal and RFC1918 traffic SHALL remain unchanged.

### Requirement 5: VyOS SDWAN Router BGP Configuration for Cloud WAN Peering (Tunnel-less)

**User Story:** As a network engineer, I want the SDWAN VyOS routers configured with BGP sessions toward Cloud WAN Connect peers using tunnel-less connectivity, so that routes learned from branch routers propagate into Cloud WAN and across regions without GRE overhead.

#### Acceptance Criteria

1. THE VyOS_Configuration_Script SHALL assign the Connect_Peer inside address to a loopback or dummy interface on each SDWAN_Router for use as the BGP source address toward Cloud WAN.
2. THE VyOS_Configuration_Script SHALL add a static route on each SDWAN_Router for the Cloud WAN peer IP address pointing to the private subnet gateway, ensuring reachability over the VPC fabric.
3. THE VyOS_Configuration_Script SHALL add a BGP neighbor for the Cloud WAN Connect_Peer using the Core_Network_ASN (64512) as the remote-as.
4. THE VyOS_Configuration_Script SHALL configure the BGP neighbor with the Cloud WAN peer IP address derived from the Connect_Peer inside CIDR.
5. THE VyOS_Configuration_Script SHALL configure the BGP session to use the Connect_Peer inside address as the update-source.
6. THE VyOS_Configuration_Script SHALL configure the BGP session to advertise the SDWAN_Router loopback network and any routes learned from branch routers.
7. THE existing VPN tunnel BGP sessions between SDWAN and branch routers SHALL remain intact and operational after the Cloud WAN BGP configuration is applied.
8. WHEN the BGP session is established, THE SDWAN_Router SHALL exchange routes with Cloud WAN without disrupting existing VPN BGP peering.

### Requirement 6: VyOS Configuration Delivery via SSM

**User Story:** As a DevOps engineer, I want the Cloud WAN BGP configuration pushed to the SDWAN VyOS routers via SSM Run Command, so that the configuration is applied consistently using the existing automation pattern.

#### Acceptance Criteria

1. THE Configuration_Script SHALL be a bash script that uses SSM Run Command to push vbash configuration scripts to the nv-sdwan and fra-sdwan instances.
2. THE Configuration_Script SHALL read Connect_Peer IP addresses and inside CIDR information from Terraform outputs.
3. THE Configuration_Script SHALL generate a vbash script for each SDWAN_Router that configures the dummy interface, static route, and BGP neighbor for Cloud WAN.
4. THE Configuration_Script SHALL push the vbash script to the VyOS LXC container via "lxc file push" and execute it via "lxc exec router".
5. THE Configuration_Script SHALL handle instances in both us-east-1 (nv-sdwan) and eu-central-1 (fra-sdwan) regions.
6. THE Configuration_Script SHALL be independently rerunnable without causing errors on already-configured routers.
7. IF an SSM command fails on an instance, THEN THE Configuration_Script SHALL report the failure and continue processing the remaining instance.

### Requirement 7: Route Propagation and Cross-Region Connectivity

**User Story:** As a network engineer, I want branch router loopback routes to propagate through the SDWAN routers into Cloud WAN and across regions, so that I can verify end-to-end cross-region routing through the SD-WAN and Cloud WAN backbone.

#### Acceptance Criteria

1. WHEN the nv-branch1 Branch_Router advertises its loopback (10.255.1.1/32) via eBGP, THE nv-sdwan SDWAN_Router SHALL receive the route and re-advertise it to Cloud WAN via the Connect_Peer BGP session.
2. WHEN the fra-branch1 Branch_Router advertises its loopback (10.255.11.1/32) via eBGP, THE fra-sdwan SDWAN_Router SHALL receive the route and re-advertise it to Cloud WAN via the Connect_Peer BGP session.
3. WHEN routes are advertised to Cloud WAN from one region, THE Core_Network SHALL propagate the routes to the other region's SDWAN_Router via the sdwan segment.
4. THE nv-sdwan SDWAN_Router SHALL have a route to 10.255.11.1/32 (fra-branch1 loopback) learned via Cloud WAN.
5. THE fra-sdwan SDWAN_Router SHALL have a route to 10.255.1.1/32 (nv-branch1 loopback) learned via Cloud WAN.
6. THE nv-sdwan SDWAN_Router SHALL have a route to 10.255.2.1/32 (nv-branch2 loopback) learned via the existing intra-region VPN BGP session.

### Requirement 8: Terraform Outputs for Cloud WAN Resources

**User Story:** As a DevOps engineer, I want Terraform outputs for all Cloud WAN resource identifiers and Connect peer addresses, so that configuration scripts and verification tools can reference them.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL output the Core_Network ID and ARN.
2. THE Terraform_Configuration SHALL output the VPC_Attachment IDs for both nv-sdwan and fra-sdwan.
3. THE Terraform_Configuration SHALL output the Connect_Attachment IDs for both nv-sdwan and fra-sdwan.
4. THE Terraform_Configuration SHALL output the Connect_Peer inside IP addresses and Cloud WAN core network peer IP addresses for both regions.
5. THE Terraform_Configuration SHALL output the Core_Network_ASN value.

### Requirement 9: Verification of Cloud WAN BGP Integration

**User Story:** As a network engineer, I want a verification script that checks Cloud WAN BGP session status and cross-region route propagation, so that I can confirm the integration is working correctly.

#### Acceptance Criteria

1. THE Verification_Script SHALL check the BGP session status between each SDWAN_Router and its Cloud WAN Connect_Peer by running "show ip bgp summary" via SSM.
2. THE Verification_Script SHALL check the routing table on each SDWAN_Router for cross-region loopback routes learned via Cloud WAN.
3. THE Verification_Script SHALL verify that the existing intra-region VPN BGP sessions remain established after Cloud WAN integration.
4. THE Verification_Script SHALL verify that the Connect_Peer inside address is reachable from each SDWAN_Router.
5. THE Verification_Script SHALL format output in a readable per-instance summary.
6. THE Verification_Script SHALL handle instances in both us-east-1 and eu-central-1 regions.

### Requirement 10: Terraform Variable Definitions for Cloud WAN

**User Story:** As a DevOps engineer, I want Cloud WAN-related configuration values defined as Terraform variables, so that the deployment can be customized without modifying resource definitions.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL define a variable for the Core_Network_ASN with a default value of 64512.
2. THE Terraform_Configuration SHALL define a variable for the Connect_Peer inside CIDR for nv-sdwan with a default value of "169.254.200.0/29".
3. THE Terraform_Configuration SHALL define a variable for the Connect_Peer inside CIDR for fra-sdwan with a default value of "169.254.201.0/29".
4. THE Terraform_Configuration SHALL define a variable for the sdwan segment name with a default value of "sdwan".

# Requirements Document

## Introduction

This feature extends the existing VyOS router configurations to establish IPsec VPN and BGP connectivity between the nv_branch1 and nv_sdwan appliances in the us-east-1 (Virginia) region. The implementation adds VyOS configuration templates that are injected via Terraform's templatefile() function into the user_data.sh script, enabling automatic VPN tunnel establishment and BGP peering on instance boot. The VPN uses IKEv2 with PSK authentication, and BGP uses private ASNs for route exchange over the encrypted tunnel.

## Glossary

- **VyOS_Config_Template**: A Terraform template file containing VyOS configuration syntax that is rendered with Elastic IP addresses and other variables at plan time.
- **IPsec_VPN**: An encrypted site-to-site tunnel using IKEv2 protocol with pre-shared key authentication between two VyOS routers.
- **VTI**: Virtual Tunnel Interface — a routable interface in VyOS that terminates an IPsec tunnel, enabling dynamic routing protocols like BGP to run over the encrypted path.
- **BGP_Session**: A Border Gateway Protocol peering session between two routers that exchanges routing information over the VPN tunnel.
- **ASN**: Autonomous System Number — a unique identifier for a BGP-speaking network. Private ASNs (64512-65534) are used for internal routing.
- **Loopback_Interface**: A virtual interface on a router with a stable IP address used for BGP router-id and route advertisement testing.
- **PSK**: Pre-Shared Key — a secret string used for IKEv2 authentication between VPN peers.
- **Tunnel_Subnet**: A /30 point-to-point subnet used for addressing the VTI interfaces on each end of the VPN tunnel.
- **SDWAN_Router**: The VyOS router running in the nv_sdwan VPC, acting as the hub for VPN connections (ASN 65001).
- **Branch1_Router**: The VyOS router running in the nv_branch1 VPC, acting as a spoke connecting to the SDWAN hub (ASN 65002).
- **Outside_EIP**: The Elastic IP address associated with the SDWAN_Outside_ENI, used as the VPN endpoint address.

## Requirements

### Requirement 1: VyOS Configuration Templates

**User Story:** As a network engineer, I want VyOS configuration templates that are rendered with Terraform variables, so that VPN and BGP settings are automatically configured with the correct IP addresses at deployment time.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create separate VyOS configuration template files for nv_sdwan and nv_branch1 routers.
2. WHEN Terraform renders the templates, THE Template_Engine SHALL inject the Outside_EIP addresses for both local and remote VPN endpoints.
3. THE VyOS_Config_Template SHALL include all necessary VyOS configuration blocks for interfaces, VPN, and BGP in valid config.boot syntax.
4. THE User_Data_Script SHALL be modified to accept the rendered VyOS configuration and push it to the LXD container at /opt/vyatta/etc/config/config.boot.
5. WHEN the VyOS container starts, THE VyOS_Router SHALL load the complete configuration including VPN and BGP settings without manual intervention.

### Requirement 2: IPsec VPN Configuration

**User Story:** As a network engineer, I want an IPsec site-to-site VPN tunnel between nv_branch1 and nv_sdwan routers, so that traffic between the two sites is encrypted and secure.

#### Acceptance Criteria

1. THE VyOS_Config_Template SHALL configure IKEv2 as the key exchange protocol for the IPsec VPN.
2. THE VyOS_Config_Template SHALL use pre-shared key (PSK) authentication for the IKE phase.
3. THE VyOS_Config_Template SHALL define an IPsec profile with AES-256 encryption and SHA-256 integrity algorithms.
4. THE VyOS_Config_Template SHALL configure a Virtual Tunnel Interface (VTI) on each router for the IPsec tunnel termination.
5. THE VTI interfaces SHALL use a /30 subnet (169.254.100.0/30) with .1 assigned to SDWAN_Router and .2 assigned to Branch1_Router.
6. THE VyOS_Config_Template SHALL configure the local-address as the router's Outside_EIP and the remote-address as the peer's Outside_EIP.
7. WHEN both routers boot with the configuration, THE IPsec_VPN tunnel SHALL establish automatically without manual intervention.
8. THE IPsec_VPN SHALL remain operational across router reboots by persisting the configuration in config.boot.

### Requirement 3: BGP Configuration

**User Story:** As a network engineer, I want BGP sessions running over the VPN tunnel between nv_branch1 and nv_sdwan, so that routes can be dynamically exchanged between sites.

#### Acceptance Criteria

1. THE VyOS_Config_Template SHALL configure BGP with private ASN 65001 on the SDWAN_Router and ASN 65002 on the Branch1_Router.
2. THE BGP_Session SHALL peer using the VTI interface addresses (169.254.100.1 and 169.254.100.2) as neighbor addresses.
3. THE VyOS_Config_Template SHALL configure eBGP multihop with a TTL of 2 to allow BGP packets to traverse the VTI.
4. THE Branch1_Router SHALL advertise its Loopback_Interface network (10.255.1.1/32) to the SDWAN_Router via BGP.
5. THE SDWAN_Router SHALL accept and install routes received from the Branch1_Router into its routing table.
6. WHEN the IPsec_VPN tunnel is established, THE BGP_Session SHALL come up automatically and begin route exchange.
7. THE BGP configuration SHALL use the Loopback_Interface address as the router-id for stable BGP identification.

### Requirement 4: Loopback Interface

**User Story:** As a network engineer, I want a loopback interface on the nv_branch1 router, so that I can test BGP route advertisement and have a stable router identifier.

#### Acceptance Criteria

1. THE VyOS_Config_Template for Branch1_Router SHALL configure a loopback interface named "lo" with IP address 10.255.1.1/32.
2. THE Loopback_Interface address SHALL be used as the BGP router-id for the Branch1_Router.
3. THE Loopback_Interface network SHALL be included in the BGP network statements for advertisement to peers.
4. THE VyOS_Config_Template for SDWAN_Router SHALL configure a loopback interface with IP address 10.255.0.1/32 for router-id purposes.

### Requirement 5: Terraform Variable Management

**User Story:** As a DevOps engineer, I want VPN-related secrets and configuration values managed as Terraform variables, so that sensitive data is not hardcoded and configurations can be customized per environment.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL define a variable for the IPsec pre-shared key with a sensitive flag set to true.
2. THE Terraform_Configuration SHALL define variables for the BGP ASNs with default values of 65001 (sdwan) and 65002 (branch1).
3. THE Terraform_Configuration SHALL define a variable for the VPN tunnel subnet with a default value of "169.254.100.0/30".
4. THE VyOS_Config_Template SHALL reference these variables through the templatefile() function.
5. IF the PSK variable is not provided, THE Terraform_Configuration SHALL generate a random 32-character PSK using the random_password resource.

### Requirement 6: Security Group Updates

**User Story:** As a network engineer, I want the security groups to allow ESP protocol traffic, so that IPsec encrypted packets can traverse between the VPN endpoints.

#### Acceptance Criteria

1. THE Public_Security_Group for nv_branch1 and nv_sdwan VPCs SHALL allow inbound ESP protocol (IP protocol 50) from 0.0.0.0/0.
2. THE existing IKE (UDP 500) and NAT-T (UDP 4500) rules SHALL remain in place for IKE negotiation.
3. THE Public_Security_Group SHALL allow inbound traffic from the peer's Outside_EIP for all protocols to enable tunnel traffic.

### Requirement 7: Interface Configuration Preservation

**User Story:** As a network engineer, I want the existing DHCP interface configuration preserved, so that the VyOS routers maintain connectivity to their respective VPC networks.

#### Acceptance Criteria

1. THE VyOS_Config_Template SHALL retain the eth0 (OUTSIDE) interface configured with DHCP for AWS ENI IP assignment.
2. THE VyOS_Config_Template SHALL retain the eth1 (INSIDE) interface configured with DHCP for AWS ENI IP assignment.
3. THE VyOS_Config_Template SHALL add the VTI and loopback interfaces without modifying the existing ethernet interface configuration.
4. WHEN the VyOS container boots, THE Router SHALL obtain IP addresses on eth0 and eth1 via DHCP before the VPN tunnel attempts to establish.

### Requirement 8: Configuration File Organization

**User Story:** As a DevOps engineer, I want the VyOS configuration templates organized in the templates directory, so that the codebase remains maintainable and follows existing conventions.

#### Acceptance Criteria

1. THE VyOS_Config_Template files SHALL be placed in the templates/ directory alongside the existing user_data.sh template.
2. THE template files SHALL be named following the pattern "vyos_config_{router_name}.tpl" (e.g., vyos_config_nv_sdwan.tpl, vyos_config_nv_branch1.tpl).
3. THE User_Data_Script template SHALL be modified to accept an additional variable containing the rendered VyOS configuration.
4. THE Terraform_Configuration SHALL use nested templatefile() calls or a single templatefile() with the VyOS config as a variable.


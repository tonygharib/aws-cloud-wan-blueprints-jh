# =============================================================================
# Instance ID Outputs (for SSM targeting)
# =============================================================================

output "nv_branch1_instance_id" {
  description = "Virginia Branch1 - EC2 Instance ID"
  value       = aws_instance.nv_branch1_sdwan_instance.id
}

output "nv_branch2_instance_id" {
  description = "Virginia Branch2 - EC2 Instance ID"
  value       = aws_instance.nv_branch2_sdwan_instance.id
}

output "nv_sdwan_instance_id" {
  description = "Virginia SD-WAN - EC2 Instance ID"
  value       = aws_instance.nv_sdwan_sdwan_instance.id
}

output "fra_branch1_instance_id" {
  description = "Frankfurt Branch1 - EC2 Instance ID"
  value       = aws_instance.fra_branch1_sdwan_instance.id
}

output "fra_sdwan_instance_id" {
  description = "Frankfurt SD-WAN - EC2 Instance ID"
  value       = aws_instance.fra_sdwan_sdwan_instance.id
}

# =============================================================================
# Elastic IP Outputs - Outside interfaces (for VPN tunnel endpoints)
# =============================================================================

output "nv_branch1_outside_private_ip" {
  description = "Virginia Branch1 - Outside ENI Private IP"
  value       = aws_network_interface.nv_branch1_sdwan_outside.private_ip
}

output "nv_branch2_outside_private_ip" {
  description = "Virginia Branch2 - Outside ENI Private IP"
  value       = aws_network_interface.nv_branch2_sdwan_outside.private_ip
}

output "nv_sdwan_outside_private_ip" {
  description = "Virginia SD-WAN - Outside ENI Private IP"
  value       = aws_network_interface.nv_sdwan_sdwan_outside.private_ip
}

output "fra_branch1_outside_private_ip" {
  description = "Frankfurt Branch1 - Outside ENI Private IP"
  value       = aws_network_interface.fra_branch1_sdwan_outside.private_ip
}

output "fra_sdwan_outside_private_ip" {
  description = "Frankfurt SD-WAN - Outside ENI Private IP"
  value       = aws_network_interface.fra_sdwan_sdwan_outside.private_ip
}

output "fra_branch1_outside_eip" {
  description = "Frankfurt Branch1 - Outside EIP (VPN endpoint)"
  value       = aws_eip.fra_branch1_sdwan_outside_eip.public_ip
}

output "fra_sdwan_outside_eip" {
  description = "Frankfurt SD-WAN - Outside EIP (VPN endpoint)"
  value       = aws_eip.fra_sdwan_sdwan_outside_eip.public_ip
}

output "nv_branch1_outside_eip" {
  description = "Virginia Branch1 - Outside EIP (VPN endpoint)"
  value       = aws_eip.nv_branch1_sdwan_outside_eip.public_ip
}

output "nv_branch2_outside_eip" {
  description = "Virginia Branch2 - Outside EIP (VPN endpoint)"
  value       = aws_eip.nv_branch2_sdwan_outside_eip.public_ip
}

output "nv_sdwan_outside_eip" {
  description = "Virginia SD-WAN - Outside EIP (VPN endpoint)"
  value       = aws_eip.nv_sdwan_sdwan_outside_eip.public_ip
}

# =============================================================================
# Elastic IP Outputs - Management interfaces (for SSH/SSM access)
# =============================================================================

output "fra_branch1_mgmt_eip" {
  description = "Frankfurt Branch1 - Management EIP"
  value       = aws_eip.fra_branch1_sdwan_mgmt_eip.public_ip
}

output "fra_sdwan_mgmt_eip" {
  description = "Frankfurt SD-WAN - Management EIP"
  value       = aws_eip.fra_sdwan_sdwan_mgmt_eip.public_ip
}

output "nv_branch1_mgmt_eip" {
  description = "Virginia Branch1 - Management EIP"
  value       = aws_eip.nv_branch1_sdwan_mgmt_eip.public_ip
}

output "nv_branch2_mgmt_eip" {
  description = "Virginia Branch2 - Management EIP"
  value       = aws_eip.nv_branch2_sdwan_mgmt_eip.public_ip
}

output "nv_sdwan_mgmt_eip" {
  description = "Virginia SD-WAN - Management EIP"
  value       = aws_eip.nv_sdwan_sdwan_mgmt_eip.public_ip
}

# =============================================================================
# VPN Configuration Reference
# =============================================================================

output "vpn_psk" {
  description = "VPN Pre-Shared Key for all tunnels"
  value       = local.vpn_psk
  sensitive   = true
}

output "serial_console_password" {
  description = "Password for ubuntu user on EC2 serial console"
  value       = local.serial_console_password
  sensitive   = true
}

output "vpn_bgp_asns" {
  description = "BGP ASNs for VPN routers"
  value = {
    sdwan   = var.sdwan_bgp_asn
    branch1 = var.branch1_bgp_asn
  }
}

# =============================================================================
# Cloud WAN Outputs
# =============================================================================

output "cloudwan_core_network_id" {
  description = "Cloud WAN Core Network ID"
  value       = aws_networkmanager_core_network.main.id
}

output "cloudwan_core_network_arn" {
  description = "Cloud WAN Core Network ARN"
  value       = aws_networkmanager_core_network.main.arn
}

output "cloudwan_nv_sdwan_vpc_attachment_id" {
  description = "Cloud WAN VPC Attachment ID for nv-sdwan"
  value       = aws_networkmanager_vpc_attachment.nv_sdwan.id
}

output "cloudwan_fra_sdwan_vpc_attachment_id" {
  description = "Cloud WAN VPC Attachment ID for fra-sdwan"
  value       = aws_networkmanager_vpc_attachment.fra_sdwan.id
}

output "cloudwan_nv_sdwan_connect_attachment_id" {
  description = "Cloud WAN Connect Attachment ID for nv-sdwan"
  value       = aws_networkmanager_connect_attachment.nv_sdwan.id
}

output "cloudwan_fra_sdwan_connect_attachment_id" {
  description = "Cloud WAN Connect Attachment ID for fra-sdwan"
  value       = aws_networkmanager_connect_attachment.fra_sdwan.id
}

output "cloudwan_nv_sdwan_connect_peer_config" {
  description = "Connect peer BGP configuration for nv-sdwan"
  value       = aws_networkmanager_connect_peer.nv_sdwan.configuration
}

output "cloudwan_fra_sdwan_connect_peer_config" {
  description = "Connect peer BGP configuration for fra-sdwan"
  value       = aws_networkmanager_connect_peer.fra_sdwan.configuration
}

output "cloudwan_asn" {
  description = "Cloud WAN Core Network BGP ASN"
  value       = var.cloudwan_asn
}

# =============================================================================
# SDWAN Internal ENI Private IP Outputs (for Connect Peer peer_address)
# =============================================================================

output "nv_sdwan_internal_private_ip" {
  description = "Virginia SD-WAN - Internal ENI Private IP (Connect Peer peer_address)"
  value       = aws_network_interface.nv_sdwan_sdwan_internal.private_ip
}

output "fra_sdwan_internal_private_ip" {
  description = "Frankfurt SD-WAN - Internal ENI Private IP (Connect Peer peer_address)"
  value       = aws_network_interface.fra_sdwan_sdwan_internal.private_ip
}

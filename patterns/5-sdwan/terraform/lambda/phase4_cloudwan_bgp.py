"""
Phase 4 Cloud WAN BGP vbash script generation.

Python equivalent of the build_cloudwan_bgp_script() function from
phase4-cloudwan-bgp-config.sh, extracted for property-based testing.
"""

SDWAN_BGP_ASN = 65001
CLOUDWAN_ASN = 64512

# Private subnet gateways (first IP in each private subnet)
PRIVATE_SUBNET_GW = {
    "nv-sdwan": "10.201.1.1",
    "fra-sdwan": "10.200.1.1",
}

# Instance-to-region mapping
INSTANCE_REGIONS = {
    "nv-sdwan": "us-east-1",
    "fra-sdwan": "eu-central-1",
}


def build_cloudwan_bgp_script(
    router_name: str,
    cloudwan_peer_ip: str,
    appliance_ip: str,
    private_subnet_gw: str | None = None,
) -> str:
    """Generate a vbash script for Cloud WAN BGP configuration on a VyOS SDWAN router.

    Args:
        router_name: Name of the SDWAN router (nv-sdwan or fra-sdwan).
        cloudwan_peer_ip: Core network side IP (BGP neighbor address).
        appliance_ip: Appliance side IP from inside CIDR (dum0 address).
        private_subnet_gw: Private subnet gateway for static route next-hop.
            Defaults to the known gateway for the router_name.

    Returns:
        A vbash script string.
    """
    if private_subnet_gw is None:
        private_subnet_gw = PRIVATE_SUBNET_GW[router_name]

    return f"""#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure

# Dummy interface for Cloud WAN Connect peer inside address
set interfaces dummy dum0 address {appliance_ip}/32

# Static route to Cloud WAN peer via private subnet gateway
set protocols static route {cloudwan_peer_ip}/32 next-hop {private_subnet_gw}

# BGP neighbor for Cloud WAN
set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} remote-as {CLOUDWAN_ASN}
set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} update-source {appliance_ip}
set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} ebgp-multihop 4
set protocols bgp {SDWAN_BGP_ASN} neighbor {cloudwan_peer_ip} address-family ipv4-unicast

commit
save
exit
"""

"""
Phase 5 Lambda Handler — Advanced Routing Demo Prefix Injection.

Injects demo prefixes on branch routers via static blackhole routes and BGP
network statements, then configures route-maps with BGP communities on SD-WAN
routers for outbound advertisement toward Cloud WAN.

Note: VyOS config directory permissions are fixed in Phase 1 (the chgrp
vyattacfg fix). Phase 5 assumes Phase 1 has already run.

Two-step process per region:
  1. Branch router: Dummy interfaces (pingable) + redistribute connected
  2. SD-WAN router: Prefix-lists, route-map with community tagging,
     applied outbound to Cloud WAN BGP peers
"""

import os
from ssm_utils import get_instance_configs, send_and_wait


SSM_PARAM_PREFIX = os.environ.get("SSM_PARAM_PREFIX", "/sdwan/")
SSM_TIMEOUT = int(os.environ.get("SSM_TIMEOUT", "300"))

BRANCH_BGP_ASN = {
    "fra-branch1": 65004,
    "nv-branch1": 65002,
}
SDWAN_BGP_ASN = {
    "fra-sdwan": 65003,
    "nv-sdwan": 65001,
}

# All routers involved in phase5
BRANCH_ROUTERS = ["fra-branch1", "nv-branch1"]
SDWAN_ROUTERS = ["fra-sdwan", "nv-sdwan"]

# Demo prefixes per region — branch routers originate these via dummy interfaces
# addr uses /24 so redistribute connected advertises a /24 that matches the prefix-lists
DEMO_PREFIXES = {
    "fra-branch1": {
        "prod":    {"net": "172.16.100.0/24", "addr": "172.16.100.1/24"},
        "dev":     {"net": "172.16.200.0/24", "addr": "172.16.200.1/24"},
        "blocked": {"net": "172.16.99.0/24",  "addr": "172.16.99.1/24"},
    },
    "nv-branch1": {
        "prod":    {"net": "172.17.100.0/24", "addr": "172.17.100.1/24"},
        "dev":     {"net": "172.17.200.0/24", "addr": "172.17.200.1/24"},
        "blocked": {"net": "172.17.99.0/24",  "addr": "172.17.99.1/24"},
    },
}

# Community tags — same scheme both regions
COMMUNITY_MAP = {
    "prod":    "65001:100",
    "dev":     "65001:200",
    "blocked": "65001:999",
}

# Which SD-WAN router corresponds to which branch
BRANCH_TO_SDWAN = {
    "fra-branch1": "fra-sdwan",
    "nv-branch1":  "nv-sdwan",
}


def build_branch_script(router_name):
    """Generate SSM command for branch router: dummy interfaces + redistribute connected.

    Creates VyOS dummy interfaces with demo prefix addresses (pingable),
    then enables redistribute connected in BGP so the dummy interface
    subnets are advertised to the SD-WAN peer.

    Args:
        router_name: One of fra-branch1, nv-branch1

    Returns:
        str: Shell script for SSM RunShellScript
    """
    prefixes = DEMO_PREFIXES[router_name]

    vbash_lines = ""
    for idx, (role, info) in enumerate(prefixes.items()):
        dum_name = f"dum{idx}"
        vbash_lines += """
# {role} — dummy interface
set interfaces dummy {dum} address {addr}
set interfaces dummy {dum} description '{role} workload prefix'
""".format(role=role, dum=dum_name, addr=info["addr"])

    # Redistribute connected so dummy interface subnets are advertised
    vbash_lines += """
# Redistribute connected routes into BGP (picks up dummy interfaces)
set protocols bgp {asn} address-family ipv4-unicast redistribute connected
""".format(asn=BRANCH_BGP_ASN[router_name])

    vbash_script = """#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure

{lines}
commit
save
exit
""".format(lines=vbash_lines)

    return """#!/bin/bash
set -e

echo "=== Phase 5: Configuring dummy interfaces on {router} ==="
cat > /tmp/vyos-phase5-branch.sh <<'PHASE5EOF'
{vbash_script}
PHASE5EOF

lxc file push /tmp/vyos-phase5-branch.sh router/tmp/vyos-phase5-branch.sh
lxc exec router -- chmod +x /tmp/vyos-phase5-branch.sh
lxc exec router -- /tmp/vyos-phase5-branch.sh

echo "=== Phase 5: Branch config complete on {router} ==="
""".format(router=router_name, vbash_script=vbash_script)


def build_sdwan_script(router_name, configs):
    """Generate SSM command for SD-WAN router: prefix-lists, route-map, apply to CW peers.

    Creates VyOS prefix-lists matching each demo prefix, a route-map that
    stamps the appropriate community on each, and applies it outbound to
    the Cloud WAN BGP neighbors with send-community enabled.

    Args:
        router_name: One of fra-sdwan, nv-sdwan
        configs: Dict from get_instance_configs() with cloudwan params

    Returns:
        str: Shell script for SSM RunShellScript
    """
    # Find which branch this SD-WAN router serves
    branch_name = None
    for br, sd in BRANCH_TO_SDWAN.items():
        if sd == router_name:
            branch_name = br
            break

    prefixes = DEMO_PREFIXES[branch_name]
    peer_ip1 = configs[router_name].get("cloudwan_peer_ip1", "")
    peer_ip2 = configs[router_name].get("cloudwan_peer_ip2", "")

    # Build prefix-list and route-map config
    vbash_lines = ""
    rule_num = 10
    for role, info in prefixes.items():
        plist_name = f"DEMO-{role.upper()}"
        community = COMMUNITY_MAP[role]

        vbash_lines += """
# Prefix-list and route-map rule for {role}
set policy prefix-list {plist} rule 10 prefix {net}
set policy prefix-list {plist} rule 10 action permit
set policy route-map CLOUDWAN-OUT rule {rn} match ip address prefix-list {plist}
set policy route-map CLOUDWAN-OUT rule {rn} set community '{community}'
set policy route-map CLOUDWAN-OUT rule {rn} action permit
""".format(role=role, plist=plist_name, net=info["net"],
           rn=rule_num, community=community)
        rule_num += 10

    # Default permit rule for all other routes (existing loopback, VPC, etc.)
    vbash_lines += """
# Default permit for existing routes
set policy route-map CLOUDWAN-OUT rule 1000 action permit
"""

    # Apply route-map and send-community to Cloud WAN peers
    for peer_ip in [peer_ip1, peer_ip2]:
        if peer_ip:
            vbash_lines += """
# Apply to Cloud WAN peer {peer}
set protocols bgp {asn} neighbor {peer} address-family ipv4-unicast route-map export CLOUDWAN-OUT
set protocols bgp {asn} neighbor {peer} address-family ipv4-unicast send-community standard
set protocols bgp {asn} neighbor {peer} address-family ipv4-unicast soft-reconfiguration inbound
""".format(asn=SDWAN_BGP_ASN[router_name], peer=peer_ip)

    vbash_script = """#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure

{lines}
commit
save
exit
""".format(lines=vbash_lines)

    return """#!/bin/bash
set -e

echo "=== Phase 5: Configuring route-map and communities on {router} ==="
cat > /tmp/vyos-phase5-sdwan.sh <<'PHASE5EOF'
{vbash_script}
PHASE5EOF

lxc file push /tmp/vyos-phase5-sdwan.sh router/tmp/vyos-phase5-sdwan.sh
lxc exec router -- chmod +x /tmp/vyos-phase5-sdwan.sh
lxc exec router -- /tmp/vyos-phase5-sdwan.sh

echo "=== Phase 5: SD-WAN config complete on {router} ==="
""".format(router=router_name, vbash_script=vbash_script)


def handler(event, context):
    """Lambda handler for Phase 5 advanced routing demo setup.

    Step 1: Configure branch routers (dummy interfaces + BGP networks)
    Step 2: Configure SD-WAN routers (route-map + communities toward Cloud WAN)

    Both regions are configured in parallel within each step.
    """
    configs = get_instance_configs(param_prefix=SSM_PARAM_PREFIX)

    results = {}
    success_count = 0
    fail_count = 0

    # Step 1: Branch routers — create dummy interfaces and BGP networks
    for router_name in BRANCH_ROUTERS:
        if router_name not in configs:
            results[router_name] = {
                "status": "Failed",
                "command_id": "",
                "instance_id": "",
                "stdout": "",
                "stderr": f"Instance config not found for {router_name}",
            }
            fail_count += 1
            continue

        instance_id = configs[router_name]["instance_id"]
        region = configs[router_name]["region"]

        ssm_cmd = build_branch_script(router_name)
        result = send_and_wait(
            instance_id=instance_id,
            region=region,
            commands=ssm_cmd,
            timeout=SSM_TIMEOUT,
        )
        results[router_name] = result

        if result["status"] == "Success":
            success_count += 1
        else:
            fail_count += 1

    # Step 2: SD-WAN routers — route-map with community tagging
    for router_name in SDWAN_ROUTERS:
        if router_name not in configs:
            results[router_name] = {
                "status": "Failed",
                "command_id": "",
                "instance_id": "",
                "stdout": "",
                "stderr": f"Instance config not found for {router_name}",
            }
            fail_count += 1
            continue

        instance_id = configs[router_name]["instance_id"]
        region = configs[router_name]["region"]

        ssm_cmd = build_sdwan_script(router_name, configs)
        result = send_and_wait(
            instance_id=instance_id,
            region=region,
            commands=ssm_cmd,
            timeout=SSM_TIMEOUT,
        )
        results[router_name] = result

        if result["status"] == "Success":
            success_count += 1
        else:
            fail_count += 1

    return {
        "phase": "phase5",
        "results": results,
        "success_count": success_count,
        "fail_count": fail_count,
    }

# Phase 5 — Advanced Routing Policy Demo (Lambda + Console)

Demonstrate Cloud WAN Advanced Routing Policy using community-based segment
leaking across both regions. A Lambda function (phase5) handles all VyOS
configuration via SSM — creating dummy interfaces on branch routers and
configuring route-maps with BGP communities on SD-WAN routers. Cloud WAN
routing policies (configured in the Console) then:

- Leak production-tagged routes (65001:100) into a **production** segment
- Leak development-tagged routes (65001:200) into a **development** segment
- Drop blocked-tagged routes (65001:999) entirely

> VyOS config is pushed by the phase5 Lambda via SSM (same pattern as
> phases 1–4). Cloud WAN policy changes are done in the AWS Console.

---

## Architecture

```
us-east-1                                                          eu-central-1
─────────────────────────────────────────────────────────────────────────────────────────

nv-branch1 (ASN 65002)        nv-sdwan (ASN 65001)                fra-sdwan (ASN 65003)        fra-branch1 (ASN 65004)
┌────────────────────┐ IPsec ┌────────────────────┐   Connect    ┌────────────────────┐ Connect ┌────────────────────┐ IPsec ┌────────────────────┐
│ Prefixes:          │◄─────►│ Route-map tags:    │◄────────────►│                    │◄───────►│ Route-map tags:    │◄─────►│ Prefixes:          │
│ 172.17.100.0/24 PRD│ VTI   │ 172.17.100.0→      │  NO_ENCAP   │   Cloud WAN Core   │NO_ENCAP │ 172.16.100.0→      │ VTI   │ 172.16.100.0/24 PRD│
│ 172.17.200.0/24 DEV│100.1/2│   65001:100        │             │     Network        │         │   65001:100        │100.13 │ 172.16.200.0/24 DEV│
│ 172.17.99.0/24 BLK │       │ 172.17.200.0→      │             │                    │         │ 172.16.200.0→      │  /14  │ 172.16.99.0/24 BLK │
│                    │       │   65001:200        │             │  sdwan segment     │         │   65001:200        │       │                    │
│ (dummy interfaces) │       │ 172.17.99.0→       │             │  ├ inbound: drop   │         │ 172.16.99.0→       │       │ (dummy interfaces) │
└────────────────────┘       │   65001:999        │             │  │  65001:999       │         │   65001:999        │       └────────────────────┘
                             │                    │             │  ├ share→prod:     │         │                    │
                             │ VPC 10.201.0.0/16  │             │  │  allow 65001:100│         │ VPC 10.200.0.0/16  │
                             └────────────────────┘             │  ├ share→dev:      │         └────────────────────┘
                                                                │  │  allow 65001:200│
                                                                │  │                 │
                                                                │  production segment│
                                                                │   → 172.17.100.0  │
                                                                │   → 172.16.100.0  │
                                                                │  development seg.  │
                                                                │   → 172.17.200.0  │
                                                                │   → 172.16.200.0  │
                                                                └────────────────────┘
```

---

## Quick Reference

### BGP ASN Assignments

| Router | Region | ASN | Role |
|--------|--------|-----|------|
| nv-sdwan | us-east-1 | 65001 | SD-WAN hub — tags prefixes with communities |
| nv-branch1 | us-east-1 | 65002 | Branch — originates demo prefixes |
| fra-sdwan | eu-central-1 | 65003 | SD-WAN hub — tags prefixes with communities |
| fra-branch1 | eu-central-1 | 65004 | Branch — originates demo prefixes |
| Cloud WAN us-east-1 CNE | us-east-1 | 64512 | Core network edge |
| Cloud WAN eu-central-1 CNE | eu-central-1 | 64513 | Core network edge |
| Core network ASN range | — | 64512–64520 | Narrowed to avoid overlap with community ASNs |

### Demo Subnets — Where Each Prefix Lives

| Subnet | Dummy IF | Host IP | Originated By | Region |
|--------|----------|---------|---------------|--------|
| 172.16.100.0/24 | dum0 | 172.16.100.1 | fra-branch1 | eu-central-1 |
| 172.16.200.0/24 | dum1 | 172.16.200.1 | fra-branch1 | eu-central-1 |
| 172.16.99.0/24 | dum2 | 172.16.99.1 | fra-branch1 | eu-central-1 | arn:aws:ec2:us-west-2:579137394270:prefix-list/pl-0ac86a083f99fb65b
| 172.17.100.0/24 | dum0 | 172.17.100.1 | nv-branch1 | us-east-1 |
| 172.17.200.0/24 | dum1 | 172.17.200.1 | nv-branch1 | us-east-1 |
| 172.17.99.0/24 | dum2 | 172.17.99.1 | nv-branch1 | us-east-1 | arn:aws:ec2:us-west-2:579137394270:prefix-list/pl-0e2d49ec25a5d7668

### Community Tagging (applied by SD-WAN routers outbound to Cloud WAN)

| Subnet Pattern | Community | Meaning | Cloud WAN Action |
|----------------|-----------|---------|-----------------|
| 172.1x.100.0/24 | 65001:100 | Production | Leaked to **production** segment |
| 172.1x.200.0/24 | 65001:200 | Development | Leaked to **development** segment |
| 172.1x.99.0/24 | 65001:999 | Blocked | **Dropped** at sdwan inbound |

### BGP Path: Branch → Cloud WAN

```
fra-branch1 (65004)                fra-sdwan (65003)                Cloud WAN (64513)
  dum0: 172.16.100.1/24    eBGP     receives 172.16.100.0/24  eBGP   receives 172.16.100.0/24
  redistribute connected ────────►  route-map CLOUDWAN-OUT   ────────►  with community 65001:100
                                     sets community 65001:100
                                     send-community standard

nv-branch1 (65002)                 nv-sdwan (65001)                 Cloud WAN (64512)
  dum0: 172.17.100.1/24    eBGP     receives 172.17.100.0/24  eBGP   receives 172.17.100.0/24
  redistribute connected ────────►  route-map CLOUDWAN-OUT   ────────►  with community 65001:100
                                     sets community 65001:100
                                     send-community standard
```

### Existing VPC CIDRs (not part of phase5, for reference)

| VPC | Region | CIDR |
|-----|--------|------|
| fra-branch1 | eu-central-1 | 10.10.0.0/20 |
| fra-sdwan | eu-central-1 | 10.200.0.0/16 |
| nv-branch1 | us-east-1 | 10.20.0.0/20 |
| nv-sdwan | us-east-1 | 10.201.0.0/16 |
| Cloud WAN inside | Global | 10.100.0.0/16 |

### Cloud WAN Segments

| Segment | Purpose |
|---------|---------|
| hybrid | SD-WAN Connect attachments (both regions) — all routes land here first |
| production | Only receives routes tagged 65001:100 (via segment share from hybrid) |
| development | Only receives routes tagged 65001:200 (via segment share from hybrid) |

---

## Extended Communities vs Standard Communities

**Cloud WAN supports standard BGP communities only** (RFC 1997, `ASN:VALUE`).
Extended communities (RFC 4360) and large communities (RFC 8092) are not
recognized by Cloud WAN routing policy rules.

### What Standard Communities Can Do on Cloud WAN

| Capability | Direction | How |
|------------|-----------|-----|
| Match on community | Inbound | `community-in-list` condition |
| Filter by community | Inbound | Match → `drop` or `allow` |
| Set local-preference | Inbound | Match → `set-local-preference` |
| Prepend AS-path | Both | Match → `prepend-asn-list` |
| Add community | Outbound | `add-community` action |
| Remove community | Outbound | `remove-community` action |
| Summarize | Outbound | Match → `summarize` |
| Transitive pass-through | Both | Communities carry across CNE-to-CNE and segment shares |


---

## Step 1 — Deploy the Phase 5 Lambda

The phase5 Lambda function is already defined in `lambda.tf`. Deploy it:

```bash
terraform apply -target=aws_lambda_function.sdwan_phase5
```

## Step 2 — Run the Phase 5 Lambda

Invoke the Lambda to push all VyOS config to both regions:

```bash
aws lambda invoke \
  --function-name sdwan-phase5 \
  --region us-east-1 \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/phase5-result.json

cat /tmp/phase5-result.json | python3 -m json.tool
```

### What the Lambda does

On **all four routers** — fixes VyOS config directory permissions first:
```bash
chgrp -R vyattacfg /opt/vyatta/config/active/
chmod -R g+rw /opt/vyatta/config/active/
chgrp -R vyattacfg /opt/vyatta/etc/quagga/
chmod -R g+rw /opt/vyatta/etc/quagga/
```
This is needed because the LXD container's config directories are owned by
`root:root` instead of `root:vyattacfg`, preventing VyOS from committing.

On each **branch router** (fra-branch1, nv-branch1):
1. Creates static blackhole routes for the demo prefixes
2. Adds BGP `network` statements to advertise them toward the SD-WAN router

On each **SD-WAN router** (fra-sdwan, nv-sdwan):
1. Creates prefix-lists matching each demo prefix
2. Creates route-map `CLOUDWAN-OUT` with rules tagging each prefix:
   - 172.1x.100.0/24 → community 65001:100 (production)
   - 172.1x.200.0/24 → community 65001:200 (development)
   - 172.1x.99.0/24 → community 65001:999 (blocked)
   - Rule 1000: permit all other routes unchanged
3. Applies the route-map outbound to Cloud WAN BGP peers
4. Enables `send-community standard` on Cloud WAN peers

### Verify on VyOS (optional)

SSH into any router via SSM to confirm:

```bash
# On fra-branch1 — check dummy interfaces exist
lxc exec router -- ip addr show dum0
lxc exec router -- ip addr show dum1
lxc exec router -- ip addr show dum2

# On fra-sdwan — check communities are attached
lxc exec router -- /opt/vyatta/bin/vyatta-op-cmd-wrapper show ip bgp 172.16.100.0/24
lxc exec router -- /opt/vyatta/bin/vyatta-op-cmd-wrapper show ip bgp neighbors <PEER_IP> advertised-routes
```

---

## Step 3 — Cloud WAN Policy Changes (AWS Console)

### 3a. Upgrade policy version

1. Network Manager → Core Network → Policy versions
2. Edit latest → Network Configuration → General Settings
3. Set version to **2025.11**

### 3b. Create three segments

Rename `sdwan` to `hybrid`. Add production and development:

```json
"segments": [
  {
    "name": "hybrid",
    "require-attachment-acceptance": false
  },
  {
    "name": "production",
    "require-attachment-acceptance": false
  },
  {
    "name": "development",
    "require-attachment-acceptance": false
  }
]
```

> Update the `segment` tag on both Connect attachments from `sdwan` to
> `hybrid`. Update attachment-policies condition to match `hybrid`.

### 3c. Routing Policy 1 — Inbound filter on hybrid (drop 65001:999)

```json
{
  "routing-policy-name": "hybrid-inbound-filter",
  "routing-policy-description": "Drop routes tagged 65001:999 from SD-WAN",
  "routing-policy-direction": "inbound",
  "routing-policy-number": 100,
  "routing-policy-rules": [
    {
      "rule-number": 100,
      "rule-definition": {
        "match-conditions": [
          { "type": "community-in-list", "value": "65001:999" }
        ],
        "condition-logic": "or",
        "action": { "type": "drop" }
      }
    },
    {
      "rule-number": 1000,
      "rule-definition": {
        "match-conditions": [
          { "type": "prefix-in-cidr", "value": "0.0.0.0/0" }
        ],
        "condition-logic": "or",
        "action": { "type": "allow" }
      }
    }
  ]
}
```

### 3d. Routing Policy 2 — Segment share: hybrid → production

```json
{
  "routing-policy-name": "hybrid-to-production",
  "routing-policy-description": "Leak only 65001:100 routes to prod segment",
  "routing-policy-direction": "inbound",
  "routing-policy-number": 200,
  "routing-policy-rules": [
    {
      "rule-number": 100,
      "rule-definition": {
        "match-conditions": [
          { "type": "community-in-list", "value": "65001:100" }
        ],
        "condition-logic": "or",
        "action": { "type": "allow" }
      }
    }
  ]
}
```

### 3e. Routing Policy 3 — Segment share: hybrid → development

```json
{
  "routing-policy-name": "hybrid-to-development",
  "routing-policy-description": "Leak only 65001:200 routes to dev segment",
  "routing-policy-direction": "inbound",
  "routing-policy-number": 300,
  "routing-policy-rules": [
    {
      "rule-number": 100,
      "rule-definition": {
        "match-conditions": [
          { "type": "community-in-list", "value": "65001:200" }
        ],
        "condition-logic": "or",
        "action": { "type": "allow" }
      }
    }
  ]
}
```

### 3f. Segment-actions

```json
"segment-actions": [
  {
    "action": "share",
    "mode": "attachment-route",
    "segment": "hybrid",
    "share-with": ["production"],
    "routing-policy-names": ["hybrid-to-production"]
  },
  {
    "action": "share",
    "mode": "attachment-route",
    "segment": "hybrid",
    "share-with": ["development"],
    "routing-policy-names": ["hybrid-to-development"]
  }
]
```

### 3g. Attachment routing policy rule

```json
"attachment-routing-policy-rules": [
  {
    "rule-number": 100,
    "description": "Apply inbound community filter to hybrid Connect attachments",
    "conditions": [
      { "type": "routing-policy-label", "value": "hybrid-sdwan-filter" }
    ],
    "action": {
      "associate-routing-policies": ["hybrid-inbound-filter"]
    }
  }
]
```

Apply label `hybrid-sdwan-filter` to BOTH Connect attachments:
1. fra-sdwan-connect-attachment → Routing policy label → `hybrid-sdwan-filter`
2. nv-sdwan-connect-attachment → Routing policy label → `hybrid-sdwan-filter`

### 3h. Apply the policy version

Review diff → Apply → wait for "Execution succeeded"


---

## Step 4 — Verify

### 4a. Cloud WAN — hybrid segment (both CNEs)

**Route information base** (RIB — before policy):
- All six demo /24s should appear with communities visible

**Routes** tab (FIB — after policy):
- 10.10x.100.0/24 ✅ (65001:100, allowed)
- 10.10x.200.0/24 ✅ (65001:200, allowed)
- 10.10x.99.0/24 ❌ (65001:999, dropped)

### 4b. Production segment (both CNEs)

| Prefix | Origin | Present? |
|--------|--------|----------|
| 172.16.100.0/24 | Frankfurt | ✅ |
| 172.17.100.0/24 | Virginia | ✅ |
| All others | — | ❌ |

### 4c. Development segment (both CNEs)

| Prefix | Origin | Present? |
|--------|--------|----------|
| 172.16.200.0/24 | Frankfurt | ✅ |
| 172.17.200.0/24 | Virginia | ✅ |
| All others | — | ❌ |

### 4d. Full summary matrix

| Prefix | Community | hybrid | production | development |
|--------|-----------|--------|------------|-------------|
| 172.16.100.0/24 (FRA) | 65001:100 | ✅ | ✅ | ❌ |
| 172.16.200.0/24 (FRA) | 65001:200 | ✅ | ❌ | ✅ |
| 172.16.99.0/24 (FRA) | 65001:999 | ❌ | ❌ | ❌ |
| 172.17.100.0/24 (NV) | 65001:100 | ✅ | ✅ | ❌ |
| 172.17.200.0/24 (NV) | 65001:200 | ✅ | ❌ | ✅ |
| 172.17.99.0/24 (NV) | 65001:999 | ❌ | ❌ | ❌ |

### Demo Talking Points

1. **Multi-region, single policy** — Same routing policies work at both
   CNEs. Label `hybrid-sdwan-filter` applied to both Connect attachments.

2. **SD-WAN signals intent via communities** — Branch routers just
   advertise prefixes. SD-WAN routers tag them. Cloud WAN acts on the
   tag, not the prefix.

3. **Two-stage filtering** — Inbound policy drops 65001:999 at hybrid.
   Segment-share policies selectively leak to prod/dev. Defense in depth.

4. **Cross-region visibility** — Production prefixes from Frankfurt appear
   in production segment at Virginia CNE and vice versa.

5. **RIB vs FIB** — Route information base shows pre-policy state. Routes
   tab shows post-policy. The "before and after" for troubleshooting.

---

## Step 5 — Cleanup

### Remove VyOS config (invoke Lambda or run manually)

To reverse the VyOS changes, either create a phase5-cleanup Lambda or
run these SSM commands manually:

**Branch routers** (fra-branch1, nv-branch1) — push a vbash script:
```
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
delete protocols static route 172.16.100.0/24
delete protocols static route 172.16.200.0/24
delete protocols static route 172.16.99.0/24
delete protocols bgp 65002 network 172.16.100.0/24
delete protocols bgp 65002 network 172.16.200.0/24
delete protocols bgp 65002 network 172.16.99.0/24
commit
save
exit
```
(Use 172.17.x.x for nv-branch1)

**SD-WAN routers** (fra-sdwan, nv-sdwan):
```
#!/bin/vbash
source /opt/vyatta/etc/functions/script-template
configure
delete protocols bgp 65001 neighbor <PEER_IP1> address-family ipv4-unicast route-map export CLOUDWAN-OUT
delete protocols bgp 65001 neighbor <PEER_IP2> address-family ipv4-unicast route-map export CLOUDWAN-OUT
delete protocols bgp 65001 neighbor <PEER_IP1> address-family ipv4-unicast send-community
delete protocols bgp 65001 neighbor <PEER_IP2> address-family ipv4-unicast send-community
delete policy route-map CLOUDWAN-OUT
delete policy prefix-list DEMO-PROD
delete policy prefix-list DEMO-DEV
delete policy prefix-list DEMO-BLOCKED
commit
save
exit
```

### Cloud WAN

1. Remove routing policy label from both Connect attachments
2. Remove segment-actions
3. Delete routing policies
4. Delete production and development segments (or rename hybrid back)
5. Apply reverted policy version

---

## Appendix A — Full Cloud WAN Policy Document (Demo State)

```json
{
  "version": "2025.11",
  "core-network-configuration": {
    "vpn-ecmp-support": false,
    "asn-ranges": ["64512-64520"],
    "inside-cidr-blocks": ["10.100.0.0/16"],
    "edge-locations": [
      { "location": "us-east-1", "inside-cidr-blocks": ["10.100.0.0/24"] },
      { "location": "eu-central-1", "inside-cidr-blocks": ["10.100.1.0/24"] }
    ]
  },
  "segments": [
    { "name": "hybrid", "require-attachment-acceptance": false },
    { "name": "production", "require-attachment-acceptance": false },
    { "name": "development", "require-attachment-acceptance": false }
  ],
  "attachment-policies": [
    {
      "rule-number": 100,
      "condition-logic": "or",
      "conditions": [
        { "type": "tag-value", "operator": "equals", "key": "segment", "value": "hybrid" }
      ],
      "action": { "association-method": "tag", "tag-value-of-key": "segment" }
    }
  ],
  "attachment-routing-policy-rules": [
    {
      "rule-number": 100,
      "description": "Apply inbound community filter to hybrid Connect attachments",
      "conditions": [
        { "type": "routing-policy-label", "value": "hybrid-sdwan-filter" }
      ],
      "action": { "associate-routing-policies": ["hybrid-inbound-filter"] }
    }
  ],
  "segment-actions": [
    {
      "action": "share", "mode": "attachment-route",
      "segment": "hybrid", "share-with": ["production"],
      "routing-policy-names": ["hybrid-to-production"]
    },
    {
      "action": "share", "mode": "attachment-route",
      "segment": "hybrid", "share-with": ["development"],
      "routing-policy-names": ["hybrid-to-development"]
    }
  ],
  "routing-policies": [
    {
      "routing-policy-name": "hybrid-inbound-filter",
      "routing-policy-description": "Drop 65001:999, allow rest",
      "routing-policy-direction": "inbound",
      "routing-policy-number": 100,
      "routing-policy-rules": [
        {
          "rule-number": 100,
          "rule-definition": {
            "match-conditions": [{ "type": "community-in-list", "value": "65001:999" }],
            "condition-logic": "or",
            "action": { "type": "drop" }
          }
        },
        {
          "rule-number": 1000,
          "rule-definition": {
            "match-conditions": [{ "type": "prefix-in-cidr", "value": "0.0.0.0/0" }],
            "condition-logic": "or",
            "action": { "type": "allow" }
          }
        }
      ]
    },
    {
      "routing-policy-name": "hybrid-to-production",
      "routing-policy-description": "Leak only 65001:100 to prod",
      "routing-policy-direction": "inbound",
      "routing-policy-number": 200,
      "routing-policy-rules": [
        {
          "rule-number": 100,
          "rule-definition": {
            "match-conditions": [{ "type": "community-in-list", "value": "65001:100" }],
            "condition-logic": "or",
            "action": { "type": "allow" }
          }
        }
      ]
    },
    {
      "routing-policy-name": "hybrid-to-development",
      "routing-policy-description": "Leak only 65001:200 to dev",
      "routing-policy-direction": "inbound",
      "routing-policy-number": 300,
      "routing-policy-rules": [
        {
          "rule-number": 100,
          "rule-definition": {
            "match-conditions": [{ "type": "community-in-list", "value": "65001:200" }],
            "condition-logic": "or",
            "action": { "type": "allow" }
          }
        }
      ]
    }
  ]
}
```

## Appendix B — ASN Range Caveat

The Cloud WAN docs state: "ASNs specified in the routing policy (community
tags) cannot overlap with the ASN range specified in the core network
configuration."

The ASN range has been narrowed to `64512-64520` (in `cloudwan.tf`) so that
community values like `65001:100` are outside the range and accepted by
Cloud WAN routing policy. The original range `64512-65534` included 65001,
which caused communities to be silently stripped.

---

# Manual Demo Steps — Cloud WAN Console

After running the phase5 Lambda (which configures VyOS routers), follow
these manual steps in the AWS Console to set up Cloud WAN segments and
routing policies.

## Prerequisites

- Phase5 Lambda has run successfully (dummy interfaces on branches,
  route-maps with communities on SD-WAN routers)
- Verify routes are arriving at Cloud WAN: Network Manager → Core Network
  → Routing → select `sdwan` segment → check Route information base for
  the demo /24 prefixes with communities attached

---

## Manual Step 1 — Add Production and Development Segments

1. Open **Network Manager** → **Cloud WAN** → **Core Network**
2. Go to **Policy versions** → select latest → **Edit**
3. Navigate to **Segments** tab
4. Add two new segments:

| Segment Name | Require Acceptance | Description |
|-------------|-------------------|-------------|
| production | No | Routes tagged with community 65001:100 |
| development | No | Routes tagged with community 65001:200 |

5. **Important:** For both new segments, set the default route filter to
   **"Deny all"** (not "Allow all"). If left as "Allow all", the segment
   accepts all shared routes regardless of the routing policy, defeating
   the community-based filtering.
6. Keep the existing `sdwan` segment (this is where Connect attachments live)

Your segments should now be:

| Segment | Purpose |
|---------|---------|
| sdwan | SD-WAN Connect attachments — all routes land here first |
| production | Will receive only production-tagged routes via segment share |
| development | Will receive only development-tagged routes via segment share |

> Do NOT apply the policy yet — continue to Step 2 first.

---

## Manual Step 2 — Create Routing Policies

### 2a. Create inbound routing policy: drop blocked routes

This policy drops routes tagged `65001:999` before they enter the sdwan
segment routing table. All other routes are allowed through.

1. In the policy editor, go to **Routing policies** tab
2. Click **Create routing policy**
3. Fill in:
   - Policy number: `100`
   - Description: `sdwan-inbound-drop-blocked`
   - Direction: **Inbound**
4. Add **Rule 100** — Drop blocked:
   - Rule number: `100`
   - Action: **Drop**
   - Condition: **Community in list** → `65001:999`
5. Add **Rule 1000** — Allow everything else:
   - Rule number: `1000`
   - Action: **Allow**
   - Condition: **Prefix in CIDR** → `0.0.0.0/0`

### 2b. Create segment share routing policy: sdwan → production

This policy controls which routes leak from sdwan into the production
segment. Only routes carrying community `65001:100` are allowed.

1. Click **Create routing policy**
2. Fill in:
   - Policy number: `200`
   - Description: `sdwan-to-production`
   - Direction: **Inbound**
3. Add **Rule 100** — Allow production community:
   - Rule number: `100`
   - Action: **Allow**
   - Condition: **Community in list** → `65001:100`

> No default allow rule needed — unmatched routes are implicitly dropped.
> This means only `65001:100` routes make it into production.

### 2c. Create segment share routing policy: sdwan → development

Same pattern for development. Only `65001:200` routes are allowed.

1. Click **Create routing policy**
2. Fill in:
   - Policy number: `300`
   - Description: `sdwan-to-development`
   - Direction: **Inbound**
3. Add **Rule 100** — Allow development community:
   - Rule number: `100`
   - Action: **Allow**
   - Condition: **Community in list** → `65001:200`

---

## Manual Step 3 — Create Attachment Routing Policy Rule

This associates the inbound drop policy (Step 2a) with the Connect
attachments via a label.

1. Go to **Attachment routing policy rules** tab
2. Click **Create rule**
3. Fill in:
   - Rule number: `100`
   - Description: `Apply inbound filter to sdwan Connect attachments`
   - Condition: **Routing policy label** → `sdwan-community-filter`
   - Action: Associate routing policies → `sdwan-inbound-drop-blocked`

---

## Manual Step 4 — Configure Segment Sharing with Routing Policies

Wire up the segment shares so routes leak from sdwan to prod/dev with
the routing policies controlling what gets through.

1. Go to **Segment actions** tab
2. Add segment share — sdwan → production:
   - Action: **Share**
   - Mode: **attachment-route**
   - Source segment: `sdwan`
   - Share with: `production`
   - Routing policy: `sdwan-to-production`
3. Add segment share — sdwan → development:
   - Action: **Share**
   - Mode: **attachment-route**
   - Source segment: `sdwan`
   - Share with: `development`
   - Routing policy: `sdwan-to-development`

---

## Manual Step 5 — Apply Policy and Label Attachments

### 5a. Apply the policy version

1. Go to **Policy versions** → **View or apply changes**
2. Review the diff — you should see:
   - 2 new segments (production, development)
   - 3 routing policies
   - 1 attachment routing policy rule
   - 2 segment-actions (shares)
3. Click **Apply** → wait for "Execution succeeded"

### 5b. Label the Connect attachments

Apply the routing policy label to both Connect attachments so the inbound
drop policy takes effect:

1. **Network Manager** → **Attachments**
2. Select **nv-sdwan-connect-attachment** → Edit → set Routing policy label
   to `sdwan-community-filter` → Save
3. Select **fra-sdwan-connect-attachment** → Edit → set Routing policy label
   to `sdwan-community-filter` → Save

---

## Manual Step 6 — Verify

### 6a. sdwan segment route table

Go to **Routing** → select segment `sdwan`:

**Route information base** (RIB — pre-policy):
- All six demo /24s visible with communities

**Routes** tab (FIB — post-policy):
- 172.16.100.0/24 ✅ (65001:100)
- 172.16.200.0/24 ✅ (65001:200)
- 172.16.99.0/24 ❌ (65001:999 — dropped)
- 172.17.100.0/24 ✅ (65001:100)
- 172.17.200.0/24 ✅ (65001:200)
- 172.17.99.0/24 ❌ (65001:999 — dropped)

### 6b. production segment route table

Select segment `production`:
- 172.16.100.0/24 ✅ (from Frankfurt, community 65001:100)
- 172.17.100.0/24 ✅ (from Virginia, community 65001:100)
- Nothing else — dev and blocked routes filtered out

### 6c. development segment route table

Select segment `development`:
- 172.16.200.0/24 ✅ (from Frankfurt, community 65001:200)
- 172.17.200.0/24 ✅ (from Virginia, community 65001:200)
- Nothing else — prod and blocked routes filtered out

### 6d. Verification summary

| Prefix | Community | sdwan | production | development |
|--------|-----------|-------|------------|-------------|
| 172.16.100.0/24 (FRA) | 65001:100 | ✅ | ✅ | ❌ |
| 172.16.200.0/24 (FRA) | 65001:200 | ✅ | ❌ | ✅ |
| 172.16.99.0/24 (FRA) | 65001:999 | ❌ | ❌ | ❌ |
| 172.17.100.0/24 (NV) | 65001:100 | ✅ | ✅ | ❌ |
| 172.17.200.0/24 (NV) | 65001:200 | ✅ | ❌ | ✅ |
| 172.17.99.0/24 (NV) | 65001:999 | ❌ | ❌ | ❌ |

---

## Demo Talking Points

1. **Community-based segment leaking** — The SD-WAN router tags each prefix
   with a community. Cloud WAN uses that tag to decide which segment gets
   the route. No prefix-list maintenance — just community values.

2. **Two-stage filtering** — Inbound policy on sdwan segment drops
   `65001:999` first. Then segment-share policies selectively leak only
   the right community to each segment. A route must pass both gates.

3. **Multi-region consistency** — Same policies apply at both CNEs. Both
   Frankfurt and Virginia prefixes appear in the correct segments.

4. **RIB vs FIB** — Show the Route information base (all learned routes
   before policy) vs Routes tab (after policy). This is the key
   troubleshooting view.

5. **Scalable pattern** — New workload class = new community on SD-WAN +
   new segment + new segment-share policy. No per-prefix config anywhere.

6. **Pingable endpoints** — The dummy interfaces on branch routers
   (172.16.100.1, 172.17.100.1, etc.) are real IPs you can ping for
   end-to-end connectivity testing.

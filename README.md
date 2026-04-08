# AWS Cloud WAN Blueprints

Welcome to AWS Cloud WAN Blueprints!

This project contains a collection of AWS Cloud WAN patterns implemented in [AWS CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html) and [Terraform](https://developer.hashicorp.com/terraform) that demonstrate how to configure and deploy global networks using [AWS Cloud WAN](https://aws.amazon.com/cloud-wan/).

## Motivation

AWS Cloud WAN simplifies the configuration and management of global networks by providing a centralized, policy-driven approach to building multi-region connectivity. While Cloud WAN abstracts away much of the complexity of traditional AWS networking (such as manual Transit Gateway peering, static routing, or associations and propagations), understanding all the service's capabilities can be overwhelming, especially when designing production-grade architectures.

AWS customers have asked for practical examples and best practices that demonstrate how to leverage Cloud WAN's full potential. These blueprints provide real-world use cases with complete, tested implementations that teams can use for:

- **Proof of Concepts (PoCs)**: Quickly validate Cloud WAN capabilities in your environment.
- **Testing and learning**: Understand how different features work together through hands-on examples.
- **Starting point**: Use as a foundation for your production network configurations.
- **Best practices**: Learn recommended patterns for common networking scenarios.

With Cloud WAN Blueprints, customers can configure and deploy purpose-built global networks and start onboarding workloads in days, rather than spending weeks or months figuring out the optimal configuration.

## Consumption

AWS Cloud WAN Blueprints have been designed to be consumed in the following manners:

1. **Reference**: Users can refer to the patterns and snippets provided to help guide them to their desired solution. Users will typically view how the pattern or snippet is configured to achieve the desired end result and then replicate that in their environment.

2. **Copy & Paste**: Users can copy and paste the patterns and snippets into their own environment, using Cloud WAN Blueprints as the starting point for their implementation. Users can then adapt the initial pattern to customize it to their specific needs.

**AWS Cloud WAN Blueprints are not intended to be consumed as-is directly from this project**. The patterns provided only contain `variables` when certain information is required to deploy the pattern and generally use local variables. If you wish to deploy the patterns into a different AWS Region or with other changes, it is recommended that you make those modifications locally before applying the pattern.

## Patterns

| Pattern | Description | IaC Support |
|---------|-------------|-------------|
| [1. Simple Architecture](./patterns/1-simple_architecture/) | Basic Cloud WAN setup with segments and attachment policies | Terraform, CloudFormation |
| [2. Multi-AWS Account](./patterns/2-multi_account/) | Cross-account Cloud WAN deployment with AWS RAM sharing | Terraform, CloudFormation |
| [3. Traffic Inspection](./patterns/3-traffic_inspection/) | Various inspection architectures (centralized outbound, east-west) | Terraform, CloudFormation |
| [4. Routing Policies](./patterns/4-routing_policies/) | Advanced routing controls, filtering, and BGP manipulation | Terraform, CloudFormation |
| 5. Hybrid Architectures | On-premises integration patterns with Site-to-Site VPN and Direct Connect | Coming Soon |

## Infrastructure as Code Considerations

AWS Cloud WAN Blueprints do not intend to teach users the recommended practices for Infrastructure as Code (IaC) tools nor does it offer guidance on how users should structure their IaC projects. The patterns provided are intended to show users how they can achieve a defined architecture or configuration in a way that they can quickly and easily get up and running to start interacting with that pattern. Therefore, there are a few considerations users should be aware of when using Cloud WAN Blueprints:

1. We recognize that most users will already have existing VPCs in separate IaC projects or stacks. However, the patterns provided come complete with VPCs to ensure stable, deployable examples that have been tested and validated.

2. Patterns are not intended to be consumed in-place in the same manner that one would consume a reusable module. Therefore, we do not provide extensive parameters and outputs to expose various levels of configuration for the examples. Users can modify the pattern locally after cloning to suit their requirements.

3. The patterns use local variables (Terraform) or parameters (CloudFormation) with sensible defaults. If you wish to deploy patterns into different regions or with other changes, modify these values before deploying.

4. For production deployments, we recommend separating your infrastructure into multiple projects or stacks (e.g., network infrastructure, workload VPCs, inspection resources) to follow IaC best practices and enable independent lifecycle management.

## AWS Cloud WAN Fundamentals

[AWS Cloud WAN](https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html) is a managed, intent-driven service for building and managing global networks across [AWS Regions](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/) and on-premises environments.

### Key Advantages

| Capability | Description |
|------------|-------------|
| **Automated Dynamic Routing** | Cross-region e-BGP routing |
| **Centralized Management** | Policy-driven configuration |
| **Network Segmentation** | Global segments for traffic isolation and routing domains |
| **Advanced Routing** | Fine-grained control with routing policies, filtering, and BGP manipulation |

---

### Control Plane & Network Policy

| Aspect | Details |
|--------|---------|
| **Management Console** | AWS Network Manager |
| **Home Region** | Oregon (us-west-2) - [Learn more](https://docs.aws.amazon.com/network-manager/latest/cloudwan/what-is-cloudwan.html#cloudwan-home-region) |
| **Policy Format** | Declarative JSON document |
| **Policy Defines** | Segments, routing behavior, attachment mappings, access control |

The policy-driven approach automates network configuration while ensuring scalability and consistency across AWS Regions.

---

### Core Network Edge (CNE)

| Aspect | Details |
|--------|---------|
| **Function** | Regional router (similar to Transit Gateway) |
| **Availability** | High-available and resilient |
| **Deployment** | One per AWS Region where Cloud WAN operates |
| **Peering** | Automatic full-mesh between all CNEs |
| **Routing Protocol** | e-BGP for dynamic route exchange |

---

### Segments

Global route table (similar to Transit Gateway route table or VRF domain)

| Characteristic | Description |
|----------------|-------------|
| **Availability** | Present in every Region with a CNE |
| **Regional Scope** | Can be limited to specific Regions |
| **Attachment Requirement** | Only possible in Regions where segment exists |
| **Default Behavior** | Attachments auto-propagate prefixes; intra-segment traffic allowed |
| **Isolation** | Supports isolated and non-isolated attachments |
| **Common Segmentation Patterns** | By environment (dev, test, prod), Business Unit (Org A, Org B, Org C), or Geography (AMER, EMEA, APAC) |

---

### Routing Action: Segment Sharing

Exchange routes between segments (1:1 or 1:many) without inspection.

> **Note**: Non-transitive - requires explicit share action between segments.

### Routing Action: Service Insertion

Define inspection for intra-segment, inter-segment, and egress traffic.

| Component | Description |
|-----------|-------------|
| **Network Function Groups (NFGs)** | Container for inspection VPC attachments |
| **Scope** | Global construct, supports cross-region inspection |
| **Multiple NFGs** | Supported for firewall grouping |

Service Insertion Actions:

| Action | Use Case | Traffic Flow |
|--------|----------|--------------|
| `send-via` | East-west inspection | Intra-segment or inter-segment traffic |
| `send-to` | Egress inspection | North-south traffic (internet-bound) |

### Routing Action: Routing Policies

Fine-grained routing controls for advanced scenarios.

| Capability | Description | Supported Attachments |
|------------|-------------|----------------------|
| **Route Filtering** | Drop routes based on prefixes, prefix lists, or BGP communities | All attachment types |
| **Route Summarization** | Aggregate routes outbound | BGP-capable attachments |
| **Path Preferences** | Influence paths via BGP attributes (Local Pref, AS-PATH, MED) | BGP-capable attachments |
| **BGP Communities** | Transitively pass, match, and act on communities | Site-to-Site VPN, Connect |

> **BGP-capable attachments**: Site-to-Site VPN, Direct Connect, Connect, Transit Gateway peering, CNE-to-CNE

[See AWS documentation for considerations](https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-routing-policies.html#cloudwan-routing-policies-considerations)

---

### Attachments

Connection between network resource and Core Network Edge (CNE)

| Attachment Type | Description | Notes |
|-----------------|-------------|-------|
| **VPC** | Connect VPC to Cloud WAN | Most common attachment type |
| **Site-to-Site VPN** | IPsec tunnel to on-premises | Supports BGP |
| **Direct Connect Gateway** | Dedicated connection to on-premises | Supports BGP |
| **Transit Gateway Route Table** | Integrate existing Transit Gateways | Enables migration path |
| **Connect** | SD-WAN integration (GRE or tunnel-less) | Requires underlay VPC attachment |

> **Important**: Each attachment can only be associated with one segment.

---

### Attachment Policies

Rules that govern how attachments are associated with segments or Network Function Groups (NFGs). Matching Attributes:

| Attribute Type | Description |
|----------------|-------------|
| **Tags** | Key-value pairs on attachments |
| **Attachment Type** | VPC, VPN, Direct Connect, etc. |
| **AWS Account ID** | Source account of attachment |
| **AWS Region** | Region where attachment exists |

> **Note**: Pending attachments cannot access the core network until approved.

## Prerequisites

Before using these blueprints, you should have:

- **AWS Networking Knowledge**: Understanding of VPCs, subnets, route tables, Transit Gateways, and Direct Connect.
- **General Networking Concepts**: Familiarity with IP addressing, routing, IPSec, GRE, BGP, VRFs, SD-WAN, and network security.
- **Infrastructure as Code**: Experience with AWS CloudFormation or Terraform.
- **AWS Account**: An AWS account with appropriate IAM permissions to create networking resources.

## Support & Feedback

AWS Cloud WAN Blueprints are maintained by AWS Solution Architects. This is not part of an AWS service and support is provided as best-effort by the Cloud WAN Blueprints community. To provide feedback, please use the [issues templates](https://github.com/aws-samples/aws-cloud-wan-blueprints/issues) provided. If you are interested in contributing to Cloud WAN Blueprints, see the [Contribution guide](CONTRIBUTING.md).

## FAQ

**Q: Why do some patterns show "Coming Soon"?**

A: We're actively developing the blueprint library. We've structured the repository to show the planned patterns while we work on completing them. See [CONTRIBUTING](./CONTRIBUTING.md) to provide feedback or request new patterns.

**Q: Can I use these patterns in production?**

A: These patterns are **not ready** for production environments. They should be customized for your specific requirements. Update variables, CIDR blocks, and configurations before deploying to production. Always test in pre-production environments first.

**Q: What are the bandwidth and MTU limits for Cloud WAN?**

A: Each Core Network Edge (CNE) supports up to 100 Gbps throughput. For detailed quotas and limits, see the [AWS Cloud WAN quotas documentation](https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-quotas.html).

**Q: Do I need separate AWS accounts to use these patterns?**

A: No, most patterns can be deployed in a single AWS account. However, the [Multi-AWS Account pattern](./patterns/2-multi_account/) demonstrates cross-account deployment using AWS Resource Access Manager (RAM).

**Q: Which IaC tool should I use?**

A: Both CloudFormation and Terraform are supported for most patterns. Choose based on your organization's preferences and existing tooling. Terraform patterns use the [AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) and [AWSCC](https://registry.terraform.io/providers/hashicorp/awscc/latest/docs) providers, while CloudFormation patterns use native AWS resources.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See [LICENSE](LICENSE).

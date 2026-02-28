# Input Variables for SD-WAN Cloud WAN Workshop

variable "instance_type" {
  description = "EC2 instance type for test instances"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "sdwan-cloudwan-workshop"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "workshop"
}

variable "sdwan_instance_type" {
  description = "EC2 instance type for SD-WAN Ubuntu instances"
  type        = string
  default     = "c5.large"
}

variable "vyos_s3_bucket" {
  description = "S3 bucket name containing the VyOS LXD image"
  type        = string
  default     = "fra-vyos-bucket"
}

variable "vyos_s3_region" {
  description = "AWS region of the VyOS S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "vyos_s3_key" {
  description = "S3 object key (filename) for the VyOS LXD image"
  type        = string
  default     = "vyos_dxgl-1.3.3-bc64a3a-5_lxd_amd64.tar.gz"
}

# VPN and BGP Configuration Variables

variable "vpn_psk" {
  description = "Pre-shared key for IPsec VPN authentication. If not provided, a random 32-character PSK will be generated."
  type        = string
  sensitive   = true
  default     = null
}

variable "sdwan_bgp_asn" {
  description = "BGP ASN for SDWAN router"
  type        = number
  default     = 65001
}

variable "branch1_bgp_asn" {
  description = "BGP ASN for Branch1 router"
  type        = number
  default     = 65002
}

variable "vpn_tunnel_cidr" {
  description = "CIDR for VPN tunnel interfaces (/30 subnet)"
  type        = string
  default     = "169.254.100.0/30"
}

# Lambda and Step Functions Variables

variable "lambda_source_dir" {
  description = "Path to Lambda function source code directory"
  type        = string
  default     = "lambda"
}

variable "phase1_wait_seconds" {
  description = "Wait time after Phase1 before starting Phase2 (seconds)"
  type        = number
  default     = 60
}

variable "phase2_wait_seconds" {
  description = "Wait time after Phase2 before starting Phase3 (seconds)"
  type        = number
  default     = 90
}

# Cloud WAN Variables

variable "cloudwan_asn" {
  description = "BGP ASN for Cloud WAN Core Network"
  type        = number
  default     = 64512
}

variable "cloudwan_connect_cidr_nv" {
  description = "Inside CIDR for nv-sdwan Cloud WAN edge (/24 allocated to us-east-1)"
  type        = string
  default     = "10.100.0.0/24"
}

variable "cloudwan_connect_cidr_fra" {
  description = "Inside CIDR for fra-sdwan Cloud WAN edge (/24 allocated to eu-central-1)"
  type        = string
  default     = "10.100.1.0/24"
}

variable "cloudwan_segment_name" {
  description = "Cloud WAN segment name for SDWAN attachments"
  type        = string
  default     = "sdwan"
}

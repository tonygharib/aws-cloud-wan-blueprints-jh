# Virginia Region SD-WAN Ubuntu Instances (us-east-1)
# EC2 instances, ENIs, EIPs, and Security Groups

# -----------------------------------------------------------------------------
# Security Groups - nv-branch1-vpc
# -----------------------------------------------------------------------------

resource "aws_security_group" "nv_branch1_public_sg" {
  provider    = aws.virginia
  name        = "nv-branch1-vpc-sdwan-public-sg"
  description = "Public security group for SD-WAN instance - IKE, NAT-T, SSM"
  vpc_id      = module.nv_branch1_vpc.vpc_id

  # IKE
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NAT-T
  ingress {
    description = "NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ESP (IPsec)
  ingress {
    description = "ESP"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSM from VPC CIDR
  ingress {
    description = "SSM HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.nv_branch1_vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-branch1-vpc-sdwan-public-sg"
  }
}

resource "aws_security_group" "nv_branch1_private_sg" {
  provider    = aws.virginia
  name        = "nv-branch1-vpc-sdwan-private-sg"
  description = "Private security group for SD-WAN instance - internal traffic"
  vpc_id      = module.nv_branch1_vpc.vpc_id

  # All from VPC CIDR
  ingress {
    description = "All from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.nv_branch1_vpc.vpc_cidr_block]
  }

  # All from 10.0.0.0/8 (cross-VPC)
  ingress {
    description = "All from RFC1918"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-branch1-vpc-sdwan-private-sg"
  }
}

# -----------------------------------------------------------------------------
# Security Groups - nv-branch2-vpc
# -----------------------------------------------------------------------------

resource "aws_security_group" "nv_branch2_public_sg" {
  provider    = aws.virginia
  name        = "nv-branch2-vpc-sdwan-public-sg"
  description = "Public security group for SD-WAN instance - IKE, NAT-T, SSM"
  vpc_id      = module.nv_branch2_vpc.vpc_id

  # IKE
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NAT-T
  ingress {
    description = "NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSM from VPC CIDR
  ingress {
    description = "SSM HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.nv_branch2_vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-branch2-vpc-sdwan-public-sg"
  }
}

resource "aws_security_group" "nv_branch2_private_sg" {
  provider    = aws.virginia
  name        = "nv-branch2-vpc-sdwan-private-sg"
  description = "Private security group for SD-WAN instance - internal traffic"
  vpc_id      = module.nv_branch2_vpc.vpc_id

  # All from VPC CIDR
  ingress {
    description = "All from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.nv_branch2_vpc.vpc_cidr_block]
  }

  # All from 10.0.0.0/8 (cross-VPC)
  ingress {
    description = "All from RFC1918"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-branch2-vpc-sdwan-private-sg"
  }
}

# -----------------------------------------------------------------------------
# Security Groups - nv-sdwan-vpc
# -----------------------------------------------------------------------------

resource "aws_security_group" "nv_sdwan_public_sg" {
  provider    = aws.virginia
  name        = "nv-sdwan-vpc-sdwan-public-sg"
  description = "Public security group for SD-WAN instance - IKE, NAT-T, SSM"
  vpc_id      = module.nv_sdwan_vpc.vpc_id

  # IKE
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NAT-T
  ingress {
    description = "NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ESP (IPsec)
  ingress {
    description = "ESP"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSM from VPC CIDR
  ingress {
    description = "SSM HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.nv_sdwan_vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-sdwan-vpc-sdwan-public-sg"
  }
}

resource "aws_security_group" "nv_sdwan_private_sg" {
  provider    = aws.virginia
  name        = "nv-sdwan-vpc-sdwan-private-sg"
  description = "Private security group for SD-WAN instance - internal traffic"
  vpc_id      = module.nv_sdwan_vpc.vpc_id

  # All from VPC CIDR
  ingress {
    description = "All from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.nv_sdwan_vpc.vpc_cidr_block]
  }

  # All from 10.0.0.0/8 (cross-VPC)
  ingress {
    description = "All from RFC1918"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # BGP from Cloud WAN Connect Peer
  ingress {
    description = "BGP from Cloud WAN Connect Peer"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.cloudwan_connect_cidr_nv]
  }

  # All traffic from Cloud WAN Connect CIDR (health checks, etc.)
  ingress {
    description = "All from Cloud WAN Connect CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cloudwan_connect_cidr_nv]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nv-sdwan-vpc-sdwan-private-sg"
  }
}


# -----------------------------------------------------------------------------
# EC2 Instance, ENIs, and EIPs - nv-branch1-vpc
# -----------------------------------------------------------------------------

resource "aws_instance" "nv_branch1_sdwan_instance" {
  provider                    = aws.virginia
  ami                         = data.aws_ami.ubuntu_virginia.id
  instance_type               = var.sdwan_instance_type
  subnet_id                   = module.nv_branch1_vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.nv_branch1_public_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.sdwan_instance_profile.name
  source_dest_check           = false
  associate_public_ip_address = true

  tags = {
    Name = "nv-branch1-vpc-sdwan-instance"
  }
}

resource "aws_network_interface" "nv_branch1_sdwan_outside" {
  provider          = aws.virginia
  subnet_id         = module.nv_branch1_vpc.public_subnets[1]
  security_groups   = [aws_security_group.nv_branch1_public_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-branch1-vpc-sdwan-outside"
  }
}

resource "aws_network_interface" "nv_branch1_sdwan_internal" {
  provider          = aws.virginia
  subnet_id         = module.nv_branch1_vpc.private_subnets[0]
  security_groups   = [aws_security_group.nv_branch1_private_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-branch1-vpc-sdwan-internal"
  }
}

resource "aws_network_interface_attachment" "nv_branch1_sdwan_outside_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_branch1_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_branch1_sdwan_outside.id
  device_index         = 1
}

resource "aws_network_interface_attachment" "nv_branch1_sdwan_internal_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_branch1_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_branch1_sdwan_internal.id
  device_index         = 2
}

resource "aws_eip" "nv_branch1_sdwan_mgmt_eip" {
  provider          = aws.virginia
  network_interface = aws_instance.nv_branch1_sdwan_instance.primary_network_interface_id
  domain            = "vpc"

  tags = {
    Name = "nv-branch1-vpc-sdwan-mgmt-eip"
  }
}

resource "aws_eip" "nv_branch1_sdwan_outside_eip" {
  provider          = aws.virginia
  network_interface = aws_network_interface.nv_branch1_sdwan_outside.id
  domain            = "vpc"

  tags = {
    Name = "nv-branch1-vpc-sdwan-outside-eip"
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance, ENIs, and EIPs - nv-branch2-vpc
# -----------------------------------------------------------------------------

resource "aws_instance" "nv_branch2_sdwan_instance" {
  provider                    = aws.virginia
  ami                         = data.aws_ami.ubuntu_virginia.id
  instance_type               = var.sdwan_instance_type
  subnet_id                   = module.nv_branch2_vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.nv_branch2_public_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.sdwan_instance_profile.name
  source_dest_check           = false
  associate_public_ip_address = true

  tags = {
    Name = "nv-branch2-vpc-sdwan-instance"
  }
}

resource "aws_network_interface" "nv_branch2_sdwan_outside" {
  provider          = aws.virginia
  subnet_id         = module.nv_branch2_vpc.public_subnets[1]
  security_groups   = [aws_security_group.nv_branch2_public_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-branch2-vpc-sdwan-outside"
  }
}

resource "aws_network_interface" "nv_branch2_sdwan_internal" {
  provider          = aws.virginia
  subnet_id         = module.nv_branch2_vpc.private_subnets[0]
  security_groups   = [aws_security_group.nv_branch2_private_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-branch2-vpc-sdwan-internal"
  }
}

resource "aws_network_interface_attachment" "nv_branch2_sdwan_outside_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_branch2_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_branch2_sdwan_outside.id
  device_index         = 1
}

resource "aws_network_interface_attachment" "nv_branch2_sdwan_internal_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_branch2_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_branch2_sdwan_internal.id
  device_index         = 2
}

resource "aws_eip" "nv_branch2_sdwan_mgmt_eip" {
  provider          = aws.virginia
  network_interface = aws_instance.nv_branch2_sdwan_instance.primary_network_interface_id
  domain            = "vpc"

  tags = {
    Name = "nv-branch2-vpc-sdwan-mgmt-eip"
  }
}

resource "aws_eip" "nv_branch2_sdwan_outside_eip" {
  provider          = aws.virginia
  network_interface = aws_network_interface.nv_branch2_sdwan_outside.id
  domain            = "vpc"

  tags = {
    Name = "nv-branch2-vpc-sdwan-outside-eip"
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance, ENIs, and EIPs - nv-sdwan-vpc
# -----------------------------------------------------------------------------

resource "aws_instance" "nv_sdwan_sdwan_instance" {
  provider                    = aws.virginia
  ami                         = data.aws_ami.ubuntu_virginia.id
  instance_type               = var.sdwan_instance_type
  subnet_id                   = module.nv_sdwan_vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.nv_sdwan_public_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.sdwan_instance_profile.name
  source_dest_check           = false
  associate_public_ip_address = true

  tags = {
    Name = "nv-sdwan-vpc-sdwan-instance"
  }
}

resource "aws_network_interface" "nv_sdwan_sdwan_outside" {
  provider          = aws.virginia
  subnet_id         = module.nv_sdwan_vpc.public_subnets[1]
  security_groups   = [aws_security_group.nv_sdwan_public_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-sdwan-vpc-sdwan-outside"
  }
}

resource "aws_network_interface" "nv_sdwan_sdwan_internal" {
  provider          = aws.virginia
  subnet_id         = module.nv_sdwan_vpc.private_subnets[0]
  security_groups   = [aws_security_group.nv_sdwan_private_sg.id]
  source_dest_check = false

  tags = {
    Name = "nv-sdwan-vpc-sdwan-internal"
  }
}

resource "aws_network_interface_attachment" "nv_sdwan_sdwan_outside_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_sdwan_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_sdwan_sdwan_outside.id
  device_index         = 1
}

resource "aws_network_interface_attachment" "nv_sdwan_sdwan_internal_attach" {
  provider             = aws.virginia
  instance_id          = aws_instance.nv_sdwan_sdwan_instance.id
  network_interface_id = aws_network_interface.nv_sdwan_sdwan_internal.id
  device_index         = 2
}

resource "aws_eip" "nv_sdwan_sdwan_mgmt_eip" {
  provider          = aws.virginia
  network_interface = aws_instance.nv_sdwan_sdwan_instance.primary_network_interface_id
  domain            = "vpc"

  tags = {
    Name = "nv-sdwan-vpc-sdwan-mgmt-eip"
  }
}

resource "aws_eip" "nv_sdwan_sdwan_outside_eip" {
  provider          = aws.virginia
  network_interface = aws_network_interface.nv_sdwan_sdwan_outside.id
  domain            = "vpc"

  tags = {
    Name = "nv-sdwan-vpc-sdwan-outside-eip"
  }
}

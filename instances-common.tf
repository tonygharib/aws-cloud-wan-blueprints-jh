# Shared resources for SD-WAN Ubuntu instances
# IAM role, instance profile, and AMI data sources

# -----------------------------------------------------------------------------
# IAM Role and Instance Profile
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sdwan_instance_role" {
  provider = aws.frankfurt
  name     = "sdwan-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "sdwan-instance-role"
  }
}

resource "aws_iam_role_policy_attachment" "sdwan_ssm_policy" {
  provider   = aws.frankfurt
  role       = aws_iam_role.sdwan_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "sdwan_s3_policy" {
  provider = aws.frankfurt
  name     = "sdwan-s3-access"
  role     = aws_iam_role.sdwan_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.vyos_s3_bucket}"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.vyos_s3_bucket}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sdwan_instance_profile" {
  provider = aws.frankfurt
  name     = "sdwan-instance-profile"
  role     = aws_iam_role.sdwan_instance_role.name

  tags = {
    Name = "sdwan-instance-profile"
  }
}

# -----------------------------------------------------------------------------
# AMI Data Sources - Ubuntu 22.04 LTS
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu_frankfurt" {
  provider    = aws.frankfurt
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "ubuntu_virginia" {
  provider    = aws.virginia
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

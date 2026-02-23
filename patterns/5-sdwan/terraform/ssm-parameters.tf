# SSM Parameter Store - SD-WAN Instance Configuration
# Populates /sdwan/{instance-name}/{param-type} parameters for Lambda consumption
# us-east-1 instances use aws.virginia provider, eu-central-1 use aws.frankfurt

# -----------------------------------------------------------------------------
# nv-sdwan (us-east-1)
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "nv_sdwan_instance_id" {
  provider = aws.virginia
  name     = "/sdwan/nv-sdwan/instance-id"
  type     = "String"
  value    = aws_instance.nv_sdwan_sdwan_instance.id

  tags = {
    Name = "sdwan-nv-sdwan-instance-id"
  }
}

resource "aws_ssm_parameter" "nv_sdwan_outside_eip" {
  provider = aws.virginia
  name     = "/sdwan/nv-sdwan/outside-eip"
  type     = "String"
  value    = aws_eip.nv_sdwan_sdwan_outside_eip.public_ip

  tags = {
    Name = "sdwan-nv-sdwan-outside-eip"
  }
}

resource "aws_ssm_parameter" "nv_sdwan_outside_private_ip" {
  provider = aws.virginia
  name     = "/sdwan/nv-sdwan/outside-private-ip"
  type     = "String"
  value    = aws_network_interface.nv_sdwan_sdwan_outside.private_ip

  tags = {
    Name = "sdwan-nv-sdwan-outside-private-ip"
  }
}

# -----------------------------------------------------------------------------
# nv-branch1 (us-east-1)
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "nv_branch1_instance_id" {
  provider = aws.virginia
  name     = "/sdwan/nv-branch1/instance-id"
  type     = "String"
  value    = aws_instance.nv_branch1_sdwan_instance.id

  tags = {
    Name = "sdwan-nv-branch1-instance-id"
  }
}

resource "aws_ssm_parameter" "nv_branch1_outside_eip" {
  provider = aws.virginia
  name     = "/sdwan/nv-branch1/outside-eip"
  type     = "String"
  value    = aws_eip.nv_branch1_sdwan_outside_eip.public_ip

  tags = {
    Name = "sdwan-nv-branch1-outside-eip"
  }
}

resource "aws_ssm_parameter" "nv_branch1_outside_private_ip" {
  provider = aws.virginia
  name     = "/sdwan/nv-branch1/outside-private-ip"
  type     = "String"
  value    = aws_network_interface.nv_branch1_sdwan_outside.private_ip

  tags = {
    Name = "sdwan-nv-branch1-outside-private-ip"
  }
}

# -----------------------------------------------------------------------------
# fra-sdwan (eu-central-1)
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "fra_sdwan_instance_id" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-sdwan/instance-id"
  type     = "String"
  value    = aws_instance.fra_sdwan_sdwan_instance.id

  tags = {
    Name = "sdwan-fra-sdwan-instance-id"
  }
}

resource "aws_ssm_parameter" "fra_sdwan_outside_eip" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-sdwan/outside-eip"
  type     = "String"
  value    = aws_eip.fra_sdwan_sdwan_outside_eip.public_ip

  tags = {
    Name = "sdwan-fra-sdwan-outside-eip"
  }
}

resource "aws_ssm_parameter" "fra_sdwan_outside_private_ip" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-sdwan/outside-private-ip"
  type     = "String"
  value    = aws_network_interface.fra_sdwan_sdwan_outside.private_ip

  tags = {
    Name = "sdwan-fra-sdwan-outside-private-ip"
  }
}

# -----------------------------------------------------------------------------
# fra-branch1 (eu-central-1)
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "fra_branch1_instance_id" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-branch1/instance-id"
  type     = "String"
  value    = aws_instance.fra_branch1_sdwan_instance.id

  tags = {
    Name = "sdwan-fra-branch1-instance-id"
  }
}

resource "aws_ssm_parameter" "fra_branch1_outside_eip" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-branch1/outside-eip"
  type     = "String"
  value    = aws_eip.fra_branch1_sdwan_outside_eip.public_ip

  tags = {
    Name = "sdwan-fra-branch1-outside-eip"
  }
}

resource "aws_ssm_parameter" "fra_branch1_outside_private_ip" {
  provider = aws.frankfurt
  name     = "/sdwan/fra-branch1/outside-private-ip"
  type     = "String"
  value    = aws_network_interface.fra_branch1_sdwan_outside.private_ip

  tags = {
    Name = "sdwan-fra-branch1-outside-private-ip"
  }
}

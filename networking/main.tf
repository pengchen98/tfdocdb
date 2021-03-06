#-- networking/main.tf ---
data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { 
    name = format("%s_vpc", var.project_name)
    project_name = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = { 
    name = format("%s_igw", var.project_name)
    project_name = var.project_name
  }
}

resource "aws_subnet" "subpub" {
  count                   = length(var.subpub_cidrs)

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subpub_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  
  tags = { 
    name = format("%s_subpub_%d", var.project_name, count.index + 1)
    project_name = var.project_name
  }
}

resource "aws_subnet" "subprv" {
  count                   = length(var.subprv_cidrs)

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subprv_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = { 
    name = format("%s_subprv_%d", var.project_name, count.index + 1)
    project_name = var.project_name
  }
}

# Public route table, allows all outgoing traffic to go the the internet gateway.
# https://www.terraform.io/docs/providers/aws/r/route_table.html?source=post_page-----1a7fb9a336e9----------------------
resource "aws_route_table" "rtpub" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
  tags = {
    name = format("%s_rtpub", var.project_name)
    project_name = var.project_name
  }
}
# connect every public subnet with our public route table
resource "aws_route_table_association" "rtpubassoc" {
  count = length(var.subpub_cidrs)

  subnet_id      = "${aws_subnet.subpub.*.id[count.index]}"
  route_table_id = "${aws_route_table.rtpub.id}"
}

# If the subnet is not associated with any route by default it will be 
# associated automatically with this Private Route table.
# That's why we don't need an aws_route_table_association for private route tables.
# When Terraform first adopts the Default Route Table, it immediately removes all defined routes. 
# It then proceeds to create any routes specified in the configuration. 
# This step is required so that only the routes specified in the configuration present in the 
# Default Route Table.
# https://www.terraform.io/docs/providers/aws/r/default_route_table.html
resource "aws_default_route_table" "rtprv" {
  default_route_table_id = "${aws_vpc.vpc.default_route_table_id}"
  tags = {
    name = format("%s_rtprv", var.project_name)
    project_name = var.project_name
  }
}

resource "aws_security_group" "sgbastion" {
  name        = "sgbastion"
  description = "Used for access to the public instances"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = [ for s in var.bastion_ports: {
      from_port = s.from_port
      to_port = s.to_port
    }]
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value.to_port == 27017 ? "0.1.2.3/32" : var.access_ip]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { 
    name = format("%s_sgbastion", var.project_name)
    project_name = var.project_name
  }
}
resource "aws_security_group" "sgdocdb" {
  name        = "sgdocdb"
  description = "Used to allow access into docdb"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = [ for s in var.docdb_ports: {
      from_port = s.from_port
      to_port = s.to_port
    }]
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = "tcp"
      cidr_blocks = [var.access_ip]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { 
    name = format("%s_sgdocdb", var.project_name)
    project_name = var.project_name
  }
}

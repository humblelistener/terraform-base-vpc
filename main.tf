provider "aws" {
  region = "${var.aws_region}"
}

##############################################################################
# VPC configuration
##############################################################################
resource "aws_vpc" "default" {
  cidr_block = "${var.vpc_cidr}"
  instance_tenancy = "default"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"

  tags {
    Name = "${var.vpc_name}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "${var.vpc_name} internet gateway"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_dhcp_options" "default" {
  domain_name = "${var.aws_region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags {
    Name = "${var.vpc_name}"
  }
}

resource "aws_vpc_dhcp_options_association" "default" {
  vpc_id = "${aws_vpc.default.id}"
  dhcp_options_id = "${aws_vpc_dhcp_options.default.id}"
}

##############################################################################
# VPC Peering
##############################################################################

resource "aws_vpc_peering_connection" "vpc_to_parent" {
  peer_owner_id = "${var.aws_peer_owner_id}"
  peer_vpc_id = "${var.aws_parent_vpc_id}"
  vpc_id = "${aws_vpc.default.id}"
  auto_accept = true

  tags {
    Name = "${var.vpc_name}-parent-peering"
    stream = "${var.stream_tag}"
  }
}

##############################################################################
# Public Subnets
##############################################################################

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Name = "${var.vpc_name}-public"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.default.id}"
  cidr_block        = "${element(split(",", var.public_subnets_cidr), count.index)}"
  availability_zone = "${element(split(",", var.availability_zones), count.index)}"
  count             = "${length(split(",", var.public_subnets_cidr))}"

  map_public_ip_on_launch = true

  tags {
    Name = "${var.vpc_name}-${format("public-%02d", count.index+1)}"
  }
}

resource "aws_route_table_association" "public" {
  count          = "${length(split(",", var.public_subnets_cidr))}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

##############################################################################
# NAT Gateways for routing
##############################################################################

resource "aws_nat_gateway" "default" {
  count         = "${length(split(",", var.private_subnets_cidr))}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"

  depends_on    = ["aws_internet_gateway.default"]
}

resource "aws_eip" "nat" {
  count = "${length(split(",", var.private_subnets_cidr))}"
  vpc   = true
}

##############################################################################
# Private subnets
##############################################################################

resource "aws_route_table" "private" {
  count  = "${length(split(",", var.private_subnets_cidr))}"
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.default.*.id, count.index)}"
  }

  tags {
    Name = "${var.vpc_name}-${format("private-%02d", count.index+1)}"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.default.id}"
  cidr_block        = "${element(split(",", var.private_subnets_cidr), count.index)}"
  availability_zone = "${element(split(",", var.availability_zones), count.index)}"
  count             = "${length(split(",", var.private_subnets_cidr))}"

  tags {
    Name = "${var.vpc_name}-${format("private-%02d", count.index+1)}"
  }
}

resource "aws_route_table_association" "private" {
  count          = "${length(split(",", var.private_subnets_cidr))}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

##############################################################################
# Route 53
##############################################################################

resource "aws_route53_zone" "private_zone" {
  name = "${var.private_hosted_zone_name}"
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "Private zone ${var.private_hosted_zone_name}"
    stream = "${var.stream_tag}"
  }
}

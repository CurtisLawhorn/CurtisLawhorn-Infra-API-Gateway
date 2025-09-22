###############################################
# Networking setup for running private App Runners publicly via REST API Gateways via custom domain
###############################################

provider "aws" {
    profile = var.aws_profile
    region  = var.aws_region
}

data "aws_availability_zones" "available" {}

# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support    = false
  enable_dns_hostnames  = false
  tags = {
    Name    = var.vpc_name
    AppName = var.application_name
  }
}

# Security group
resource "aws_default_security_group" "my_vpc_sg" {
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Allow all traffic from VPC CIDR"
  }
  #ingress { # Allow inbound traffic from private subnets
  #  from_port   = 0
  #  to_port     = 0
  #  protocol    = "-1"
  #  cidr_blocks = var.private_subnet_cidr_blocks
  #  description = "Allow traffic from private subnets"
  #}
  egress { # Allow all outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name    = var.security_group_name
    AppName = var.application_name
  }
}

# Subnets
resource "aws_subnet" "my_vpc_public_subnet" {
  count             = 2
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = element(var.public_subnet_cidr_blocks, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name    = var.public_subnet_names[count.index]
    AppName = var.application_name
  }
}

resource "aws_subnet" "my_vpc_private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = element(var.private_subnet_cidr_blocks, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name    = var.private_subnet_names[count.index]
    AppName = var.application_name
  }
}

# VPC endpoint
resource "aws_vpc_endpoint" "my_vpc_endpoint" {
  vpc_id              = aws_vpc.my_vpc.id
  service_name        = "com.amazonaws.us-east-2.apprunner.requests"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.my_vpc_private_subnet[*].id
  security_group_ids  = [aws_default_security_group.my_vpc_sg.id]
  private_dns_enabled = false
  tags = {
    Name    = var.vpc_endpoint_name
    AppName = var.application_name
  }
}

data "aws_network_interface" "my_ec2_eni" {
  count = length(tolist(aws_vpc_endpoint.my_vpc_endpoint.network_interface_ids))
  id    = tolist(aws_vpc_endpoint.my_vpc_endpoint.network_interface_ids)[count.index]
}

output "my_vpc_endpoint_ips" {
  value = [
    for idx in range(length(aws_vpc_endpoint.my_vpc_endpoint.network_interface_ids)) :
    data.aws_network_interface.my_ec2_eni[idx].private_ip
  ]
}

# Network load Balancer
resource "aws_lb" "my_ec2_nlb" {
  name                = var.nlb_name
  internal            = true
  load_balancer_type  = "network"
  ip_address_type     = "ipv4"
  subnets             = aws_subnet.my_vpc_private_subnet[*].id
  enable_deletion_protection = false
  tags = {
    Name    = var.nlb_name
    AppName = var.application_name
  }
}

# Target Group
resource "aws_lb_target_group" "my_ec2_tg" {
  name        = var.target_group_name
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.my_vpc.id
  ip_address_type = "ipv4"
  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
  tags = {
    Name    = var.target_group_name
    AppName = var.application_name
  }
}

# Network load Balancer - Listener
resource "aws_lb_listener" "my_ec2_nlb_listener" {
  load_balancer_arn   = aws_lb.my_ec2_nlb.arn
  port                = 443
  protocol            = "TCP"
  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.my_ec2_tg.arn
  }
}

# Network load Balancer - Targets
resource "aws_lb_target_group_attachment" "my_ec2_tg_ips" {
  for_each         = { for idx, my_ec2_eni in data.aws_network_interface.my_ec2_eni : idx => my_ec2_eni }
  target_id        = each.value.private_ip
  target_group_arn = aws_lb_target_group.my_ec2_tg.arn
  port             = 443
}

# Custom domain
resource "aws_api_gateway_domain_name" "my_api_custom_domain" {
  domain_name              = var.domain_name
  regional_certificate_arn = var.domain_certificate_arn
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_vpc_link" "my_api_vpc_link" {
  name        = var.vpc_link_name
  target_arns = [aws_lb.my_ec2_nlb.arn]
}

# App Runner VPC connector
resource "aws_apprunner_vpc_connector" "my_apprunner_vpc_connector" {
  vpc_connector_name = var.app_runner_vpc_connector_name
  subnets            = aws_subnet.my_vpc_private_subnet[*].id
  security_groups    = [aws_default_security_group.my_vpc_sg.id]
  tags = {
    Name    = var.app_runner_vpc_connector_name
    AppName = var.application_name
  }
}

# Networking setup for running private App Runners publicly via REST API Gateways via custom domain

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

###############################################

# API Gateway
resource "aws_api_gateway_rest_api" "my_api" {
  name = var.api_gateway_name
}

# API gateway proxy resource
resource "aws_api_gateway_resource" "my_api_resource" { # Create the {proxy+} resource under the root resource
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "{proxy+}"
}

# API gateway proxy method
resource "aws_api_gateway_method" "my_api_method" { # Create the ANY method for the {proxy+} resource
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.my_api_resource.id
  http_method   = "ANY"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

###############################################

# App Runner
resource "aws_apprunner_service" "my_apprunner" {
  service_name = var.app_runner_name
  source_configuration {
    image_repository {
      image_identifier      = var.app_runner_image_arn
      image_repository_type = "ECR"
      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          ASPNETCORE_ENVIRONMENT                          = "Production"
          AWS__CognitoConfiguration__UserPoolId           = var.app_runner_cognito_userpoolid
          AWS__ApiDataStreamingConfiguration__StreamName  = var.app_runner_datastream_name
          Logging__LogLevel__Default                      = "Information"
          "Logging__LogLevel__Microsoft.AspNetCore"       = "Warning"
        }
        runtime_environment_secrets = {}
      }
    }
    auto_deployments_enabled = true
    authentication_configuration {
      access_role_arn = var.app_runner_access_role_arn
    }
  }
  instance_configuration {
    cpu               = "1024"
    memory            = "2048"
    instance_role_arn = var.app_runner_instance_role_arn
  }
  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }
  auto_scaling_configuration_arn = "arn:aws:apprunner:us-east-2:689502032294:autoscalingconfiguration/DefaultConfiguration/1/00000000000000000000000000000001"
  network_configuration {
    egress_configuration {
      egress_type       = "DEFAULT"
    }
    ingress_configuration {
      is_publicly_accessible = false
    }
    ip_address_type = "IPV4"
  }
  observability_configuration {
    observability_enabled           = true
    observability_configuration_arn = "arn:aws:apprunner:us-east-2:689502032294:observabilityconfiguration/DefaultConfiguration/1/00000000000000000000000000000001"
  }
  tags = {
    Name    = var.app_runner_name
    AppName = var.application_name
  }
}

resource "aws_apprunner_vpc_ingress_connection" "my_apprunner_ingress" {
  name        = var.app_runner_ingress_name
  service_arn = aws_apprunner_service.my_apprunner.arn
  ingress_vpc_configuration {
    vpc_id          = aws_vpc.my_vpc.id
    vpc_endpoint_id = aws_vpc_endpoint.my_vpc_endpoint.id
  }
  tags = {
    Name    = var.app_runner_ingress_name
    AppName = var.application_name
  }
}

resource "aws_api_gateway_integration" "my_api_integration" { # Integrate the ANY method with your VPC Link/NLB
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.my_api_resource.id
  http_method             = aws_api_gateway_method.my_api_method.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://${aws_apprunner_service.my_apprunner.service_url}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.my_api_vpc_link.id
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_method_response" "my_api_method_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.my_api_resource.id
  http_method = aws_api_gateway_method.my_api_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "my_api_deployment" { # Deploy the API
  depends_on  = [aws_api_gateway_integration.my_api_integration]
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  triggers    = { # Force a new deployment when any of these hashes change
    redeploy_hash = sha1(jsonencode([
      aws_api_gateway_method.my_api_method.id,
      aws_api_gateway_integration.my_api_integration.id,
      aws_api_gateway_method_response.my_api_method_response.id
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "my_api_stage" {
  stage_name    = "active"
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  deployment_id = aws_api_gateway_deployment.my_api_deployment.id
  #cache_cluster_enabled = true
  #cache_cluster_size    = "0.5"
}

# Custom domain API gateway mapping
resource "aws_api_gateway_base_path_mapping" "my_api_mapping" {
  api_id      = aws_api_gateway_rest_api.my_api.id
  stage_name  = aws_api_gateway_stage.my_api_stage.stage_name
  domain_name = aws_api_gateway_domain_name.my_api_custom_domain.domain_name
  base_path   = var.api_gateway_app_runner_base_path
}

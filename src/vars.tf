###############################################
# Environment
###############################################

variable "project_name" {
  type    = string
  default = "Curtis Lawhorn"
}

###############################################
# Networking
###############################################

# VPC
variable "vpc_name" {
  type    = string
  default = "curtislawhorn-apprunner-vpc"
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

# Security group
variable "security_group_name" {
  type    = string
  default = "curtislawhorn-apprunner-vpc-sg"
}

# Subnets
variable "public_subnet_names" {
  type    = list(string)
  default = ["curtislawhorn-apprunner-public-snet-1", "curtislawhorn-apprunner-public-snet-2"]
}

variable "public_subnet_cidr_blocks" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_subnet_names" {
  type    = list(string)
  default = ["curtislawhorn-apprunner-private-snet-1", "curtislawhorn-apprunner-private-snet-2"]
}

variable "private_subnet_cidr_blocks" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}

# VPC endpoint
variable "vpc_endpoint_name" {
  type    = string
  default = "curtislawhorn-apprunner-vpce"
}

# Network load balancer
variable "nlb_name" {
  type    = string
  default = "curtislawhorn-apprunner-nlb"
}

# Target group
variable "target_group_name" {
  type    = string
  default = "curtislawhorn-apprunner-vpc-tg"
}

# API gateway
variable "domain_name" {
  type    = string
  default = "api.curtislawhorn.com"
}

variable "domain_certificate_arn" {
  type    = string
  default = "arn:aws:acm:us-east-2:689502032294:certificate/dec1fca0-a71c-41a8-b714-6f90bf81f9f9"
}

variable "vpc_link_name" {
  type    = string
  default = "curtislawhorn-apprunner-vpc-link"
}

variable "app_runner_vpc_connector_name" {
  type    = string
  default = "curtislawhorn-apprunner-connector"
}

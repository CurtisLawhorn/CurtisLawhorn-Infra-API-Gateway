terraform {
  backend "s3" {
    region         = "us-east-2"
    bucket         = "curtislawhorn-terraform-states"
    key            = "prod/api-gateway/terraform.tfstate"
    dynamodb_table = "curtislawhorn-terraform-locks"
    encrypt        = true
  }
}

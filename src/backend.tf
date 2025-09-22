terraform {
  backend "s3" {
    region         = "us-east-2"
    bucket         = "curtislawhorn-terraform-states"
    key            = "network/terraform.tfstate"
    dynamodb_table = "curtislawhorn-terraform-locks"
    encrypt        = true
  }
}

# For production, uncomment the S3 backend below and run `terraform init -migrate-state`
# terraform {
#   backend "s3" {
#     bucket         = "rosa-terraform-state"
#     key            = "rosa-hcp/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "rosa-terraform-locks"
#     encrypt        = true
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

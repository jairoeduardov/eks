# Backend parcial: los valores concretos (bucket, tabla de lock, cuenta) salen
# de los outputs de ../bootstrap y se pasan en init. Ver README para el comando exacto:
#
#   terraform init \
#     -backend-config="bucket=<state_bucket de bootstrap>" \
#     -backend-config="dynamodb_table=<lock_table de bootstrap>" \
#     -backend-config="region=us-east-1"

terraform {
  backend "s3" {
    key     = "eks-lab/terraform.tfstate"
    encrypt = true
  }
}

# State lives in Azure Storage. Values come from backend.hcl:
#   terraform init -backend-config=backend.hcl
# Run scripts/bootstrap-state.sh once to create the storage account and
# generate backend.hcl.
terraform {
  backend "azurerm" {}
}

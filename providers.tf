# Authentication comes from the environment: Azure CLI locally, the ARM_*
# variables exported by the pipeline's AzureCLI task in CI.
provider "azurerm" {
  features {}
}

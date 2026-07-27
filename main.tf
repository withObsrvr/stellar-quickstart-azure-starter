module "stellar_quickstart" {
  source = "git::https://github.com/withobsrvr/terraform-azure-stellar-quickstart.git?ref=v0.1.0"

  location            = var.location
  environment         = var.environment
  project_name        = var.project_name
  resource_group_name = var.resource_group_name

  network_access     = var.network_access
  enable_vpn_gateway = var.enable_vpn_gateway

  stellar_network  = var.stellar_network
  container_cpu    = var.container_cpu
  container_memory = var.container_memory

  tags = var.tags
}

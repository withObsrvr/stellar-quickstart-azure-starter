module "stellar_quickstart" {
  source = "git::https://github.com/withobsrvr/terraform-azure-stellar-quickstart.git?ref=v0.1.3"

  location            = var.location
  environment         = var.environment
  project_name        = var.project_name
  resource_group_name = var.resource_group_name

  network_access     = var.network_access
  dns_name_label     = var.dns_name_label
  enable_vpn_gateway = var.enable_vpn_gateway

  vnet_cidr                 = var.vnet_cidr
  aci_subnet_cidr           = var.aci_subnet_cidr
  gateway_subnet_cidr       = var.gateway_subnet_cidr
  vpn_client_address_pool   = var.vpn_client_address_pool
  vpn_authentication_type   = var.vpn_authentication_type
  vpn_aad_audience          = var.vpn_aad_audience
  vpn_root_certificate_name = var.vpn_root_certificate_name
  vpn_root_certificate_data = var.vpn_root_certificate_data
  additional_allowed_cidrs  = var.additional_allowed_cidrs

  stellar_network  = var.stellar_network
  quickstart_image = var.quickstart_image
  container_cpu    = var.container_cpu
  container_memory = var.container_memory

  tags = var.tags
}

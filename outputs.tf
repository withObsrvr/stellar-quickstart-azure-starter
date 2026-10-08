output "stellar_endpoint" {
  description = "Endpoint for Horizon/RPC/Friendbot/Lab"
  value       = module.stellar_quickstart.stellar_endpoint
}

output "resource_group_name" {
  description = "Resource group containing the sandbox"
  value       = module.stellar_quickstart.resource_group_name
}

output "container_group_private_ip" {
  description = "Private IP (private mode); null in public mode"
  value       = module.stellar_quickstart.container_group_private_ip
}

output "container_group_public_fqdn" {
  description = "Public FQDN (public mode); null in private mode"
  value       = module.stellar_quickstart.container_group_public_fqdn
}

output "container_group_public_ip" {
  description = "Public IP (public mode); null in private mode"
  value       = module.stellar_quickstart.container_group_public_ip
}

output "vnet_id" {
  description = "VNet ID for peering consumer VNets; null in public mode"
  value       = module.stellar_quickstart.vnet_id
}

output "vnet_name" {
  description = "Sandbox VNet name; null in public mode"
  value       = module.stellar_quickstart.vnet_name
}

output "private_dns_zone_id" {
  description = "Private DNS zone ID for linking application VNets; null in public mode"
  value       = module.stellar_quickstart.private_dns_zone_id
}

output "vpn_gateway_name" {
  description = "VPN gateway name for client profile generation; null when VPN disabled"
  value       = module.stellar_quickstart.vpn_gateway_name
}

output "vpn_gateway_public_ip" {
  description = "Public IP of the VPN endpoint only; null when VPN is disabled"
  value       = module.stellar_quickstart.vpn_gateway_public_ip
}

variable "location" {
  description = "Azure region for the sandbox"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name used in resource naming and tags"
  type        = string
  default     = "sandbox"
}

variable "project_name" {
  description = "Project name used in resource naming and tags"
  type        = string
  default     = "stellar-quickstart"
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into; leave null to have one created"
  type        = string
  default     = null
}

variable "network_access" {
  description = "private (VNet, no public exposure) or public (demo-only, internet-open)"
  type        = string
  default     = "private"
}

variable "enable_vpn_gateway" {
  description = "Deploy a Point-to-Site VPN gateway for laptop access (private mode only; ~$190/month, 30-45 min to provision)"
  type        = bool
  default     = false
}

variable "stellar_network" {
  description = "local (ephemeral private network with Friendbot), testnet, or futurenet"
  type        = string
  default     = "local"
}

variable "container_cpu" {
  description = "vCPUs for the container group (use 4 for testnet/futurenet)"
  type        = number
  default     = 2
}

variable "container_memory" {
  description = "Memory in GB for the container group (use 16 for testnet/futurenet)"
  type        = number
  default     = 8
}

variable "tags" {
  description = "Additional tags merged onto all resources"
  type        = map(string)
  default     = {}
}

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

variable "dns_name_label" {
  description = "Globally unique regional DNS label for public mode; defaults to {project_name}-{environment}"
  type        = string
  default     = null
}

variable "enable_vpn_gateway" {
  description = "Deploy a Point-to-Site VPN gateway for laptop access (private mode only; ~$190/month, 30-45 min to provision)"
  type        = bool
  default     = false
}

variable "vnet_cidr" {
  description = "Address space for the sandbox VNet; choose a range that does not overlap connected networks"
  type        = string
  default     = "10.10.0.0/16"
}

variable "aci_subnet_cidr" {
  description = "Subnet delegated to Azure Container Instances"
  type        = string
  default     = "10.10.1.0/24"
}

variable "gateway_subnet_cidr" {
  description = "GatewaySubnet address prefix used when the VPN gateway is enabled"
  type        = string
  default     = "10.10.255.0/27"
}

variable "vpn_client_address_pool" {
  description = "Addresses assigned to Point-to-Site VPN clients; must not overlap the VNet or connected networks"
  type        = string
  default     = "172.16.201.0/24"
}

variable "vpn_authentication_type" {
  description = "P2S authentication mode: entra for Windows/macOS Azure VPN Client, or certificate for standard OpenVPN clients including Linux"
  type        = string
  default     = "entra"

  validation {
    condition     = contains(["entra", "certificate"], var.vpn_authentication_type)
    error_message = "vpn_authentication_type must be \"entra\" or \"certificate\"."
  }
}

variable "vpn_aad_audience" {
  description = "Audience application ID accepted by the P2S VPN; defaults to Microsoft's current registered Azure VPN Client"
  type        = string
  default     = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
}

variable "vpn_root_certificate_name" {
  description = "Name of the trusted root certificate uploaded in certificate mode"
  type        = string
  default     = "stellar-p2s-root"
}

variable "vpn_root_certificate_data" {
  description = "Base64-encoded DER public root certificate required in certificate mode; never provide the CA private key"
  type        = string
  default     = null
}

variable "additional_allowed_cidrs" {
  description = "Additional internal CIDRs allowed to reach port 8000, such as peered application VNets"
  type        = list(string)
  default     = []
}

variable "stellar_network" {
  description = "local (ephemeral private network with Friendbot), testnet, or futurenet"
  type        = string
  default     = "local"
}

variable "quickstart_image" {
  description = "Stellar Quickstart container image; override with an ACR mirror to avoid public-registry pull limits"
  type        = string
  default     = "stellar/quickstart:latest"
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

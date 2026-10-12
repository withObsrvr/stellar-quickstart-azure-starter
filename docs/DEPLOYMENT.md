# Deployment runbook

This runbook takes a new Azure environment from an empty workstation to a
working Stellar Quickstart network. It covers two deployment shapes:

- **Public demo:** fast to create and easy to demonstrate, but Horizon, RPC,
  Lab, and Friendbot are exposed without authentication. Destroy it promptly.
- **Internal only:** the default. The container receives only a private IP.
  Applications reach it through the sandbox VNet or VNet peering; developers
  can optionally use a Point-to-Site (P2S) VPN.

Both shapes use a `local` Stellar network. It starts from genesis and includes
Friendbot. Its data is ephemeral: a container restart resets the network, so
seed test accounts after every deployment or restart.

## 1. Prerequisites

Install:

- Terraform 1.5 or newer
- Azure CLI
- Python 3 and `pip` (only required for account seeding)

Sign in and select the intended subscription:

```bash
az login
az account set --subscription "<subscription name or ID>"
az account show --query '{name:name,id:id,tenantId:tenantId}' -o table
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

The signed-in identity needs permission to create the deployment resources.
Bootstrapping state also creates a role assignment, which requires Owner or
User Access Administrator at the relevant scope.

## 2. Bootstrap Terraform state

From the repository root:

```bash
./scripts/bootstrap-state.sh \
  eastus \
  rg-stellar-tfstate \
  ststellaryouruniqueid \
  tfstate
```

On Windows PowerShell, use:

~~~powershell
.\scripts\bootstrap-state.ps1 -Location eastus -StateResourceGroup rg-stellar-tfstate -StorageAccount ststellaryouruniqueid -Container tfstate
~~~

Azure Storage account names are globally unique, lowercase, and 3–24
alphanumeric characters. The script creates the resource group, account, blob
container, and your data-plane role assignment, then writes `backend.hcl`.
Commit `backend.hcl`; it contains resource names but no credentials.

Copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is intentionally ignored so each environment can have local
values. In an automated environment, use a reviewed `.auto.tfvars` strategy or
pipeline variables appropriate to your organization.

## 3A. Short-lived public demo

Use a unique DNS label in `terraform.tfvars`:

```hcl
location           = "eastus"
environment        = "demo"
network_access     = "public"
dns_name_label     = "stellar-demo-youruniqueid"
enable_vpn_gateway = false
stellar_network    = "local"

container_cpu    = 2
container_memory = 8

tags = {
  purpose    = "stellar-demo"
  expires_on = "YYYY-MM-DD"
}
```

Deploy:

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Continue at [Verify and seed](#4-verify-and-seed).

## 3B. Internal-only deployment

### Choose the access path

Choose one or both:

1. **Application access through VNet peering.** This is the normal path for
   services already running in Azure. Peer the application VNet with the
   sandbox VNet, allow the application CIDR, and link the private DNS zone.
2. **Developer access through P2S VPN.** This provides laptop access but adds a
   VPN gateway, cost, tenant setup, and approximately 30–45 minutes of initial
   provisioning.

Choose the authentication path based on the developer platform:

- Windows/macOS: use Entra authentication and follow
  [PRIVATE_RELEASE_WINDOWS_MACOS.md](PRIVATE_RELEASE_WINDOWS_MACOS.md).
- NixOS/Linux: use certificate authentication and follow
  [NIXOS_PRIVATE_ACCESS.md](NIXOS_PRIVATE_ACCESS.md).

If neither is enabled, the network is still deployable and manageable through
Azure. The seeding script can use `az container exec`, but a laptop cannot call
Horizon or RPC directly.

### Plan non-overlapping addresses

Coordinate these ranges with the organization's network owner before applying.
The VNet, peered VNets, on-premises networks, and VPN client pool must not
overlap.

Example `terraform.tfvars`:

```hcl
location           = "eastus"
environment        = "internal"
network_access     = "private"
enable_vpn_gateway = true # false when only Azure workloads need access
stellar_network    = "local"

vnet_cidr               = "10.10.0.0/16"
aci_subnet_cidr         = "10.10.1.0/24"
gateway_subnet_cidr     = "10.10.255.0/27"
vpn_client_address_pool = "172.16.201.0/24"
vpn_aad_audience         = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"

# Add every peered application/hub CIDR that should reach TCP 8000.
additional_allowed_cidrs = ["10.20.0.0/16"]

container_cpu    = 2
container_memory = 8
```

Deploy using the same Terraform sequence:

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Confirm that the container has no public address:

```bash
terraform output container_group_private_ip
terraform output container_group_public_ip
```

The second output should be `null`.

### Application access with VNet peering

The module returns the sandbox VNet and private DNS zone IDs:

```bash
terraform output -raw vnet_id
terraform output -raw private_dns_zone_id
```

Create bidirectional peering between the sandbox and application VNets using
your organization's hub-and-spoke or direct-peering standard. On the sandbox
side, a direct peering can be created with:

```bash
RG="$(terraform output -raw resource_group_name)"
SANDBOX_VNET="$(terraform output -raw vnet_name)"
APP_VNET_ID="<application-vnet-resource-id>"

az network vnet peering create \
  --name sandbox-to-app \
  --resource-group "$RG" \
  --vnet-name "$SANDBOX_VNET" \
  --remote-vnet "$APP_VNET_ID" \
  --allow-vnet-access
```

Create the reverse peering in the application VNet's resource group. Exact
gateway-transit flags depend on the organization's network topology; do not
enable them by assumption.

The Terraform `additional_allowed_cidrs` list must contain the application
VNet CIDR. Also link the module-created private DNS zone to the application
VNet so it can resolve `quickstart.stellar.internal`:

```bash
ZONE_ID="$(terraform output -raw private_dns_zone_id)"
ZONE_NAME="$(basename "$ZONE_ID")"
APP_VNET_ID="<application-vnet-resource-id>"

az network private-dns link vnet create \
  --name stellar-from-app \
  --resource-group "$RG" \
  --zone-name "$ZONE_NAME" \
  --virtual-network "$APP_VNET_ID" \
  --registration-enabled false
```

Run the health checks in section 4 from a VM, container, or build agent with
routing and DNS access to the application VNet.

### Developer access with P2S VPN

The default `vpn_aad_audience` uses Microsoft's current registered Azure VPN
Client application. It does not require tenant admin consent. The same VPN
profile can be distributed to multiple developers; each developer signs in
with an individual Entra identity and receives an address from
`vpn_client_address_pool`.

The default audience authenticates users at the tenant level. For a customer
deployment, prefer a custom Entra audience application with **Assignment
required** enabled and assign a dedicated group such as
`Stellar-Sandbox-Developers`. Set `vpn_aad_audience` to that custom
application's client ID. Group members must be direct members; nested groups
are not supported by this Azure VPN access pattern.

Azure VPN Client with Entra authentication is supported on Windows and macOS.
Microsoft retired its Linux Azure VPN Client on August 31, 2026. Linux
developers require a separate certificate- or RADIUS-based VPN configuration,
which this module does not currently create.

For the identity setup, follow Microsoft's [assigned-user/group access
guide](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-users-access).
For supported clients and audience values, see the [P2S Entra configuration
guide](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-gateway).

After the gateway finishes provisioning:

```bash
RG="$(terraform output -raw resource_group_name)"
GW="$(terraform output -raw vpn_gateway_name)"
az network vnet-gateway show -g "$RG" -n "$GW" \
  --query '{name:name,state:provisioningState,ip:ipConfigurations[0].privateIPAddress}' \
  -o table
```

In the Azure portal, open the virtual network gateway, choose **Point-to-site
configuration**, download the VPN client, and import its Azure VPN Client
profile. Sign in with the consented tenant account and connect.

P2S clients cannot use Azure's VNet resolver through this tunnel by default.
For a quick test, use `container_group_private_ip` directly. For durable DNS,
deploy an Azure Private DNS Resolver inbound endpoint and configure the VPN
client profile/enterprise DNS architecture accordingly.

## 4. Verify and seed

Get the complete base URL (it already includes `http://` and port `8000`):

```bash
export STELLAR_ENDPOINT="$(terraform output -raw stellar_endpoint)"
echo "$STELLAR_ENDPOINT"
curl --fail --retry 30 --retry-delay 10 "$STELLAR_ENDPOINT"
```

For P2S without private DNS, substitute the private IP:

```bash
export STELLAR_ENDPOINT="http://$(terraform output -raw container_group_private_ip):8000"
```

Install the seed-script dependency in a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
```

When the endpoint is reachable directly:

```bash
python3 scripts/seed_accounts.py --count 5 --endpoint "$STELLAR_ENDPOINT"
```

For private mode from a workstation or hosted agent with no network route,
seed through the Azure control plane:

```bash
RG="$(terraform output -raw resource_group_name)"
CG="$(az container list -g "$RG" --query '[0].name' -o tsv)"
python3 scripts/seed_accounts.py --count 5 --via-exec "$RG" "$CG"
```

`seed-accounts.json` contains secret keys and is ignored by Git. Verify an
account through Horizon:

```bash
PUBLIC_KEY="$(python3 -c 'import json; print(json.load(open("seed-accounts.json"))["accounts"][0]["public_key"])')"
curl "$STELLAR_ENDPOINT/accounts/$PUBLIC_KEY"
```

Application settings for the local network are:

| Setting | Value |
|---|---|
| Horizon | `<stellar_endpoint>` |
| RPC | `<stellar_endpoint>/rpc` |
| Friendbot | `<stellar_endpoint>/friendbot` |
| Network passphrase | `Standalone Network ; February 2017` |

See [CONNECTING.md](CONNECTING.md) for SDK examples.

## 5. Cleanup

For a temporary deployment:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

This does not remove the separately bootstrapped state backend. Delete that
resource group only when no environment still uses its state:

```bash
az group delete --name rg-stellar-tfstate
```

## Troubleshooting

- **Public DNS label unavailable:** choose another `dns_name_label` and apply.
- **Docker Hub `409 RegistryErrorResponse`:** rerun `terraform apply`; anonymous
  image pulls can be throttled temporarily.
- **Private endpoint times out:** confirm routing/peering, ensure the caller's
  CIDR is in `additional_allowed_cidrs`, and test the private IP before DNS.
- **Private name does not resolve:** link the private DNS zone to the caller's
  VNet. P2S laptops require the DNS-resolver solution described above.
- **VPN creation is slow:** 30–45 minutes is normal for a new Azure VPN
  gateway.
- **Seed accounts disappeared:** the local Quickstart network restarted; run
  the seed script again.
- **Backend authorization fails just after bootstrap:** Azure role assignments
  can take several minutes to propagate; retry `terraform init`.

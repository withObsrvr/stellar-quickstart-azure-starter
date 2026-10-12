# Private release from Windows or macOS

This guide deploys Stellar Quickstart with no public container address and
connects developers through Azure Point-to-Site VPN. Microsoft Entra ID
authenticates each developer through Azure VPN Client.

## 1. Prerequisites

The deployment operator needs:

- Terraform 1.5 or newer
- Azure CLI
- An Azure subscription and permission to create the documented resources
- Owner or User Access Administrator when bootstrapping the state role

Each developer needs:

- Windows 11 or a currently supported macOS release
- Azure VPN Client
- An identity in the gateway's Microsoft Entra tenant

Sign in and select the subscription:

```bash
az login
az account set --subscription "<subscription name or ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

On Windows PowerShell, use the equivalent environment syntax:

~~~powershell
az login
az account set --subscription "<subscription name or ID>"
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv
~~~

## 2. Bootstrap state

From the starter repository on Windows PowerShell:

~~~powershell
.\scripts\bootstrap-state.ps1 -Location eastus -StateResourceGroup rg-stellar-tfstate -StorageAccount ststellaryouruniqueid -Container tfstate
~~~

On macOS or another Bash environment:

```bash
./scripts/bootstrap-state.sh \
  eastus \
  rg-stellar-tfstate \
  ststellaryouruniqueid \
  tfstate
```

Review and commit the generated `backend.hcl`; it contains resource names, not
credentials. Commit `.terraform.lock.hcl` as well.

## 3. Configure private Entra access

Create `terraform.tfvars`:

```hcl
location                = "eastus"
environment             = "internal"
network_access          = "private"
enable_vpn_gateway      = true
vpn_authentication_type = "entra"
vpn_aad_audience        = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"

vnet_cidr               = "10.10.0.0/16"
aci_subnet_cidr         = "10.10.1.0/24"
gateway_subnet_cidr     = "10.10.255.0/27"
vpn_client_address_pool = "172.16.201.0/24"

stellar_network  = "local"
container_cpu    = 2
container_memory = 8
```

Coordinate the address ranges with the network owner. They must not overlap
each other, users' local networks, connected corporate networks, or peered
VNets.

The Microsoft-registered audience shown above does not require the old tenant
admin-consent workflow. It authenticates at tenant scope. For a production
customer, use a custom Entra audience application with **Assignment required**
and assign a dedicated direct-membership group such as
`Stellar-Sandbox-Developers`; set `vpn_aad_audience` to that application's
client ID.

## 4. Plan and deploy

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Allow 30–45 minutes for a new gateway. Confirm private-only addressing:

```bash
terraform output container_group_private_ip
terraform output container_group_public_ip
terraform output vpn_gateway_name
```

`container_group_public_ip` must be `null`. The VPN gateway has a public IP as
its encrypted tunnel endpoint; the Stellar container does not.

## 5. Generate and distribute the client profile

In the Azure portal:

1. Open the deployed **Virtual network gateway**.
2. Open **Point-to-site configuration**.
3. Select **Download VPN client** and wait for profile generation.
4. Extract the zip and locate `AzureVPN/azurevpnconfig.xml`.
5. Distribute that profile through an approved internal channel.

The profile contains gateway connection settings, not a developer's password.
The same profile can be imported by multiple developers. Each person signs in
with an individual Entra identity and receives a distinct address from
`vpn_client_address_pool`.

Regenerate and redistribute the profile after changing gateway authentication
or tunnel settings.

## 6. Connect from Windows

1. Install the latest Azure VPN Client from Microsoft Store or with:
   `winget install Microsoft.AzureVPNClient --source winget`.
2. Open Azure VPN Client and select **Import**.
3. Import `azurevpnconfig.xml`.
4. Select the imported connection and **Connect**.
5. Complete the Entra sign-in and any required MFA.

## 7. Connect from macOS

1. Install Azure VPN Client from the Mac App Store.
2. Open it, select **Import**, and choose `azurevpnconfig.xml`.
3. Select the imported connection and connect.
4. Complete the Entra sign-in and any required MFA.

## 8. Verify Stellar privately

P2S clients do not automatically use the module's Azure Private DNS zone. For
the first test, use the private container IP:

```bash
PRIVATE_IP="$(terraform output -raw container_group_private_ip)"
export STELLAR_ENDPOINT="http://${PRIVATE_IP}:8000"

curl --fail --retry 30 --retry-delay 10 "$STELLAR_ENDPOINT"
curl "$STELLAR_ENDPOINT/rpc"
```

For durable hostname resolution, integrate Azure Private DNS Resolver with the
organization's DNS design.

Seed development accounts while connected:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python3 scripts/seed_accounts.py --count 5 --endpoint "$STELLAR_ENDPOINT"
```

## 9. Operate the release

- Add and remove developers through the assigned Entra group when using a
  custom audience application.
- Keep each developer on an individual identity; never share accounts.
- Re-seed after container restarts because the local Stellar network is
  ephemeral.
- Monitor VPN gateway cost and destroy temporary environments when finished.
- Keep the container private; only the VPN gateway should have a public IP.

See Microsoft's [P2S Entra gateway guide](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-gateway),
[Azure VPN Client guide](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-vpn-client-windows),
and [assigned-user/group access guide](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-users-access).

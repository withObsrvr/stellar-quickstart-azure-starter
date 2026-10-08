# Private P2S access from NixOS

Microsoft retired Azure VPN Client for Linux on August 31, 2026. Entra-based
P2S therefore isn't a supported NixOS path. This guide configures Azure VPN
Gateway for certificate authentication and connects with standard OpenVPN.

Each developer must receive a distinct client certificate. Never distribute
the root CA private key or commit any private key to Git.

## 1. Enter a tooling shell

From the starter repository:

```bash
nix shell nixpkgs#azure-cli nixpkgs#terraform nixpkgs#openssl \
  nixpkgs#openvpn nixpkgs#unzip

az login --use-device-code
az account set --subscription "<subscription name or ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

## 2. Create a private certificate authority

Create this outside the repository in a protected directory:

```bash
install -d -m 700 "$HOME/.local/share/stellar-p2s-ca"
cd "$HOME/.local/share/stellar-p2s-ca"

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout caKey.pem \
  -out caCert.pem \
  -subj "/CN=stellar-p2s-root"
chmod 600 caKey.pem

openssl x509 -in caCert.pem -outform der | base64 -w0 > caCert.base64
```

`caCert.base64` is public certificate material and is the only CA value given
to Terraform. `caKey.pem` is the authority that can create VPN identities;
protect and back it up according to the organization's certificate policy.

## 3. Configure the private deployment

In the repository's `terraform.tfvars`:

```hcl
location                = "eastus"
environment             = "internal"
network_access          = "private"
enable_vpn_gateway      = true
vpn_authentication_type = "certificate"

vnet_cidr               = "10.10.0.0/16"
aci_subnet_cidr         = "10.10.1.0/24"
gateway_subnet_cidr     = "10.10.255.0/27"
vpn_client_address_pool = "172.16.201.0/24"

vpn_root_certificate_name = "stellar-p2s-root"
vpn_root_certificate_data = "<contents of caCert.base64>"

stellar_network  = "local"
container_cpu    = 2
container_memory = 8
```

The VNet and VPN client ranges must not overlap each other, the developer's
local network, peered VNets, or on-premises networks.

Deploy from the repository root:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Allow 30–45 minutes for the initial VPN gateway creation.

## 4. Issue one developer certificate

Return to the protected CA directory and choose a unique developer name:

```bash
cd "$HOME/.local/share/stellar-p2s-ca"
DEV_NAME="yourname"

openssl genrsa -out "${DEV_NAME}Key.pem" 2048
openssl req -new \
  -key "${DEV_NAME}Key.pem" \
  -out "${DEV_NAME}Req.pem" \
  -subj "/CN=${DEV_NAME}"

openssl x509 -req -sha256 -days 365 \
  -in "${DEV_NAME}Req.pem" \
  -CA caCert.pem \
  -CAkey caKey.pem \
  -CAcreateserial \
  -out "${DEV_NAME}Cert.pem" \
  -extfile <(printf 'extendedKeyUsage=clientAuth\nsubjectAltName=DNS:%s\n' "$DEV_NAME")

chmod 600 "${DEV_NAME}Key.pem"
```

Repeat this step for every developer. Do not share a client certificate or
private key between people.

## 5. Download and prepare the OpenVPN profile

In the Azure portal:

1. Open the deployed **Virtual network gateway**.
2. Open **Point-to-site configuration**.
3. Select **Download VPN client** and wait for the zip package.
4. Extract the package and open `OpenVPN/vpnconfig.ovpn`.

Replace the placeholder contents between `<cert>` and `</cert>` with the
developer certificate from `${DEV_NAME}Cert.pem`. Replace the placeholder
between `<key>` and `</key>` with `${DEV_NAME}Key.pem`. Include the complete
`BEGIN` and `END` lines. Leave the server certificate and `tls-auth` sections
unchanged.

For OpenVPN 2.6, add this line to the profile if it is not already present:

```text
disable-dco
```

The completed profile contains a private key. Store it with mode `600`, never
commit it, and distribute profiles through an approved secret-delivery method.

## 6. Connect and verify

```bash
chmod 600 vpnconfig.ovpn
sudo openvpn --config vpnconfig.ovpn
```

Keep OpenVPN running. In another terminal:

```bash
cd /path/to/stellar-quickstart-azure-starter
PRIVATE_IP="$(terraform output -raw container_group_private_ip)"
export STELLAR_ENDPOINT="http://${PRIVATE_IP}:8000"

curl --fail --retry 30 --retry-delay 10 "$STELLAR_ENDPOINT"
curl "$STELLAR_ENDPOINT/rpc"
```

Use the private IP for this test. P2S clients do not automatically resolve the
module's Azure Private DNS zone. Production name resolution requires a DNS
forwarding design, typically Azure Private DNS Resolver.

Seed accounts while connected:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python3 scripts/seed_accounts.py --count 5 --endpoint "$STELLAR_ENDPOINT"
```

## 7. Add more developers

For each developer:

1. Issue a unique client certificate from the protected CA.
2. Give that developer a fresh copy of the gateway profile populated with only
   their certificate and private key.
3. Record the certificate identity and expiration in the organization's access
   inventory.
4. Revoke and replace the certificate immediately if its private key is lost.

Microsoft's reference procedures are [certificate-authenticated P2S gateway
configuration](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-certificate-gateway)
and [OpenVPN client configuration](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-vpn-client-certificate-openvpn-linux).

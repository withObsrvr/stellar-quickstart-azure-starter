#!/usr/bin/env bash
# One-time setup of the Azure Storage backend for Terraform state.
# Creates a resource group, storage account, and blob container, grants the
# signed-in user blob access, and writes backend.hcl for terraform init.
#
# Usage: ./scripts/bootstrap-state.sh [location] [state-rg] [storage-account] [container]
set -euo pipefail

LOCATION="${1:-eastus}"
STATE_RG="${2:-rg-tfstate}"
STORAGE_ACCOUNT="${3:-sttfstate$RANDOM$RANDOM}"
CONTAINER="${4:-tfstate}"

command -v az >/dev/null || { echo "ERROR: Azure CLI (az) is required" >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in — run 'az login' first" >&2; exit 1; }

echo "Subscription: $(az account show --query name -o tsv)"
echo "Creating state backend: $STATE_RG / $STORAGE_ACCOUNT / $CONTAINER in $LOCATION"

az group create --name "$STATE_RG" --location "$LOCATION" --output none

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

STORAGE_ID=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$STATE_RG" --query id -o tsv)

# Blob-level RBAC so use_azuread_auth works without storage keys.
USER_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee "$USER_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ID" \
  --output none

# Role assignment takes a moment to propagate before container create succeeds.
for i in $(seq 1 12); do
  if az storage container create \
    --name "$CONTAINER" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --output none 2>/dev/null; then
    break
  fi
  [ "$i" = 12 ] && { echo "ERROR: container create failed after RBAC propagation wait" >&2; exit 1; }
  echo "  waiting for role assignment to propagate ($i/12)..."
  sleep 10
done

cat > backend.hcl <<EOF
resource_group_name  = "$STATE_RG"
storage_account_name = "$STORAGE_ACCOUNT"
container_name       = "$CONTAINER"
key                  = "stellar-sandbox/terraform.tfstate"
use_azuread_auth     = true
EOF

echo
echo "Done. backend.hcl written — commit it, then run:"
echo "  terraform init -backend-config=backend.hcl"
echo
echo "For the pipeline, also grant your service connection's identity access:"
echo "  az role assignment create --assignee <service-principal-object-id> \\"
echo "    --role 'Storage Blob Data Contributor' --scope $STORAGE_ID"

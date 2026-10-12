<#
.SYNOPSIS
Creates the Azure Storage backend used by Terraform state.

.DESCRIPTION
Creates a resource group, storage account, and blob container; grants the
signed-in Azure user Storage Blob Data Contributor; and writes backend.hcl in
the current directory. Authentication uses Microsoft Entra ID, not storage
account keys.

.EXAMPLE
.\scripts\bootstrap-state.ps1 -Location eastus

.EXAMPLE
.\scripts\bootstrap-state.ps1 -Location eastus -StateResourceGroup rg-stellar-tfstate -StorageAccount ststellardemo1234 -Container tfstate
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $Location = "eastus",

    [Parameter()]
    [string] $StateResourceGroup = "rg-tfstate",

    [Parameter()]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string] $StorageAccount = ("sttfstate" + [Guid]::NewGuid().ToString("N").Substring(0, 14)),

    [Parameter()]
    [string] $Container = "tfstate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param([Parameter(Mandatory)][string] $Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is required. Install it, then run 'az login'."
}

& az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Not logged in to Azure. Run 'az login' first."
}

$SubscriptionName = (& az account show --query name --output tsv).Trim()
Assert-LastExitCode "Reading the active Azure subscription"

Write-Host "Subscription: $SubscriptionName"
Write-Host "Creating state backend: $StateResourceGroup / $StorageAccount / $Container in $Location"

& az group create --name $StateResourceGroup --location $Location --output none
Assert-LastExitCode "Creating the state resource group"

& az storage account create --name $StorageAccount --resource-group $StateResourceGroup --location $Location --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false --output none
Assert-LastExitCode "Creating the state storage account"

$StorageId = (& az storage account show --name $StorageAccount --resource-group $StateResourceGroup --query id --output tsv).Trim()
Assert-LastExitCode "Reading the state storage account ID"

$UserId = (& az ad signed-in-user show --query id --output tsv).Trim()
Assert-LastExitCode "Reading the signed-in Azure user"

& az role assignment create --assignee $UserId --role "Storage Blob Data Contributor" --scope $StorageId --output none
Assert-LastExitCode "Granting blob access to the signed-in user"

$ContainerCreated = $false
for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
    & az storage container create --name $Container --account-name $StorageAccount --auth-mode login --output none 2>$null

    if ($LASTEXITCODE -eq 0) {
        $ContainerCreated = $true
        break
    }

    if ($Attempt -lt 12) {
        Write-Host "  waiting for role assignment to propagate ($Attempt/12)..."
        Start-Sleep -Seconds 10
    }
}

if (-not $ContainerCreated) {
    throw "Container creation failed after waiting for Azure RBAC propagation."
}

$Backend = @"
resource_group_name  = "$StateResourceGroup"
storage_account_name = "$StorageAccount"
container_name       = "$Container"
key                  = "stellar-sandbox/terraform.tfstate"
use_azuread_auth     = true
"@

$BackendPath = Join-Path (Get-Location) "backend.hcl"
$Utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($BackendPath, $Backend + [Environment]::NewLine, $Utf8WithoutBom)

Write-Host ""
Write-Host "Done. backend.hcl written - commit it, then run:"
Write-Host "  terraform init -backend-config=backend.hcl"
Write-Host ""
Write-Host "For the pipeline, also grant the service connection identity access:"
Write-Host "  az role assignment create --assignee <service-principal-object-id>"
Write-Host "    --role 'Storage Blob Data Contributor' --scope $StorageId"

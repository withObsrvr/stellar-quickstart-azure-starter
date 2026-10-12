# stellar-quickstart-azure-starter

Starter repo for running a **private Stellar sandbox on Azure** with Terraform
and Azure DevOps. Import it into your own Azure DevOps project, run one
bootstrap script, and you get a Stellar network (Horizon + RPC + Friendbot +
Lab) your applications connect to exactly like testnet or pubnet — your SDKs
just point at different addresses ([docs/CONNECTING.md](docs/CONNECTING.md)).

Infrastructure comes from the
[terraform-azure-stellar-quickstart](https://github.com/withobsrvr/terraform-azure-stellar-quickstart)
module (pinned by version in `main.tf`). This repo adds what a consuming team
needs around it: remote state, pipelines, and test-data tooling.

## What you end up with

- A private-by-default Stellar sandbox on Azure Container Instances (no
  public exposure; optional VPN or a public demo mode — see the
  [module README](https://github.com/withobsrvr/terraform-azure-stellar-quickstart#readme))
- Terraform state in Azure Storage (Entra ID auth, no storage keys)
- An Azure DevOps pipeline: plan on PR, gated apply from `main`
  (continuous delivery), automatic re-seeding of test accounts
- `seed-accounts.json` with funded keypairs for your tests

## Setup

For a complete workstation-to-deployment walkthrough—including the short-lived
public demo, internal-only deployment, Point-to-Site VPN, VNet peering,
verification, seeding, and cleanup—see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).
Platform-specific private-access guides are available for
[NixOS/Linux with certificate-authenticated OpenVPN](docs/NIXOS_PRIVATE_ACCESS.md)
and [Windows/macOS with Entra-authenticated Azure VPN
Client](docs/PRIVATE_RELEASE_WINDOWS_MACOS.md).

### 1. Import this repo into Azure DevOps

Repos → Import repository → paste this repo's Git URL.

### 2. Bootstrap the state backend (once, from your workstation)

```bash
az login
./scripts/bootstrap-state.sh eastus
```

On Windows PowerShell, use the native script instead:

~~~powershell
az login
.\scripts\bootstrap-state.ps1 -Location eastus
~~~

Creates the state resource group, storage account, and container; grants you
blob access; writes `backend.hcl`. **Commit `backend.hcl`** (no secrets in it).

### 3. First deploy from your workstation (optional but recommended)

```bash
cp terraform.tfvars.example terraform.tfvars   # adjust if needed
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Commit the generated `.terraform.lock.hcl` so local and pipeline runs select
the same provider version.

In PowerShell, set the subscription environment variable with:

~~~powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv
~~~

### 4. Create the service connection (once)

Project Settings → Service connections → New → Azure Resource Manager →
**Workload Identity federation (automatic)** → scope it to your subscription.
Name it `azure-stellar-sandbox` (or edit `serviceConnection` in
`pipelines/azure-pipelines.yml`).

Then grant its identity access to the state storage account — the bootstrap
script prints the exact command (`Storage Blob Data Contributor` on the
storage account). The service connection also needs Contributor on the
subscription or target resource group.

### 5. Create the pipeline and the approval gate

1. Pipelines → New pipeline → Azure Repos Git → this repo →
   Existing YAML file → `pipelines/azure-pipelines.yml`.
2. Pipelines → Environments → `stellar-sandbox` (created on first run) →
   Approvals and checks → add yourself/your team as **required approvers**.
3. Repos → Branches → `main` → Branch policies → **Build Validation** → add
   this pipeline. (Azure Repos ignores YAML `pr:` triggers; this policy is
   what runs plan on PRs.)

### 6. Merge a PR

Plan runs on the PR; after merge, the apply stage waits for approval, applies,
and re-seeds test accounts (published as the `seed-accounts` pipeline
artifact).

## Continuous delivery vs continuous deployment

The pipeline defaults to **continuous delivery**: applies from `main` pause at
the `stellar-sandbox` environment until approved. For **continuous
deployment**, remove the approval check from that environment — no YAML
changes. The most conservative option is skipping step 5's approvers and
disabling the pipeline's `main` trigger, applying only from workstations.

## Seeding test data

```bash
pip install -r scripts/requirements.txt

# Endpoint reachable (public mode, VPN, or in-VNet):
python3 scripts/seed_accounts.py --count 5

# No network path (private mode from anywhere): goes through the Azure
# control plane instead — this is also what the pipeline uses.
python3 scripts/seed_accounts.py --count 5 --via-exec <resource-group> <container-group>
```

Writes `seed-accounts.json` (gitignored — contains secret keys). The sandbox
network is **ephemeral**: a container restart resets it to genesis, so re-run
seeding after restarts, or let the pipeline's Seed stage do it on every
apply. See [docs/CONNECTING.md](docs/CONNECTING.md) for loading the accounts
in your tests and pointing SDKs at the sandbox.

## Costs

Defaults (private mode, no VPN): roughly **$100/month** for the always-on
container plus ~$1 for state storage. The optional VPN gateway adds
~$190/month. `terraform destroy` when idle; redeploying takes ~5 minutes and
the pipeline re-seeds automatically.

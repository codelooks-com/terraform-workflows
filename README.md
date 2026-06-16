# terraform-workflows

> **Note:** this repository is being renamed from `terraform-azure-templates` to
> `terraform-workflows`. Examples below use the new name; the `uses:` paths resolve
> once the rename lands.

Reusable GitHub Actions workflows for the codelooks Terraform/OpenTofu estate.

## Workflow families

| Family | Files | Purpose |
|--------|-------|---------|
| **azure-*** | `azure-ci.yaml`, `azure-cd.yaml` | Azure Landing Zone CI/CD. `azurerm` backend, Azure OIDC (`ARM_*`). Azure-specific. |
| **standard-*** | `standard-ci.yaml`, `standard-cd.yaml`, `standard-drift.yaml` | Generic CI/CD/drift for all other repos. OpenTofu (default) or Terraform, Cloudflare R2 backend. |

## standard-* inputs

All three accept:

| Input | Default | Notes |
|-------|---------|-------|
| `engine` | `opentofu` | `opentofu` \| `terraform` (Terraform pending the parity gate). |
| `engine_version` | `latest` | CLI version. |
| `runner` | `ubuntu-latest` | Pass an ARC scale-set name (e.g. `terraform-vsphere`) to run on the cluster. |
| `root_module_folder_relative_path` | `.` | Root module location. |
| `op_secrets` | `""` | Multiline `ENV_NAME=op://vault/item/field` list (cloud runners). |
| `azure_oidc` | `false` | Authenticate to Azure via GitHub OIDC (federated, no secrets) instead of 1Password. Sets `ARM_*` env and requests an `id-token`. |
| `tenant_id` | `""` | Azure tenant ID (used when `azure_oidc: true`). |
| `subscription_id` | `""` | Azure subscription ID (used when `azure_oidc: true`). |
| `backend_config` | `""` | Multiline `key=value` list passed to `init` as `-backend-config` flags. For repos with a *partial* backend block (e.g. an empty `backend "azurerm" {}`). Empty ⇒ bare `init`. |

`standard-ci.yaml` / `standard-drift.yaml` also accept `client_id` (the Azure AD app for
OIDC). `standard-cd.yaml` additionally requires `plan_environment` and `apply_environment`
(GitHub Environment names), accepts `action` (`apply` \| `destroy`), and takes **split**
`plan_client_id` / `apply_client_id` so the plan and apply phases can use different
service principals (read-only plan SP, write apply SP) to preserve least privilege.

## Credential model (1Password)

Credentials come from **1Password** on cloud runners and from the **runner pod env** on
ARC cluster runners — there are no per-provider GitHub secrets.

- **Cloud runners:** pass an `op_secrets` input (multiline `ENV_NAME=op://vault/item/field`)
  plus a single `OP_SERVICE_ACCOUNT_TOKEN` secret (org-level recommended). The
  `load-op-secrets` action resolves the references into the job env before init/plan/apply.
- **Cluster (ARC) runners:** creds arrive via the pod's `envFrom`; `load-op-secrets` is a
  no-op when no `OP_SERVICE_ACCOUNT_TOKEN` is set.

Example caller `op_secrets` (nextdns):

```yaml
op_secrets: |
  AWS_ACCESS_KEY_ID=op://Talos/cloudflare-r2-tfstate/R2_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY=op://Talos/cloudflare-r2-tfstate/R2_SECRET_ACCESS_KEY
  AWS_ENDPOINT_URL_S3=op://Talos/cloudflare-r2-tfstate/R2_S3_ENDPOINT
  TF_VAR_nextdns_api_key=op://Talos/<nextdns-item>/<field>
```

**Prerequisite:** a 1Password service account with read access to the relevant vault(s),
token stored as the `OP_SERVICE_ACCOUNT_TOKEN` GitHub secret (org-level on codelooks-com).

## Credential model (Azure OIDC — federated, no secrets)

Azure repos can skip 1Password entirely and authenticate with **GitHub OIDC federated
credentials** — no client secrets stored anywhere. Set `azure_oidc: true` and pass the
client/tenant/subscription IDs; the workflow sets `ARM_USE_OIDC`/`ARM_USE_AZUREAD` and the
job requests an `id-token`. The consumer keeps an `azurerm` backend block in its own
`backend.tf` (the workflows are backend-agnostic).

```yaml
# ci.yaml caller
jobs:
  ci:
    permissions: { contents: read, pull-requests: write, id-token: write }
    uses: codelooks-com/terraform-workflows/.github/workflows/standard-ci.yaml@main
    with:
      engine: opentofu
      azure_oidc: true
      client_id: ${{ vars.PLAN_CLIENT_ID }}
      tenant_id: ${{ vars.ARM_TENANT_ID }}
      subscription_id: ${{ vars.ARM_SUBSCRIPTION_ID }}
```

**Prerequisite:** federated credentials on the SP(s) whose subjects match the jobs that use
them — `repo:<org>/<repo>:pull_request` (ci plan), `repo:<org>/<repo>:environment:<env>`
(cd plan/apply), and `repo:<org>/<repo>:ref:refs/heads/<default-branch>` (scheduled drift).

## R2 backend block (copy into each consumer repo)

```hcl
terraform {
  backend "s3" {
    bucket                      = "<BUCKET>"
    key                         = "<repo>/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}
```

## Onboarding a repo

1. Add the R2 backend block (migrate state with `tofu init -migrate-state` if needed).
2. Add three thin caller workflows (`ci.yaml`, `cd.yaml`, `drift.yaml`) calling the
   `standard-*` reusable workflows.
3. Create GitHub Environments; add a required reviewer to the apply environment for
   sensitive/on-prem repos.
4. Set R2 + provider secrets (cloud repos) or ensure the ARC runner secret carries them
   (cluster repos).

## Development

```bash
mise install                       # bats, actionlint, pinact
mise exec -- bats tests/           # unit tests for the composite-action scripts
mise exec -- actionlint .github/workflows/*.yaml
```

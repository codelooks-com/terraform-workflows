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

`standard-cd.yaml` additionally requires `plan_environment` and `apply_environment`
(GitHub Environment names) and accepts `action` (`apply` \| `destroy`).

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

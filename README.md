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

`standard-cd.yaml` additionally requires `plan_environment` and `apply_environment`
(GitHub Environment names) and accepts `action` (`apply` \| `destroy`).

## Credential model

Workflows read credentials from the **environment**. The `resolve-creds` action maps
caller-provided secrets (`IN_<NAME>`) into the environment **only when non-empty**, so:

- **Cloud runners** pass creds via `secrets:` in the caller (mapped in).
- **Cluster (ARC) runners** receive creds via the pod's `envFrom`; empty caller secrets
  do not clobber them.

R2 state creds (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) are required on **both**
runner types. Recognised provider creds: `CLOUDFLARE_API_TOKEN`, `TS_OAUTH_CLIENT_ID`,
`TS_OAUTH_SECRET`, `NEXTDNS_API_KEY`, GitHub App creds, `VSPHERE_USER` /
`VSPHERE_PASSWORD` / `VSPHERE_SERVER`.

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

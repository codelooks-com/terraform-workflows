# terraform-workflows

Reusable GitHub Actions workflows for the codelooks Terraform/OpenTofu estate.

## Workflows

One family serves the whole estate — Azure and non-Azure alike:

| File | Purpose |
|------|---------|
| `standard-ci.yaml` | PR gate: fmt / init / validate / tflint / plan, with a plan comment on the PR. |
| `standard-cd.yaml` | Push-to-main plan → apply (split plan/apply environments and client IDs), plus manual `apply`/`destroy` dispatch. |
| `standard-drift.yaml` | Scheduled `-detailed-exitcode` plan that files/updates a `terraform-drift` issue. |

Azure support is declarative only (the `azure_oidc` flag + ID inputs set `ARM_*` env);
there are no Azure-specific steps. The legacy `azure-ci`/`azure-cd` family was removed
2026-07-06 after its last consumer (terraform-azure-platform) cut over to `standard-*` —
it remains in git history and the pre-removal tags if ever needed.

## Versioning & pinning

Consumers pin `uses:` references to a release tag or commit SHA — never `@main`. These
workflows run with the caller's apply credentials, so an unpinned ref means any push to
this repo's `main` executes in every apply pipeline in the estate. Renovate (house
preset) converts tag refs to `SHA # vX.Y.Z` pins and bumps them via PR.

```yaml
uses: codelooks-com/terraform-workflows/.github/workflows/standard-ci.yaml@v1.0.0
```

Internal `uses:` references (the composite actions the reusable workflows call) are
pinned to the release tag itself, so a pinned consumer never executes unpinned code.

**Release procedure** (the tag is self-referencing, so order matters):

1. In the release PR, update every internal `.github/actions/*@<tag>` reference to the
   new tag name.
2. Merge the PR.
3. Immediately tag the merge commit: `git tag vX.Y.Z <merge-sha> && git push origin vX.Y.Z`.
   The internal refs cannot resolve until the tag exists, so cut it straight after merging.

## standard-* inputs

All three accept:

| Input | Default | Notes |
|-------|---------|-------|
| `engine` | `opentofu` | `opentofu` \| `terraform` (Terraform pending the parity gate). |
| `engine_version` | `1.12.3` | CLI version (pinned OpenTofu; Renovate bumps the default). Callers should still pin explicitly. |
| `runner` | `ubuntu-latest` | Pass an ARC scale-set name (e.g. `terraform-vsphere`) to run on the cluster. |
| `root_module_folder_relative_path` | `.` | Root module location. |
| `op_secrets` | `""` | Multiline `ENV_NAME=op://vault/item/field` list (cloud runners). |
| `azure_oidc` | `false` | Authenticate to Azure via GitHub OIDC (federated, no secrets) instead of 1Password. Sets `ARM_*` env and requests an `id-token`. |
| `tenant_id` | `""` | Azure tenant ID (used when `azure_oidc: true`). |
| `subscription_id` | `""` | Azure subscription ID (used when `azure_oidc: true`). |
| `backend_config` | `""` | Multiline `key=value` list passed to `init` as `-backend-config` flags. For repos with a *partial* backend block (e.g. an empty `backend "azurerm" {}`). Empty ⇒ bare `init`. |
| `extra_env` | `""` | Multiline `KEY=value` list exported into the job env (via `$GITHUB_ENV`) before `init`/`plan`/`apply`. For provider tuning such as `AZAPI_RETRY_GET_AFTER_PUT_MAX_TIME`. Empty ⇒ no-op. |
| `environment` | `""` | **`standard-ci` / `standard-drift`**: GitHub Environment to bind the plan/drift job to. Needed when the repo customizes its OIDC subject to require the `environment` claim. Empty ⇒ no environment. (`standard-cd` already has `plan_environment`/`apply_environment`.) |

`standard-ci.yaml` / `standard-drift.yaml` also accept `client_id` (the Azure AD app for
OIDC). `standard-cd.yaml` additionally requires `plan_environment` and `apply_environment`
(GitHub Environment names), accepts `action` (`apply` \| `destroy`), and takes **split**
`plan_client_id` / `apply_client_id` so the plan and apply phases can use different
service principals (read-only plan SP, write apply SP) to preserve least privilege.

> **Why the input names differ:** the asymmetry is deliberate, not drift. `standard-ci`
> and `standard-drift` run a single read-only phase, so one `client_id` suffices.
> `standard-cd` runs two phases with different privilege levels, so its identity and
> environment inputs are split (`plan_*` / `apply_*`). Renaming ci/drift's `client_id`
> to `plan_client_id` for symmetry would be a breaking change for every consumer with
> no privilege benefit — a single-phase workflow has nothing to split.

## Concurrency

Every plan/apply/drift job takes a concurrency group of
`<owner/repo>-<root_module_folder_relative_path>-tfstate` with `cancel-in-progress: false`,
so runs touching the **same state file** serialise rather than racing.

The root module is part of the key on purpose. Matrix callers
(`terraform-azure-workloads` runs one leg per workload) have a separate state file per
root module and can safely apply in parallel; a repo-wide key made those legs queue
against each other, and GitHub cancels the older *waiting* run as soon as a second one
arrives — so a multi-workload push silently applied only one workload. Single-root repos
key on the `.` default and are unaffected.

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
    uses: codelooks-com/terraform-workflows/.github/workflows/standard-ci.yaml@v1.0.0
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

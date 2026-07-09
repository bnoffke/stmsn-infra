# stmsn-infra: bootstrap and retroactive import plan

Handoff spec for standing up `stmsn-infra`: a Terraform repo that adopts the
existing `madison-municipal-data` GCP project's shared infrastructure into
managed state, and leaves typed placeholders for the pipeline resources that
come online in later phases.

## Goal

One repo owns project-level shared infrastructure declaratively. It does not
own application code or container images. The only thing that ever crosses the
repo boundary from `stmsn_dbt` / `stmsn-ingest` is an image tag.

The first job is retroactive: the two data buckets that exist today were
created by hand. This plan brings them under state without recreating anything,
creates the new buckets greenfield, and stubs the rest.

## Key decision: state and catalog live in separate buckets

`stmsn-tfstate` holds Terraform remote state and nothing else. It is
hand-created once, versioned, and never written as a Terraform resource or
imported. Keeping it unmanaged sidesteps the self-management edge entirely: a
`terraform destroy` can never touch the bucket holding its own state, because
Terraform doesn't know that bucket exists.

`stmsn-meta` holds the DuckLake catalog under a `ducklake/` prefix. It is a
normal managed bucket, created greenfield by `terraform apply`, with versioning
on to protect the catalog.

Two things to keep in mind:

- **`ducklake/` is a prefix, not a Terraform object.** Terraform creates the
  bucket and turns on versioning. The catalog file (`ducklake/catalog.ducklake`)
  lands there at runtime via the pull/push cycle. No `google_storage_bucket_object`.
- The DuckLake *data* parquet stays in `stmsn-silver`. Only the catalog
  metadata file lives in `meta/ducklake/`. If the catalog later moves to a
  hosted Postgres (Neon/Supabase) for concurrent writes, `meta/ducklake/` goes
  empty and the bucket layout is unchanged.

## Storage layout

| Bucket | Status | Action | Versioning |
|---|---|---|---|
| `stmsn-tfstate` | new | hand-create, leave unmanaged | on |
| `stmsn-meta` | new | `terraform apply` (greenfield) | on, keep 10 |
| `stmsn-bronze` | exists (manual, `us-central1`) | import | off |
| `stmsn-silver` | exists | import | off |

`stmsn-meta`, `stmsn-bronze`, and `stmsn-silver` are authored as calls to a
small `gcs_bucket` module. Buckets that exist are imported to their module
address; the new one is applied.

## Repo layout

```
stmsn-infra/
├── README.md              # decisions, bootstrap order, how to apply
├── versions.tf            # terraform + provider pins
├── providers.tf           # google provider + default_labels
├── backend.tf             # gcs remote state -> gs://stmsn-tfstate/infra
├── variables.tf           # project_id, region
├── project_services.tf    # required APIs as code
├── storage.tf             # the three managed buckets (module calls)
├── outputs.tf             # bucket names / urls
├── artifact_registry.tf   # PLACEHOLDER: import existing repo or create stmsn repo
├── iam.tf                 # PLACEHOLDER: scheduler SA + job-scoped run.invoker
├── run_jobs.tf            # PLACEHOLDER: stmsn-runner, stmsn-ingest (Phase 3)
├── scheduler.tf           # PLACEHOLDER: daily + monthly triggers (Phase 3)
├── workflows.tf           # PLACEHOLDER: monthly-opendata chain (Phase 3)
├── imports.generated.tf   # produced by scripts/gen_imports.sh, then deleted
├── generated.tf           # produced by terraform plan -generate-config-out
├── .gitignore
├── .terraform.lock.hcl    # committed, pins provider hashes
├── .pre-commit-config.yaml
├── modules/
│   └── gcs_bucket/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    ├── bootstrap.sh       # hand-create stmsn-tfstate
    └── gen_imports.sh     # enumerate existing resources -> import blocks
```

The GitHub Actions WIF workflow (`.github/workflows/terraform.yml`) is
deliberately absent for now. It is the Phase 4 portfolio capstone, not a
blocker, and the local pre-commit hook covers most of its value in the interim.

## Phase 0 sequence

1. Run `scripts/bootstrap.sh` to hand-create `stmsn-tfstate` (versioned).
2. Write `versions.tf`, `providers.tf`, `backend.tf`, `variables.tf`.
3. `terraform init` (talks to remote state in the bucket you just made).
4. Write the `gcs_bucket` module, `storage.tf`, and `project_services.tf`.
5. Import the two existing buckets to their module addresses (commands below).
6. `terraform plan` until it shows zero changes on the imported buckets, then
   `apply` to create `stmsn-meta` and enable the APIs. The import
   reconciliation is the meatiest skill in the phase.
7. Run `scripts/gen_imports.sh` for the non-bucket resources, then
   `terraform plan -generate-config-out=generated.tf` to draft their HCL.
8. Clean up `generated.tf`, delete `imports.generated.tf`, apply.
9. Write `outputs.tf`, the README, and commit `.terraform.lock.hcl`.

## bootstrap.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-madison-municipal-data}"
REGION="${REGION:-us-central1}"
STATE_BUCKET="stmsn-tfstate"

# The state bucket cannot be Terraform-managed (it holds the state), so it is
# created by hand exactly once and never imported.
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="${PROJECT}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --public-access-prevention

# Versioning lets you recover a clobbered state file.
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning

echo "Created gs://${STATE_BUCKET} (versioned, unmanaged)."
echo "Next: write backend.tf, then run 'terraform init'."
```

## backend.tf

```hcl
terraform {
  backend "gcs" {
    bucket = "stmsn-tfstate"
    prefix = "infra"
  }
}
```

GCS backend locking is automatic, so there is nothing to configure for state
locking.

## versions.tf

```hcl
terraform {
  required_version = ">= 1.5"   # 1.5+ gives import blocks + generate-config
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"        # 6.x resolves the default_labels diff issue
    }
  }
}
```

## providers.tf

`default_labels` stamps a consistent label set onto every resource that
supports labels, from one place. This is the cheapest thing to lock in now and
impossible to backfill: you cannot label spend that already happened. Once a
BigQuery billing export is on, these labels let you slice GCP cost by component
in dbt.

```hcl
provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed-by = "terraform"
    project    = "stmsn"
    repo       = "stmsn-infra"
  }
}
```

Provider 6.x separates `labels` from `effective_labels`, so the historical
perpetual-diff problem with `default_labels` does not apply.

## project_services.tf

APIs as code makes the project reproducible from scratch and reads as
intentional. `disable_on_destroy = false` means a destroy never yanks an API
out from under a resource that still needs it. These are likely already enabled,
so `apply` is a no-op that simply adopts them; no import needed.

```hcl
resource "google_project_service" "apis" {
  for_each = toset([
    "storage.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "workflows.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
```

## Retroactive import approach

Two tracks, because the resources differ in how much typing they save.

**Buckets: author by hand, import the existing ones to the module address.**
Only bronze and silver exist and need importing; meta is applied fresh. No
generate-config needed.

```bash
terraform import 'module.bronze.google_storage_bucket.this' stmsn-bronze
terraform import 'module.silver.google_storage_bucket.this' stmsn-silver
# module.meta is created by apply, not imported
```

**Everything else: discovery script emits import blocks, then generate-config
drafts the HCL.** This is where `-generate-config-out` earns its keep, since
Cloud Run Jobs and Scheduler jobs have long attribute surfaces.

The generated config is a starting point, not a finished file. It over-writes
provider defaults and sometimes emits fields in an invalid combination. Read
every block before applying.

### gen_imports.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-madison-municipal-data}"
REGION="${REGION:-us-central1}"
OUT="imports.generated.tf"

: > "$OUT"
sanitize() { echo "$1" | tr -c 'a-zA-Z0-9_' '_'; }

# route-traffic-monitor owns its own Terraform, so its resources are excluded
# here to avoid double management. Adjust the pattern to match its actual names.
SKIP_RE="${SKIP_RE:-route-traffic|route_traffic|routes}"
skip() { echo "$1" | grep -Eqi "$SKIP_RE"; }

{
  echo "// Generated import blocks. Review, then:"
  echo "//   terraform plan -generate-config-out=generated.tf"
  echo "// Delete this file once generated.tf is cleaned and applied."
  echo
} >> "$OUT"

emit() {  # emit <resource_type> <local_name> <import_id>
  cat >> "$OUT" <<EOF
import {
  to = ${1}.${2}
  id = "${3}"
}
EOF
}

# Cloud Run v2 jobs
for j in $(gcloud run jobs list --project="$PROJECT" --region="$REGION" \
             --format="value(metadata.name)" 2>/dev/null); do
  skip "$j" && continue
  emit google_cloud_run_v2_job "$(sanitize "$j")" \
       "projects/${PROJECT}/locations/${REGION}/jobs/${j}"
done

# Cloud Scheduler jobs
for s in $(gcloud scheduler jobs list --project="$PROJECT" --location="$REGION" \
             --format="value(name)" 2>/dev/null); do
  short="${s##*/}"
  skip "$short" && continue
  emit google_cloud_scheduler_job "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/jobs/${short}"
done

# Artifact Registry repositories
for r in $(gcloud artifacts repositories list --project="$PROJECT" \
             --location="$REGION" --format="value(name)" 2>/dev/null); do
  short="${r##*/}"
  emit google_artifact_registry_repository "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/repositories/${short}"
done

# Cloud Workflows
for w in $(gcloud workflows list --project="$PROJECT" --location="$REGION" \
             --format="value(name)" 2>/dev/null); do
  short="${w##*/}"
  emit google_workflows_workflow "$(sanitize "$short")" \
       "projects/${PROJECT}/locations/${REGION}/workflows/${short}"
done

# Service accounts (skip Google-managed defaults)
for sa in $(gcloud iam service-accounts list --project="$PROJECT" \
              --format="value(email)"); do
  case "$sa" in
    *-compute@developer.gserviceaccount.com) continue;;
    *@cloudservices.gserviceaccount.com)     continue;;
    *@appspot.gserviceaccount.com)           continue;;
  esac
  skip "$sa" && continue
  emit google_service_account "$(sanitize "${sa%%@*}")" \
       "projects/${PROJECT}/serviceAccounts/${sa}"
done

echo "Wrote ${OUT}"
echo "Next: terraform plan -generate-config-out=generated.tf"
```

Then:

```bash
terraform plan -generate-config-out=generated.tf
# review generated.tf, fold Cloud Run / Scheduler config into the phase files,
# reconcile to a zero-diff plan, then:
terraform apply
rm imports.generated.tf
```

route-traffic-monitor's resources are filtered out by `SKIP_RE`, since that
repo owns its own Terraform. Sanity-check the discovery output before applying:
if `SKIP_RE` misses a route-traffic resource because its name does not match,
that resource would land in `stmsn-infra` and become double-managed. Widen the
pattern rather than importing it.

## modules/gcs_bucket

The module carries two guards born in from the start: versioning-conditional
pruning, and `prevent_destroy` so a stray `apply` can't force-replace a bucket
full of parquet or state.

Note on `prevent_destroy`: Terraform requires a literal here and rejects a
variable reference, so it is hardcoded `true` in the module rather than
toggled by a flag. Every bucket this module makes is stateful data, so
protecting all of them is the correct default. If a throwaway bucket ever
needs to be destroyable, it should not use this module.

```hcl
# main.tf
resource "google_storage_bucket" "this" {
  name     = var.name
  project  = var.project
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning { enabled = var.versioning }

  dynamic "lifecycle_rule" {          # pruning only when versioning is on
    for_each = var.versioning ? [1] : []
    content {
      condition { num_newer_versions = var.keep_versions }
      action    { type = "Delete" }
    }
  }

  lifecycle {
    prevent_destroy = true            # literal required; guards all buckets
  }
}
```

```hcl
# variables.tf
variable "name"          { type = string }
variable "project"       { type = string }
variable "location"      { type = string }
variable "versioning"    { type = bool   default = false }
variable "keep_versions" { type = number default = 10 }
```

```hcl
# outputs.tf
output "name" { value = google_storage_bucket.this.name }
output "url"  { value = google_storage_bucket.this.url }
```

Labels are handled by the provider's `default_labels`, so there is no per-bucket
label variable to thread through.

## storage.tf

```hcl
module "meta" {
  source     = "./modules/gcs_bucket"
  name       = "stmsn-meta"
  project    = var.project_id
  location   = var.region
  versioning = true        # protects the ducklake catalog
}

module "bronze" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-bronze"
  project  = var.project_id
  location = var.region
}

module "silver" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-silver"
  project  = var.project_id
  location = var.region
}
```

## Repo hygiene

All done once, all trivial, all annoying to bolt on later.

**.gitignore** keeps state and local scratch out of git as belt-and-suspenders,
even though state lives remotely:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars          # if any hold anything you would not commit
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

**Commit `.terraform.lock.hcl`.** It pins provider hashes so a future `init`
cannot silently drift onto a new provider build. It is created by the first
`terraform init` / `providers lock`; add it to git.

**.pre-commit-config.yaml** gives most of the CI value locally, which is why
the keyless-OIDC workflow stays deferred rather than blocking:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.99.0     # pin to whatever is current at setup
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
```

`tflint` is a fine optional third hook for provider-aware linting, but it is
polish, not fruit; add it only if you want it.

## Placeholders for later phases

Each stub is a real file with a header comment so the repo reads as intentional
rather than half-built. Fill them as the phases land.

**artifact_registry.tf** (Phase 0 or 1). A Docker repo named `stmsn` in
`us-central1`. If `gcloud run ... --source` already created a
`cloud-run-source-deploy` repo for route-traffic-monitor, the discovery script
will surface it: decide whether to adopt it or stand up a clean `stmsn` repo and
retarget builds. Flagged as an open item.

**run_jobs.tf** (Phase 3). `stmsn-runner` and `stmsn-ingest` as
`google_cloud_run_v2_job`, image refs supplied via variable and bumped on each
build. One runner job, per-execution arg overrides for the two cadences.

**scheduler.tf** (Phase 3). Daily trigger runs the runner directly
(`--select source:routes+`); monthly trigger fires the workflow.

**workflows.tf** (Phase 3). `monthly-opendata`: ingest job, wait, runner job
(`--select source:madison_opendata+`). The connector blocks and fails the
workflow if the ingest fails, so a bad ingest never triggers the build.

**iam.tf** (Phase 3). A scheduler service account with a job-scoped
`run.invoker` binding per job, not a project-level grant.

## IAM caveat

IAM is the one place not to lean on import. Members, bindings, and policies
import differently, and the `google_cloud_run_v2_job_iam_member` id format
(`.../jobs/JOB roles/run.invoker serviceAccount:...`) is easy to get wrong.
Author IAM by hand in `iam.tf` rather than importing it. The scheduler SA and
its `run.invoker` bindings are new anyway, created alongside the Phase 3 jobs,
so there is little existing IAM worth adopting.

## Ownership boundaries

- **route-traffic-monitor is fully self-contained (decided).** It keeps all of
  its own Terraform, including its Cloud Run Job, Scheduler jobs, and service
  account, driven by its `config/routes.yaml`. `stmsn-infra` does not manage
  any of it. The discovery script filters these out via `SKIP_RE`; confirm the
  pattern catches every route-traffic resource so none leak into this repo.
  The one thing route-traffic still consumes from here is `stmsn-bronze`, which
  it treats as a pre-existing data source, not a managed resource.

## Open items to confirm before importing

- **Artifact Registry repo.** Adopt the auto-created `cloud-run-source-deploy`
  repo, or create a clean `stmsn` repo and retarget builds.
- **Billing budget.** The under-$1/month alert lives at the billing-account
  level, which is awkward to manage from a project-scoped Terraform config.
  Leave it out of scope for now; note its existence in the README.

## Deliberately skipped

Greenfield is exactly when this creeps in, so name it and skip it: no dev/prod
split, no workspaces, no multi-level module tree. Three managed buckets and a
handful of jobs behind one `gcs_bucket` module is the right amount of structure.
Environment scaffolding here would read as cargo-culting, not competence.

## Phase 0 checklist

- [ ] `bootstrap.sh` run, `stmsn-tfstate` created, versioned, unmanaged
- [ ] `versions.tf`, `providers.tf` (with `default_labels`), `backend.tf`, `variables.tf` written
- [ ] `terraform init` against remote state succeeds
- [ ] `gcs_bucket` module written (versioning-conditional pruning + `prevent_destroy`)
- [ ] `project_services.tf` written
- [ ] bronze and silver imported to module addresses, plan is zero-diff
- [ ] `apply` creates `stmsn-meta` and adopts the APIs
- [ ] `gen_imports.sh` run, non-bucket resources reviewed
- [ ] `SKIP_RE` confirmed to exclude every route-traffic-monitor resource
- [ ] `generated.tf` cleaned, applied, `imports.generated.tf` deleted
- [ ] `outputs.tf` and README written
- [ ] `.gitignore`, `.terraform.lock.hcl`, `.pre-commit-config.yaml` committed
- [ ] placeholder files committed with header comments
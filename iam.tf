# Bucket-level IAM bindings.
# Legacy roles (legacyBucketOwner, legacyBucketReader) are GCP-managed via project
# membership and are intentionally omitted here.
#
# Phase 3: scheduler SA + job-scoped run.invoker bindings will be added here
# when Cloud Run jobs land. Author by hand; see INITIAL_WORK.md IAM caveat.

locals {
  sa = {
    dbt_sa           = "serviceAccount:dbt-sa@madison-municipal-data.iam.gserviceaccount.com"
    duckdb_reader    = "serviceAccount:duckdb-reader@madison-municipal-data.iam.gserviceaccount.com"
    api_sa           = "serviceAccount:api-sa@madison-municipal-data.iam.gserviceaccount.com"
    streamlit_reader = "serviceAccount:streamlit-reader@madison-municipal-data.iam.gserviceaccount.com"
    # route-traffic-runner SA is owned by route-traffic-monitor repo; we only
    # manage its binding on the bronze bucket, not the SA resource itself.
    route_traffic_runner = "serviceAccount:route-traffic-runner@madison-municipal-data.iam.gserviceaccount.com"
    ci_publisher         = "serviceAccount:ci-publisher-sa@madison-municipal-data.iam.gserviceaccount.com"
    ci_docs              = "serviceAccount:ci-docs-sa@madison-municipal-data.iam.gserviceaccount.com"
    scheduler_sa         = "serviceAccount:scheduler-sa@madison-municipal-data.iam.gserviceaccount.com"
  }
  github_repo = "bnoffke/stmsn_dbt"
}

# ---------------------------------------------------------------------------
# Workload Identity Federation for GitHub Actions (stmsn_dbt)
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  project                   = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == \"${local.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Publish is pinned to main via the OIDC subject (repo:<repo>:ref:refs/heads/main);
# docs may run repo-wide.
resource "google_service_account_iam_member" "ci_publisher_wif" {
  service_account_id = google_service_account.ci_publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${local.github_repo}:ref:refs/heads/main"
}

resource "google_service_account_iam_member" "ci_docs_wif" {
  service_account_id = google_service_account.ci_docs.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repo}"
}

# ---------------------------------------------------------------------------
# ci-publisher-sa: docker build/push runs on the GitHub runner; AR writer is
# the entire permission surface.
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository_iam_member" "ci_publisher_ar_writer" {
  repository = google_artifact_registry_repository.stmsn.repository_id
  location   = var.region
  project    = var.project_id
  role       = "roles/artifactregistry.writer"
  member     = local.sa.ci_publisher
}

# Cloud Scheduler → Cloud Run job invocation
# roles/run.invoker lacks run.jobs.runWithOverrides, which the scheduler's
# containerOverrides body requires.
resource "google_project_iam_custom_role" "run_with_overrides" {
  project     = var.project_id
  role_id     = "runJobsWithOverrides"
  title       = "Run Cloud Run jobs with overrides"
  permissions = ["run.jobs.run", "run.jobs.runWithOverrides"]
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_runner" {
  name     = google_cloud_run_v2_job.stmsn_runner.name
  location = var.region
  project  = var.project_id
  role     = google_project_iam_custom_role.run_with_overrides.id
  member   = local.sa.scheduler_sa
}

# stmsn-bronze
resource "google_storage_bucket_iam_binding" "bronze_object_admin" {
  bucket = module.bronze.name
  role   = "roles/storage.objectAdmin"
  members = [
    local.sa.route_traffic_runner,
    # project-813068017704@storage-transfer-service SA was auto-created by a
    # one-time console transfer job and is not actively used. Remove it here;
    # if Storage Transfer is ever needed again, add a fresh binding at that time.
  ]
}

resource "google_storage_bucket_iam_binding" "bronze_object_viewer" {
  bucket = module.bronze.name
  role   = "roles/storage.objectViewer"
  members = [
    local.sa.dbt_sa,
    local.sa.duckdb_reader,
    local.sa.streamlit_reader,
  ]
}

# stmsn-silver
resource "google_storage_bucket_iam_binding" "silver_object_admin" {
  bucket = module.silver.name
  role   = "roles/storage.objectAdmin"
  members = [
    local.sa.dbt_sa,
  ]
}

resource "google_storage_bucket_iam_binding" "silver_object_viewer" {
  bucket = module.silver.name
  role   = "roles/storage.objectViewer"
  members = [
    local.sa.api_sa,
    local.sa.duckdb_reader,
    local.sa.streamlit_reader,
  ]
}

# stmsn-gold
resource "google_storage_bucket_iam_binding" "gold_object_admin" {
  bucket = module.gold.name
  role   = "roles/storage.objectAdmin"
  members = [
    local.sa.dbt_sa,
  ]
}

resource "google_storage_bucket_iam_binding" "gold_object_viewer" {
  bucket = module.gold.name
  role   = "roles/storage.objectViewer"
  members = [
    local.sa.api_sa,
    local.sa.duckdb_reader,
    local.sa.streamlit_reader,
  ]
}

# stmsn-lake
resource "google_storage_bucket_iam_binding" "lake_object_user" {
  bucket  = module.lake.name
  role    = "roles/storage.objectUser"
  members = [local.sa.dbt_sa]
}

resource "google_storage_bucket_iam_binding" "lake_object_viewer" {
  bucket  = module.lake.name
  role    = "roles/storage.objectViewer"
  members = [local.sa.ci_docs, local.sa.duckdb_reader, local.sa.streamlit_reader]
}

# stmsn-meta
# ingest-runner and the user account had pre-existing objectUser grants made
# outside Terraform; this authoritative binding takes them under management.
resource "google_storage_bucket_iam_binding" "meta_object_user" {
  bucket = module.meta.name
  role   = "roles/storage.objectUser"
  members = [
    local.sa.dbt_sa,
    "serviceAccount:ingest-runner@madison-municipal-data.iam.gserviceaccount.com",
    "user:bnoffke3790@gmail.com",
  ]
}

resource "google_storage_bucket_iam_binding" "meta_object_viewer" {
  bucket  = module.meta.name
  role    = "roles/storage.objectViewer"
  members = [local.sa.ci_docs, local.sa.duckdb_reader, local.sa.streamlit_reader]
}

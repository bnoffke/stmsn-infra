resource "google_service_account" "dbt_sa" {
  account_id   = "dbt-sa"
  display_name = "dbt Service Account"
  description  = "Service account to enable dbt build."
  project      = var.project_id
}

resource "google_service_account" "duckdb_reader" {
  account_id   = "duckdb-reader"
  display_name = "DuckDB Reader"
  description  = "Readonly account for querying GCS from duckdb."
  project      = var.project_id
}

resource "google_service_account" "api_sa" {
  account_id   = "api-sa"
  display_name = "Service account API access"
  project      = var.project_id
}

resource "google_service_account" "streamlit_reader" {
  account_id   = "streamlit-reader"
  display_name = "Streamlit App Readonly"
  project      = var.project_id
}

resource "google_service_account" "scheduler_sa" {
  account_id   = "scheduler-sa"
  display_name = "Cloud Scheduler Invoker"
  description  = "Invokes Cloud Run jobs on schedule; run.invoker only."
  project      = var.project_id
}

resource "google_service_account" "ci_publisher" {
  account_id   = "ci-publisher-sa"
  display_name = "CI Publisher"
  description  = "GitHub Actions (stmsn-dbt publish.yml): builds and pushes the runner image."
  project      = var.project_id
}

resource "google_service_account" "ci_docs" {
  account_id   = "ci-docs-sa"
  display_name = "CI Docs"
  description  = "GitHub Actions (stmsn-dbt docs.yml): read-only lake/meta access for dbt docs generation."
  project      = var.project_id
}

# One SA per guest so credentials revoke individually and reads are
# attributable per person. Owner email goes in the description to keep the
# roster auditable from the console.
resource "google_service_account" "guest_reader" {
  for_each     = var.guest_readers
  account_id   = "guest-${each.key}-sa"
  display_name = "Guest Reader (${each.key})"
  description  = "Read-only lakehouse guest. Owner: ${each.value}"
  project      = var.project_id
}

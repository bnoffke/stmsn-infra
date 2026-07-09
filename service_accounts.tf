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

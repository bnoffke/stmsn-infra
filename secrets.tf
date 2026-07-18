# HMAC key pairs for GCS access via dbt profiles.
# Plaintext HMAC secrets land in TF state (stmsn-tfstate is private).
# After the writer pair is confirmed end-to-end, revoke the local plaintext
# key in ~/.dbt/profiles.yml (manual last step per the verification plan).

resource "google_storage_hmac_key" "dbt_writer" {
  service_account_email = google_service_account.dbt_sa.email
  project               = var.project_id
}

resource "google_storage_hmac_key" "docs_reader" {
  service_account_email = google_service_account.ci_docs.email
  project               = var.project_id
}

# ---------------------------------------------------------------------------
# Writer pair — consumed by the stmsn-runner Cloud Run Job (dbt_sa)
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "dbt_gcs_key_id" {
  secret_id  = "dbt-gcs-key-id"
  project    = var.project_id
  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "dbt_gcs_key_id" {
  secret      = google_secret_manager_secret.dbt_gcs_key_id.id
  secret_data = google_storage_hmac_key.dbt_writer.access_id
}

resource "google_secret_manager_secret" "dbt_gcs_secret" {
  secret_id  = "dbt-gcs-secret"
  project    = var.project_id
  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "dbt_gcs_secret" {
  secret      = google_secret_manager_secret.dbt_gcs_secret.id
  secret_data = google_storage_hmac_key.dbt_writer.secret
}

# ---------------------------------------------------------------------------
# Reader pair — consumed by docs CI (ci-docs-sa)
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "docs_gcs_key_id" {
  secret_id  = "docs-gcs-key-id"
  project    = var.project_id
  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "docs_gcs_key_id" {
  secret      = google_secret_manager_secret.docs_gcs_key_id.id
  secret_data = google_storage_hmac_key.docs_reader.access_id
}

resource "google_secret_manager_secret" "docs_gcs_secret" {
  secret_id  = "docs-gcs-secret"
  project    = var.project_id
  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "docs_gcs_secret" {
  secret      = google_secret_manager_secret.docs_gcs_secret.id
  secret_data = google_storage_hmac_key.docs_reader.secret
}

# ---------------------------------------------------------------------------
# Accessor bindings
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret_iam_member" "dbt_sa_key_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.dbt_gcs_key_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa.dbt_sa
}

resource "google_secret_manager_secret_iam_member" "dbt_sa_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.dbt_gcs_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa.dbt_sa
}

resource "google_secret_manager_secret_iam_member" "ci_docs_key_id" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.docs_gcs_key_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa.ci_docs
}

resource "google_secret_manager_secret_iam_member" "ci_docs_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.docs_gcs_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa.ci_docs
}

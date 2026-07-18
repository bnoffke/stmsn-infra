resource "google_cloud_run_v2_job" "stmsn_runner" {
  name                = "stmsn-runner"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  # Image is currently pinned to `latest` for convenience during initial setup.
  # Pin to a specific SHA after the first successful end-to-end run.
  template {
    template {
      service_account = google_service_account.dbt_sa.email
      timeout         = "1800s"
      max_retries     = 0

      containers {
        image = "us-central1-docker.pkg.dev/${var.project_id}/stmsn/stmsn-runner:latest"

        resources {
          limits = {
            memory = "4Gi"
            cpu    = "2"
          }
        }

        env {
          name = "GCS_KEY_ID"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.dbt_gcs_key_id.secret_id
              version = "latest"
            }
          }
        }

        env {
          name = "GCS_SECRET"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.dbt_gcs_secret.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

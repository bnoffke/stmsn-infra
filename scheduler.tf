# Monthly trigger (fires workflow) still TBD.

# Nightly dbt run: 10 PM Central (time_zone handles CST/CDT).
resource "google_cloud_scheduler_job" "stmsn_daily" {
  name      = "stmsn-daily"
  region    = var.region
  project   = var.project_id
  schedule  = "0 22 * * *"
  time_zone = "America/Chicago"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.stmsn_runner.name}:run"
    body = base64encode(jsonencode({
      overrides = {
        containerOverrides = [{ args = ["tag:daily"] }]
      }
    }))
    headers = { "Content-Type" = "application/json" }

    # OAuth (not OIDC): run.googleapis.com is a Google API and takes access tokens.
    oauth_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }

  depends_on = [google_project_service.apis["cloudscheduler.googleapis.com"]]
}

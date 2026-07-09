resource "google_artifact_registry_repository" "stmsn" {
  repository_id = "stmsn"
  location      = var.region
  project       = var.project_id
  format        = "DOCKER"
}

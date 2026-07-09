provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed-by = "terraform"
    project    = "stmsn"
    repo       = "stmsn-infra"
  }
}

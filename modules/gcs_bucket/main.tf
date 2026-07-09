resource "google_storage_bucket" "this" {
  name     = var.name
  project  = var.project
  location = var.location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning { enabled = var.versioning }

  dynamic "lifecycle_rule" {
    for_each = var.versioning ? [1] : []
    content {
      condition { num_newer_versions = var.keep_versions }
      action { type = "Delete" }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

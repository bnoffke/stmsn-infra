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
  }
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

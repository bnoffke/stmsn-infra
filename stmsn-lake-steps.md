# Making `stmsn-lake`
 
The DuckLake root data path. One bucket, DuckLake-managed, with `silver` and `gold` as schemas underneath (`gs://stmsn-lake/silver/...`, `gs://stmsn-lake/gold/...`). Bronze stays its own raw bucket; meta stays the catalog bucket. Full integration details live in `ducklake_integration_guide.md`; this is just standing up the bucket.
 
## 1. Terraform (`stmsn-infra`)
 
```hcl
resource "google_storage_bucket" "lake" {
  name                        = "stmsn-lake"
  project                     = var.project_id
  location                    = var.region        # match your existing stmsn-* buckets
  storage_class               = "STANDARD"         # hot working lake
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false              # data bucket, no accidental destroy
 
  # No object versioning here. DuckLake writes immutable Parquet and tracks the
  # file lifecycle in the catalog, so bucket versioning would only bloat storage.
  # (Object versioning belongs on stmsn-meta, for one-line catalog rollback.)
}
 
# dbt runner service account: read/write/delete on lake objects
resource "google_storage_bucket_iam_member" "lake_rw" {
  bucket = google_storage_bucket.lake.name
  role   = "roles/storage.objectUser"             # tighter than objectAdmin, still full object RW
  member = "serviceAccount:${var.dbt_runner_sa_email}"
}
```
 
Match `var.project_id`, `var.region`, and the runner SA to whatever `stmsn-infra` already uses. Then `terraform plan && terraform apply`.
 
## 2. Skip bucket lifecycle rules
 
Do not add a GCS lifecycle delete rule to prune old files. DuckLake owns file lifecycle and a naive age-based rule will delete Parquet the catalog still references. Reclamation is handled by DuckLake maintenance (`ducklake_expire_snapshots`, `ducklake_merge_adjacent_files`, `ducklake_cleanup_old_files`) on a weekly job instead.
 
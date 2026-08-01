output "meta_bucket_name" {
  value = module.meta.name
}

output "meta_bucket_url" {
  value = module.meta.url
}

output "bronze_bucket_name" {
  value = module.bronze.name
}

output "bronze_bucket_url" {
  value = module.bronze.url
}

output "silver_bucket_name" {
  value = module.silver.name
}

output "silver_bucket_url" {
  value = module.silver.url
}

output "gold_bucket_name" {
  value = module.gold.name
}

output "gold_bucket_url" {
  value = module.gold.url
}

output "lake_bucket_name" {
  value = module.lake.name
}

output "lake_bucket_url" {
  value = module.lake.url
}

# Retrieve with `terraform output -json guest_gcs_credentials` and hand over
# through a password manager. Guests set these as GCS_KEY_ID / GCS_SECRET,
# matching the env var names the stmsn-runner job uses.
output "guest_gcs_credentials" {
  sensitive = true
  value = {
    for k, email in var.guest_readers : k => {
      email  = email
      key_id = google_storage_hmac_key.guest_reader[k].access_id
      secret = google_storage_hmac_key.guest_reader[k].secret
    }
  }
}

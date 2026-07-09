module "meta" {
  source     = "./modules/gcs_bucket"
  name       = "stmsn-meta"
  project    = var.project_id
  location   = var.region
  versioning = true
}

module "bronze" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-bronze"
  project  = var.project_id
  location = var.region
}

module "silver" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-silver"
  project  = var.project_id
  location = var.region
}

module "gold" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-gold"
  project  = var.project_id
  location = var.region
}

module "lake" {
  source   = "./modules/gcs_bucket"
  name     = "stmsn-lake"
  project  = var.project_id
  location = var.region
}

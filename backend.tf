terraform {
  backend "gcs" {
    bucket = "stmsn-tfstate"
    prefix = "infra"
  }
}
